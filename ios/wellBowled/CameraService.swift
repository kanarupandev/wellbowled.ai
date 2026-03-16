import AVFoundation
import Foundation
import os
import UIKit

private let log = Logger(subsystem: "com.wellbowled", category: "Camera")

/// Camera capture service with 3 output streams:
/// - videoOutput: feeds frames to DeliveryDetector + GeminiLiveService
/// - audioOutput: feeds mic PCM to GeminiLiveService
/// - movieOutput: records .mov for post-session clip extraction
final class CameraService: NSObject, CameraProviding, @unchecked Sendable {

    // MARK: - Public State

    var isRecording: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRecording
    }

    var currentRecordingURL: URL? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _currentRecordingURL
    }

    var recordedSegmentURLs: [URL] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _recordedSegmentURLs
    }

    /// Current camera position (back by default)
    var cameraPosition: AVCaptureDevice.Position {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _cameraPosition
    }

    /// Called for each video frame (for MediaPipe + Live API)
    var onVideoFrame: ((CMSampleBuffer, CMTime) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _onVideoFrame
        }
        set {
            stateLock.lock()
            _onVideoFrame = newValue
            stateLock.unlock()
        }
    }

    /// Called for each audio sample (for Live API mic input)
    var onAudioSample: ((CMSampleBuffer) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _onAudioSample
        }
        set {
            stateLock.lock()
            _onAudioSample = newValue
            stateLock.unlock()
        }
    }

    /// Preview layer for SwiftUI integration
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    /// Capture session exposed for preview wrappers that manage their own preview layer.
    var previewSession: AVCaptureSession { captureSession }

    // MARK: - Private

    private let captureSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private let sessionQueue = DispatchQueue(label: "com.wellbowled.camera.session")
    private let videoProcessingQueue = DispatchQueue(label: "com.wellbowled.camera.video")
    private let audioProcessingQueue = DispatchQueue(label: "com.wellbowled.camera.audio")
    private let stateLock = NSLock()

    private var isConfigured = false
    private var currentVideoInput: AVCaptureDeviceInput?
    private var lastVideoSourcePosition: AVCaptureDevice.Position?
    private var _isRecording = false
    private var _currentRecordingURL: URL?
    private var _recordedSegmentURLs: [URL] = []
    private var _cameraPosition: AVCaptureDevice.Position = .back
    private var _onVideoFrame: ((CMSampleBuffer, CMTime) -> Void)?
    private var _onAudioSample: ((CMSampleBuffer) -> Void)?
    private var videoFrameCounter = 0
    private var audioSampleCounter = 0

    /// When true, camera targets 120fps for speed estimation accuracy.
    private var speedMode = false

    /// Enable or disable high-FPS mode for speed calibration.
    func setSpeedMode(_ enabled: Bool) {
        stateLock.lock()
        speedMode = enabled
        stateLock.unlock()
    }

    private var effectiveTargetFPS: Int {
        speedMode ? WBConfig.speedCalibrationFPS : WBConfig.cameraTargetFPS
    }

    private var effectiveMaxFPS: Int {
        speedMode ? WBConfig.speedCalibrationFPS : WBConfig.cameraMaxFPS
    }

    private struct CameraFormatChoice {
        let format: AVCaptureDevice.Format
        let fps: Double
        let width: Int32
        let height: Int32

        var pixelCount: Int64 { Int64(width) * Int64(height) }
    }

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
                    self.videoFrameCounter = 0
                    self.audioSampleCounter = 0
                    self.captureSession.startRunning()
                    log.debug("Capture session started")
                }
                print(
                    "🎥 [CameraService] startSession running=\(self.captureSession.isRunning) " +
                    "inputs=\(self.captureSession.inputs.count) outputs=\(self.captureSession.outputs.count)"
                )
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
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isRecording else {
                log.debug("startRecording ignored: already recording")
                return
            }
            guard let connection = self.movieOutput.connection(with: .video),
                  connection.isActive else {
                log.warning("No active video connection for recording")
                return
            }
            self.setRecordingStarted(url: outputURL)
            self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
            log.debug("Recording started: \(outputURL.lastPathComponent)")
        }
    }

    func resetRecordingSegments() {
        stateLock.lock()
        _recordedSegmentURLs = []
        _currentRecordingURL = nil
        _isRecording = false
        stateLock.unlock()
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.isRecording else {
                log.debug("stopRecording ignored: not currently recording")
                return
            }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            self.setRecordingStopped()
            log.debug("Recording stopped")
        }
    }

    // MARK: - Camera Toggle

    /// Toggle between front and back camera. Safe to call during session.
    func toggleCamera(onSwitched: ((AVCaptureDevice.Position) -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let wasRecording = self.isRecording
            if wasRecording && self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
                self.setRecordingStopped()
                log.info("Closed active recording segment before camera switch")
            }

            let newPosition: AVCaptureDevice.Position = self.cameraPosition == .back ? .front : .back
            let previousInput = self.currentVideoInput

            guard let newInput = self.makeVideoInput(for: newPosition) else {
                log.error("Cannot create input for \(newPosition == .front ? "front" : "back") camera")
                return
            }
            let newCamera = newInput.device

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
                self.setCameraPosition(newPosition)
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
            if WBConfig.enableAdvancedCameraTuning {
                self.configureCameraCaptureSettings(newCamera, position: newPosition)
            }

            if wasRecording {
                do {
                    try self.startRecording()
                    log.info("Started new recording segment after camera switch")
                } catch {
                    log.error("Failed to restart recording after camera switch: \(error.localizedDescription, privacy: .public)")
                }
            }
            log.info("Switched to \(newPosition == .front ? "front" : "back") camera")
            print("🎥 [CameraService] switched to \(newPosition == .front ? "front" : "back")")

            DispatchQueue.main.async {
                onSwitched?(newPosition)
            }
        }
    }

    // MARK: - Configuration

    private func configureSession() {
        guard !isConfigured else { return }
        print("🎥 [CameraService] configureSession begin")

        // Keep app-managed AVAudioSession settings stable (Bluetooth routing, mode, etc.).
        captureSession.automaticallyConfiguresApplicationAudioSession = false

        captureSession.beginConfiguration()
        configureCapturePreset()

        // Video input (prefer back camera; fall back to front)
        if let videoInput = makeVideoInput(for: .back) ?? makeVideoInput(for: .front),
           captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
            currentVideoInput = videoInput
            let selectedPosition = videoInput.device.position
            setCameraPosition(selectedPosition)
            if WBConfig.enableAdvancedCameraTuning {
                configureCameraCaptureSettings(videoInput.device, position: selectedPosition)
            }
            print("🎥 [CameraService] video input added (\(selectedPosition == .front ? "front" : "back"))")
        } else {
            log.error("No camera video input could be configured")
            print("❌ [CameraService] no camera video input available")
        }

        // Audio input (microphone)
        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
            log.info("Audio input added: \(audioInput.device.localizedName, privacy: .public)")
        } else {
            log.warning("Audio input unavailable; Live mic capture may fail")
        }

        // Video data output (frames for MediaPipe + Live API)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            print("🎥 [CameraService] video output added")
        } else {
            print("❌ [CameraService] failed to add video output")
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
        log.debug("Camera configured (advanced tuning \(WBConfig.enableAdvancedCameraTuning ? "enabled" : "disabled"))")
        print("🎥 [CameraService] configureSession end inputs=\(captureSession.inputs.count) outputs=\(captureSession.outputs.count)")
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
        let desiredOrientation = videoOrientationForCurrentDevice()

        if let previewConnection = previewLayer.connection {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            if previewConnection.isVideoMirroringSupported {
                previewConnection.isVideoMirrored = shouldMirror
            }
            if previewConnection.isVideoOrientationSupported {
                previewConnection.videoOrientation = desiredOrientation
            }
        }

        if let videoConnection = videoOutput.connection(with: .video) {
            videoConnection.automaticallyAdjustsVideoMirroring = false
            if videoConnection.isVideoMirroringSupported {
                videoConnection.isVideoMirrored = shouldMirror
            }
            if videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = desiredOrientation
            }
            if videoConnection.isVideoStabilizationSupported {
                videoConnection.preferredVideoStabilizationMode = .auto
            }
        }

        if let movieConnection = movieOutput.connection(with: .video) {
            movieConnection.automaticallyAdjustsVideoMirroring = false
            if movieConnection.isVideoMirroringSupported {
                movieConnection.isVideoMirrored = shouldMirror
            }
            if movieConnection.isVideoOrientationSupported {
                movieConnection.videoOrientation = desiredOrientation
            }
            if movieConnection.isVideoStabilizationSupported {
                movieConnection.preferredVideoStabilizationMode = .auto
            }
        }
    }

    private func videoOrientationForCurrentDevice() -> AVCaptureVideoOrientation {
        if WBConfig.forcePortraitCameraOrientation {
            return .portrait
        }

        switch UIDevice.current.orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .portrait
        }
    }

    private func makeVideoInput(for position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInTripleCamera,
            .builtInUltraWideCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )
        if let device = discovery.devices.first {
            return try? AVCaptureDeviceInput(device: device)
        }
        return nil
    }

    private func configureCapturePreset() {
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
            return
        }
        if captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720
        }
    }

    private func configureCameraCaptureSettings(_ camera: AVCaptureDevice, position: AVCaptureDevice.Position) {
        let targetFPS = Double(effectiveTargetFPS)
        let maxFPS = Double(effectiveMaxFPS)
        let fallbackFPS = WBConfig.cameraFallbackFPS

        do {
            try camera.lockForConfiguration()

            if let choice = selectPreferredFormat(
                for: camera,
                targetFPS: targetFPS,
                maxFPS: maxFPS,
                preferredMinWidth: WBConfig.cameraPreferredMinWidth,
                preferredMinHeight: WBConfig.cameraPreferredMinHeight
            ) {
                camera.activeFormat = choice.format
                let chosenFPS = max(1, Int(choice.fps.rounded()))
                let frameDuration = CMTime(value: 1, timescale: CMTimeScale(chosenFPS))
                camera.activeVideoMinFrameDuration = frameDuration
                camera.activeVideoMaxFrameDuration = frameDuration

                if camera.isFocusModeSupported(.continuousAutoFocus) {
                    camera.focusMode = .continuousAutoFocus
                }
                if camera.isExposureModeSupported(.continuousAutoExposure) {
                    camera.exposureMode = .continuousAutoExposure
                }
                if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    camera.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                if camera.isSmoothAutoFocusSupported {
                    camera.isSmoothAutoFocusEnabled = true
                }
                if camera.isLowLightBoostSupported {
                    camera.automaticallyEnablesLowLightBoostWhenAvailable = true
                }

                log.info(
                    "Camera tuned (\(position == .front ? "front" : "back")): \(choice.width)x\(choice.height) @ \(chosenFPS)fps"
                )
            } else {
                configureFallbackFrameRate(camera, targetFPS: fallbackFPS)
                log.warning("No preferred camera format found; using fallback \(fallbackFPS)fps")
            }
            camera.unlockForConfiguration()
        } catch {
            log.warning("Could not configure camera format/fps: \(error.localizedDescription)")
        }
    }

    private func selectPreferredFormat(
        for camera: AVCaptureDevice,
        targetFPS: Double,
        maxFPS: Double,
        preferredMinWidth: Int32,
        preferredMinHeight: Int32
    ) -> CameraFormatChoice? {
        var preferredTargetChoice: CameraFormatChoice?
        var targetChoice: CameraFormatChoice?
        var preferredChoice: CameraFormatChoice?
        var fallbackChoice: CameraFormatChoice?

        for format in camera.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let meetsPreferredResolution = dimensions.width >= preferredMinWidth && dimensions.height >= preferredMinHeight

            for range in format.videoSupportedFrameRateRanges {
                let cappedMaxFPS = min(range.maxFrameRate, maxFPS)
                guard cappedMaxFPS >= 1 else { continue }
                let chosenFPS = cappedMaxFPS >= targetFPS ? targetFPS : floor(cappedMaxFPS)
                let choice = CameraFormatChoice(
                    format: format,
                    fps: chosenFPS,
                    width: dimensions.width,
                    height: dimensions.height
                )
                let meetsTargetFPS = cappedMaxFPS >= targetFPS

                if meetsTargetFPS && meetsPreferredResolution &&
                    isHigherResolutionOrFPS(choice, than: preferredTargetChoice) {
                    preferredTargetChoice = choice
                }
                if meetsTargetFPS && isHigherResolutionOrFPS(choice, than: targetChoice) {
                    targetChoice = choice
                }
                if meetsPreferredResolution && isHigherFPSOrResolution(choice, than: preferredChoice) {
                    preferredChoice = choice
                }
                if isHigherFPSOrResolution(choice, than: fallbackChoice) {
                    fallbackChoice = choice
                }
            }
        }

        return preferredTargetChoice ?? targetChoice ?? preferredChoice ?? fallbackChoice
    }

    private func isHigherResolutionOrFPS(_ lhs: CameraFormatChoice, than rhs: CameraFormatChoice?) -> Bool {
        guard let rhs else { return true }
        if lhs.pixelCount != rhs.pixelCount {
            return lhs.pixelCount > rhs.pixelCount
        }
        return lhs.fps > rhs.fps
    }

    private func isHigherFPSOrResolution(_ lhs: CameraFormatChoice, than rhs: CameraFormatChoice?) -> Bool {
        guard let rhs else { return true }
        if lhs.fps != rhs.fps {
            return lhs.fps > rhs.fps
        }
        return lhs.pixelCount > rhs.pixelCount
    }

    private func configureFallbackFrameRate(_ camera: AVCaptureDevice, targetFPS: Int) {
        let targetDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        for range in camera.activeFormat.videoSupportedFrameRateRanges {
            if Int(range.maxFrameRate) >= targetFPS {
                camera.activeVideoMinFrameDuration = targetDuration
                camera.activeVideoMaxFrameDuration = targetDuration
                break
            }
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
            videoFrameCounter += 1
            if videoFrameCounter == 1 || videoFrameCounter % 180 == 0 {
                print("🎥 [CameraService] video frames received=\(videoFrameCounter)")
            }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let handler = onVideoFrame
            handler?(sampleBuffer, timestamp)
        } else if output === audioOutput {
            audioSampleCounter += 1
            if audioSampleCounter == 1 || audioSampleCounter % 240 == 0 {
                let routeInputs = AVAudioSession.sharedInstance().currentRoute.inputs
                    .map { "\($0.portType.rawValue):\($0.portName)" }
                    .joined(separator: ", ")
                print("🎤 [CameraService] audio samples received=\(audioSampleCounter) routeInputs=[\(routeInputs)]")
            }
            let handler = onAudioSample
            handler?(sampleBuffer)
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
        appendRecordedSegment(url: outputFileURL)
        log.debug("Recording segment finalized: \(outputFileURL.lastPathComponent, privacy: .public)")
        NotificationCenter.default.post(
            name: .wbDidFinishRecording,
            object: nil,
            userInfo: ["videoURL": outputFileURL]
        )
    }
}

// MARK: - Internal State Helpers

private extension CameraService {
    func appendRecordedSegment(url: URL) {
        stateLock.lock()
        if !_recordedSegmentURLs.contains(url) {
            _recordedSegmentURLs.append(url)
        }
        stateLock.unlock()
    }

    func setRecordingStarted(url: URL) {
        stateLock.lock()
        _currentRecordingURL = url
        _isRecording = true
        stateLock.unlock()
    }

    func setRecordingStopped() {
        stateLock.lock()
        _isRecording = false
        stateLock.unlock()
    }

    func setCameraPosition(_ position: AVCaptureDevice.Position) {
        stateLock.lock()
        _cameraPosition = position
        stateLock.unlock()
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let wbDidFinishRecording = Notification.Name("wbDidFinishRecording")
}
