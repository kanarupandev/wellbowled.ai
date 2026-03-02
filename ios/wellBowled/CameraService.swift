import AVFoundation
import Foundation
import os
import UIKit

private let log = Logger(subsystem: "com.wellbowled", category: "Camera")

/// Camera capture service with 3 output streams:
/// - videoOutput: feeds frames to DeliveryDetector + GeminiLiveService
/// - audioOutput: feeds mic PCM to GeminiLiveService
/// - movieOutput: records .mov for post-session clip extraction
final class CameraService: NSObject, CameraProviding {

    // MARK: - Public State

    private(set) var isRecording: Bool = false
    private(set) var currentRecordingURL: URL?

    /// Current camera position (back by default)
    private(set) var cameraPosition: AVCaptureDevice.Position = .back

    /// Called for each video frame (for MediaPipe + Live API)
    var onVideoFrame: ((CMSampleBuffer, CMTime) -> Void)?

    /// Called for each audio sample (for Live API mic input)
    var onAudioSample: ((CMSampleBuffer) -> Void)?

    /// Preview layer for SwiftUI integration
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    // MARK: - Private

    private let captureSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private let sessionQueue = DispatchQueue(label: "com.wellbowled.camera.session")
    private let videoProcessingQueue = DispatchQueue(label: "com.wellbowled.camera.video")
    private let audioProcessingQueue = DispatchQueue(label: "com.wellbowled.camera.audio")

    private var isConfigured = false
    private var currentVideoInput: AVCaptureDeviceInput?
    private var lastVideoSourcePosition: AVCaptureDevice.Position?

    // MARK: - CameraProviding

    func startSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                if !self.isConfigured {
                    self.configureSession()
                }
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                    log.debug("Capture session started")
                }
                continuation.resume()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            log.debug("Capture session stopped")
        }
    }

    func startRecording() throws {
        guard !isRecording else { return }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let connection = self.movieOutput.connection(with: .video),
                  connection.isActive else {
                log.warning("No active video connection for recording")
                return
            }
            self.currentRecordingURL = outputURL
            self.isRecording = true
            self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
            log.debug("Recording started: \(outputURL.lastPathComponent)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            self.isRecording = false
            log.debug("Recording stopped")
        }
    }

    // MARK: - Camera Toggle

    /// Toggle between front and back camera. Safe to call during session.
    func toggleCamera(onSwitched: ((AVCaptureDevice.Position) -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = self.cameraPosition == .back ? .front : .back
            let previousInput = self.currentVideoInput

            guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newCamera) else {
                log.error("Cannot create input for \(newPosition == .front ? "front" : "back") camera")
                return
            }

            var switched = false
            self.captureSession.beginConfiguration()

            // Remove old video input
            if let current = previousInput {
                self.captureSession.removeInput(current)
            }

            // Add new video input
            if self.captureSession.canAddInput(newInput) {
                self.captureSession.addInput(newInput)
                self.currentVideoInput = newInput
                self.cameraPosition = newPosition
                switched = true
            } else {
                // Rollback
                if let old = previousInput, self.captureSession.canAddInput(old) {
                    self.captureSession.addInput(old)
                }
                log.error("Could not add \(newPosition == .front ? "front" : "back") camera input")
            }

            self.captureSession.commitConfiguration()

            guard switched else { return }

            // Rebuild video data output after input change has been committed.
            self.captureSession.beginConfiguration()
            self.rebuildVideoDataOutput()
            self.captureSession.commitConfiguration()

            self.applyVideoConnectionSettings(for: newPosition)
            self.configureCameraFrameRate(newCamera, targetFPS: 30)
            log.info("Switched to \(newPosition == .front ? "front" : "back") camera")

            DispatchQueue.main.async {
                onSwitched?(newPosition)
            }
        }
    }

    // MARK: - Configuration

    private func configureSession() {
        guard !isConfigured else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720

        // Video input (back camera default)
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let videoInput = try? AVCaptureDeviceInput(device: camera),
           captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
            currentVideoInput = videoInput
            cameraPosition = .back
            configureCameraFrameRate(camera, targetFPS: 30)
        }

        // Audio input (microphone)
        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        // Video data output (frames for MediaPipe + Live API)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Audio data output (mic for Live API)
        audioOutput.setSampleBufferDelegate(self, queue: audioProcessingQueue)
        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
        }

        // Movie file output (recording for clip extraction)
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }

        captureSession.commitConfiguration()
        applyVideoConnectionSettings(for: cameraPosition)
        isConfigured = true
        log.debug("Camera configured: 720p, back camera, 30fps")
    }

    /// Force-rebuild video data output connection so callbacks follow the currently active camera input.
    /// This avoids stale routing after runtime camera flips where preview updates but data output doesn't.
    private func rebuildVideoDataOutput() {
        if captureSession.outputs.contains(videoOutput) {
            captureSession.removeOutput(videoOutput)
        }
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            log.error("Failed to re-add video output after camera switch")
        }
    }

    private func applyVideoConnectionSettings(for position: AVCaptureDevice.Position) {
        let shouldMirror = position == .front

        if let previewConnection = previewLayer.connection {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            if previewConnection.isVideoMirroringSupported {
                previewConnection.isVideoMirrored = shouldMirror
            }
        }

        if let videoConnection = videoOutput.connection(with: .video) {
            videoConnection.automaticallyAdjustsVideoMirroring = false
            if videoConnection.isVideoMirroringSupported {
                videoConnection.isVideoMirrored = shouldMirror
            }
        }

        if let movieConnection = movieOutput.connection(with: .video) {
            movieConnection.automaticallyAdjustsVideoMirroring = false
            if movieConnection.isVideoMirroringSupported {
                movieConnection.isVideoMirrored = shouldMirror
            }
        }
    }

    private func configureCameraFrameRate(_ camera: AVCaptureDevice, targetFPS: Int) {
        do {
            try camera.lockForConfiguration()
            let targetDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            for range in camera.activeFormat.videoSupportedFrameRateRanges {
                if Int(range.maxFrameRate) >= targetFPS {
                    camera.activeVideoMinFrameDuration = targetDuration
                    camera.activeVideoMaxFrameDuration = targetDuration
                    break
                }
            }
            camera.unlockForConfiguration()
        } catch {
            log.warning("Could not set frame rate: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sample Buffer Delegate (Video + Audio)

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === videoOutput {
            if let sourcePosition = connection.inputPorts.compactMap({ $0.sourceDevicePosition }).first,
               sourcePosition != lastVideoSourcePosition {
                lastVideoSourcePosition = sourcePosition
                log.info("Video output source: \(sourcePosition == .front ? "front" : "back")")
            }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            onVideoFrame?(sampleBuffer, timestamp)
        } else if output === audioOutput {
            onAudioSample?(sampleBuffer)
        }
    }
}

// MARK: - Recording Delegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if let error {
            log.error("Recording error: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(
            name: .wbDidFinishRecording,
            object: nil,
            userInfo: ["videoURL": outputFileURL]
        )
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let wbDidFinishRecording = Notification.Name("wbDidFinishRecording")
}
