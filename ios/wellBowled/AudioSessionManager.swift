import AVFoundation
import Foundation
import os

private let log = Logger(subsystem: "com.wellbowled", category: "AudioSession")

/// Manages AVAudioSession for simultaneous mic capture + speaker playback.
/// Configures for Live API: mic at 16kHz, speaker for 24kHz PCM playback.
final class AudioSessionManager {

    static let shared = AudioSessionManager()

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    /// 24kHz mono 16-bit PCM format for Live API output playback
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24000,
        channels: 1,
        interleaved: true
    )!

    private init() {}

    // MARK: - Session Configuration

    func configure() throws {
        log.debug("Configuring AVAudioSession: .playAndRecord, .voiceChat")
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        // Request 16kHz — may not be honored, camera audio will need resampling
        try session.setPreferredSampleRate(16000)
        try session.setActive(true)
        log.debug("AVAudioSession active. Sample rate: \(session.sampleRate)Hz, I/O buffer: \(session.ioBufferDuration)s")

        // Observe interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
    }

    // MARK: - Audio Playback Engine

    func startPlaybackEngine() throws {
        guard !audioEngine.isRunning else {
            log.debug("Playback engine already running")
            return
        }
        log.debug("Starting playback engine (24kHz mono Int16)")
        audioEngine.attach(playerNode)
        isPlayerAttached = true
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        try audioEngine.start()
        playerNode.play()
        log.debug("Playback engine started")
    }

    private var isPlayerAttached = false

    func stopPlaybackEngine() {
        log.debug("Stopping playback engine")
        playerNode.stop()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isPlayerAttached {
            audioEngine.detach(playerNode)
            isPlayerAttached = false
        }
    }

    /// Schedule raw 24kHz 16-bit PCM data for playback
    func playPCMChunk(_ data: Data) {
        guard audioEngine.isRunning else { return }

        let frameCount = UInt32(data.count / 2) // 16-bit = 2 bytes per sample
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount) else { return }

        buffer.frameLength = frameCount

        // Copy PCM bytes into buffer
        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(buffer.int16ChannelData![0], baseAddress, data.count)
            }
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    // MARK: - Audio Resampling

    /// Convert CMSampleBuffer from camera mic to 16kHz 16-bit mono PCM Data
    static func resampleToLiveAPI(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }

        let sourceSampleRate = asbd.pointee.mSampleRate
        let sourceChannels = asbd.pointee.mChannelsPerFrame

        // Get raw audio bytes
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                     totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard let ptr = dataPointer, length > 0 else { return nil }

        let sourceData = Data(bytes: ptr, count: length)

        // If already 16kHz mono 16-bit, return as-is
        if sourceSampleRate == 16000 && sourceChannels == 1 {
            return sourceData
        }

        // Simple decimation: convert to 16-bit samples, take every Nth sample, mono-mix if stereo
        let bytesPerSample = Int(asbd.pointee.mBitsPerChannel / 8)
        let isFloat = asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let ratio = Int(sourceSampleRate / 16000)
        guard ratio > 0 else { return sourceData }

        let totalSamples = length / (bytesPerSample * Int(sourceChannels))
        let outputSamples = totalSamples / ratio
        var output = Data(capacity: outputSamples * 2) // 16-bit output

        sourceData.withUnsafeBytes { rawBuffer in
            for i in stride(from: 0, to: totalSamples, by: ratio) {
                var sample: Int16

                if isFloat && bytesPerSample == 4 {
                    // Float32 source
                    let offset = i * Int(sourceChannels) * 4
                    guard offset + 3 < length else { return }
                    let floatVal = rawBuffer.load(fromByteOffset: offset, as: Float32.self)
                    sample = Int16(clamping: Int(floatVal * 32767))
                } else if bytesPerSample == 2 {
                    // Int16 source
                    let offset = i * Int(sourceChannels) * 2
                    guard offset + 1 < length else { return }
                    sample = rawBuffer.load(fromByteOffset: offset, as: Int16.self)
                } else {
                    return
                }

                // Mono-mix: just take first channel (already done by offset calc)
                withUnsafeBytes(of: sample) { output.append(contentsOf: $0) }
            }
        }

        return output
    }

    // MARK: - Interruption Handling

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            log.info("Audio interruption began")
            playerNode.pause()
        case .ended:
            log.info("Audio interruption ended, reactivating")
            try? AVAudioSession.sharedInstance().setActive(true)
            playerNode.play()
        @unknown default:
            break
        }
    }
}
