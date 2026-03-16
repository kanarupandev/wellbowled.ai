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

    /// 24kHz mono Float32 format — AVAudioEngine works natively in Float32;
    /// Int16 connections can fail silently when routing through Bluetooth codecs.
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24000,
        channels: 1,
        interleaved: false
    )!
    private var observersInstalled = false
    private let startupWhizzLock = NSLock()
    private var startupWhizzPlayed = false
    private let micTapLock = NSLock()
    private var isMicTapInstalled = false
    private var micChunkHandler: ((Data) -> Void)?
    private var micChunkCount = 0

    private init() {}
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func currentRouteSummary() -> String {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")
        let inputs = session.currentRoute.inputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")
        return "inputs=[\(inputs)] outputs=[\(outputs)]"
    }

    // MARK: - Session Configuration

    func configure() throws {
        log.debug("Configuring AVAudioSession: .playAndRecord, .default")
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        // Let the system choose optimal sample rate and route for conversational audio.
        // For live two-way mode, prioritize HFP-capable Bluetooth routes (input + output).
        try session.setActive(true)
        applyPreferredRoute(session, preferBluetoothHFPInput: false)
        log.debug("AVAudioSession active. Sample rate: \(session.sampleRate)Hz, I/O buffer: \(session.ioBufferDuration)s")
        logCurrentRoute(session)

        installObserversIfNeeded(session: session)
    }

    // MARK: - Audio Playback Engine

    func startPlaybackEngine() throws {
        guard !audioEngine.isRunning else {
            log.debug("Playback engine already running")
            return
        }
        log.debug("Starting playback engine (24kHz mono Float32)")
        // Reset engine so output node picks up current audio session hardware format.
        audioEngine.reset()
        audioEngine.attach(playerNode)
        isPlayerAttached = true
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        audioEngine.prepare()
        try audioEngine.start()
        playerNode.play()
        log.debug("Playback engine started, output sr=\(self.audioEngine.outputNode.outputFormat(forBus: 0).sampleRate)")
    }

    private var isPlayerAttached = false

    /// Installs a microphone tap on the app audio session route (Bluetooth/wired/built-in)
    /// and emits 16kHz PCM chunks for Gemini Live upload.
    @discardableResult
    func startLiveInputCapture(onChunk: @escaping (Data) -> Void) -> Bool {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            log.error("Cannot install live input tap: invalid input format sr=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount)")
            return false
        }

        micTapLock.lock()
        defer { micTapLock.unlock() }
        micChunkHandler = onChunk
        micChunkCount = 0

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let pcm = Self.resamplePCMBufferToLiveAPI(buffer) else { return }
            self.micTapLock.lock()
            self.micChunkCount += 1
            let count = self.micChunkCount
            let handler = self.micChunkHandler
            self.micTapLock.unlock()
            if count == 1 || count % 100 == 0 {
                log.debug("Live mic chunk count=\(count) bytes=\(pcm.count)")
            }
            handler?(pcm)
        }

        micTapLock.lock()
        defer { micTapLock.unlock() }
        isMicTapInstalled = true
        log.info("Live input tap installed: sr=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount)")
        log.debug("Live input tap route: \(self.currentRouteSummary(), privacy: .public)")
        return true
    }

    func stopLiveInputCapture() {
        micTapLock.lock()
        defer { micTapLock.unlock() }
        let wasInstalled = isMicTapInstalled
        isMicTapInstalled = false
        micChunkHandler = nil
        micChunkCount = 0

        guard wasInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        log.debug("Live input tap removed")
    }

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

    func deactivateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            log.debug("AVAudioSession deactivated")
        } catch {
            log.warning("Failed to deactivate AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Schedule raw 24kHz 16-bit PCM data for playback (converted to Float32 for engine compatibility)
    func playPCMChunk(_ data: Data) {
        if !audioEngine.isRunning {
            log.warning("playPCMChunk received while engine stopped; attempting restart")
            do {
                try startPlaybackEngine()
            } catch {
                log.error("playPCMChunk restart failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        let frameCount = UInt32(data.count / 2) // 16-bit = 2 bytes per sample
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount) else { return }

        buffer.frameLength = frameCount

        // Convert Int16 PCM → Float32 (AVAudioEngine native format, required for Bluetooth routing)
        data.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.baseAddress?.assumingMemoryBound(to: Int16.self),
                  let dst = buffer.floatChannelData?[0] else { return }
            for i in 0..<Int(frameCount) {
                dst[i] = Float(src[i]) / 32768.0
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
            log.debug("Player node was stopped; resumed before scheduling PCM")
        }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// One-time startup cue to verify in-app audio routing (including Bluetooth output).
    func playStartupWhizzIfNeeded() {
        startupWhizzLock.lock()
        let shouldPlay = !startupWhizzPlayed
        if shouldPlay { startupWhizzPlayed = true }
        startupWhizzLock.unlock()
        guard shouldPlay else { return }

        do {
            try configure()
            try startPlaybackEngine()
            let pcm = Self.makeStartupWhizzPCM()
            playPCMChunk(pcm)
            log.debug("Startup cue played")
        } catch {
            log.warning("Startup cue failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Audio Resampling

    /// Convert CMSampleBuffer from camera mic to 16kHz 16-bit mono PCM Data
    static func resampleToLiveAPI(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }

        let sourceSampleRate = asbd.pointee.mSampleRate
        let sourceChannels = asbd.pointee.mChannelsPerFrame
        guard sourceSampleRate > 0, sourceChannels > 0 else { return nil }

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

        // Convert to mono Float samples, then resample with linear interpolation.
        let bytesPerSample = Int(asbd.pointee.mBitsPerChannel / 8)
        let isFloat = asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
        guard bytesPerSample == 2 || (isFloat && bytesPerSample == 4) else {
            return nil
        }

        let frameStride = bytesPerSample * Int(sourceChannels)
        let totalFrames = length / frameStride
        guard totalFrames > 1 else { return nil }

        var mono = [Float](repeating: 0, count: totalFrames)
        sourceData.withUnsafeBytes { rawBuffer in
            for frame in 0..<totalFrames {
                let base = frame * frameStride
                if isFloat && bytesPerSample == 4 {
                    let value = rawBuffer.load(fromByteOffset: base, as: Float32.self)
                    mono[frame] = Float(value)
                } else {
                    let value = rawBuffer.load(fromByteOffset: base, as: Int16.self)
                    mono[frame] = Float(value) / 32768.0
                }
            }
        }

        return linearResampleToPCM16k(mono: mono, sourceSampleRate: sourceSampleRate)
    }

    private static func resamplePCMBufferToLiveAPI(_ buffer: AVAudioPCMBuffer) -> Data? {
        let sourceSampleRate = buffer.format.sampleRate
        guard sourceSampleRate > 0, buffer.frameLength > 1 else { return nil }

        let frameCount = Int(buffer.frameLength)
        var mono = [Float](repeating: 0, count: frameCount)

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let floatData = buffer.floatChannelData else { return nil }
            let channel = floatData[0]
            for i in 0..<frameCount {
                mono[i] = channel[i]
            }
        case .pcmFormatInt16:
            guard let intData = buffer.int16ChannelData else { return nil }
            let channel = intData[0]
            for i in 0..<frameCount {
                mono[i] = Float(channel[i]) / 32768.0
            }
        default:
            return nil
        }

        return linearResampleToPCM16k(mono: mono, sourceSampleRate: sourceSampleRate)
    }

    private static func linearResampleToPCM16k(mono: [Float], sourceSampleRate: Double) -> Data? {
        guard !mono.isEmpty, sourceSampleRate > 0 else { return nil }
        let targetSampleRate = 16000.0
        let outputFrames = max(Int(Double(mono.count) * (targetSampleRate / sourceSampleRate)), 1)
        var output = Data(capacity: outputFrames * 2)
        let step = sourceSampleRate / targetSampleRate

        for outIndex in 0..<outputFrames {
            let srcPosition = Double(outIndex) * step
            let srcIndex = min(Int(srcPosition), mono.count - 1)
            let nextIndex = min(srcIndex + 1, mono.count - 1)
            let fraction = Float(srcPosition - Double(srcIndex))

            let interpolated = mono[srcIndex] + (mono[nextIndex] - mono[srcIndex]) * fraction
            let clamped = max(-1.0, min(1.0, interpolated))
            var sample = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: &sample) { output.append(contentsOf: $0) }
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
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                if !audioEngine.isRunning {
                    try startPlaybackEngine()
                } else if !playerNode.isPlaying {
                    playerNode.play()
                }
            } catch {
                log.warning("Audio interruption recovery failed: \(error.localizedDescription, privacy: .public)")
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        var reasonDescription = "unknown"
        if let info = notification.userInfo,
           let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
           let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) {
            reasonDescription = String(describing: reason)
            log.debug("Audio route changed: reason=\(reasonDescription, privacy: .public)")
        } else {
            log.debug("Audio route changed: reason=unknown")
        }
        let session = AVAudioSession.sharedInstance()
        applyPreferredRoute(session, preferBluetoothHFPInput: false)
        logCurrentRoute(session)
        restartPlaybackEngineAfterRouteChange(reason: reasonDescription)
    }

    private func applyPreferredRoute(_ session: AVAudioSession, preferBluetoothHFPInput: Bool) {
        guard preferBluetoothHFPInput else {
            do {
                try session.setPreferredInput(nil)
                log.debug("Preferred input reset to system default")
            } catch {
                log.warning("Could not set preferred input: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        let bluetoothInput = session.availableInputs?.first {
            $0.portType == .bluetoothHFP
        }

        do {
            try session.setPreferredInput(bluetoothInput)
            if let bluetoothInput {
                log.info("Preferred input set to Bluetooth HFP: \(bluetoothInput.portName, privacy: .public)")
            } else {
                log.debug("No Bluetooth HFP input available; using system default input")
            }
        } catch {
            log.warning("Could not set preferred input: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func restartPlaybackEngineAfterRouteChange(reason: String) {
        guard audioEngine.isRunning else { return }
        log.debug("Restarting playback engine after route change (\(reason, privacy: .public))")
        stopPlaybackEngine()
        do {
            try startPlaybackEngine()
            log.debug("Playback engine restarted after route change")
        } catch {
            log.warning("Playback engine restart failed after route change: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func logCurrentRoute(_ session: AVAudioSession) {
        let outputs = session.currentRoute.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")
        let inputs = session.currentRoute.inputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")
        log.debug("Current audio route -> outputs: [\(outputs, privacy: .public)] inputs: [\(inputs, privacy: .public)]")
    }

    /// Fast-ball whirling startup cue — 1.2s, energetic, sharp, loud.
    private static func makeStartupWhizzPCM(
        sampleRate: Double = 24000,
        duration: Double = 1.2
    ) -> Data {
        let frameCount = max(Int(sampleRate * duration), 1)
        var data = Data(capacity: frameCount * 2)

        let twoPi = 2.0 * Double.pi
        var phase1 = 0.0
        var phase2 = 0.0
        var phase3 = 0.0

        for frame in 0..<frameCount {
            let t = Double(frame) / Double(max(frameCount - 1, 1))

            // Rising sweep: 800Hz → 2400Hz (fast-ball whirl)
            let freq1 = 800.0 + 1600.0 * t
            // High harmonic shimmer
            let freq2 = 1800.0 + 2400.0 * t
            // Sub punch
            let freq3 = 400.0

            phase1 += twoPi * freq1 / sampleRate
            phase2 += twoPi * freq2 / sampleRate
            phase3 += twoPi * freq3 / sampleRate

            // Sharp attack, sustained energy, quick tail
            let attack = min(t / 0.002, 1.0)
            let sustain: Double = t < 0.7 ? 1.0 : exp(-6.0 * (t - 0.7))
            let envelope = attack * sustain

            // Initial crack
            let click = frame < 48 ? (1.0 - Double(frame) / 48.0) * 0.6 : 0.0

            let sweep = sin(phase1) * 0.7
            let shimmer = sin(phase2) * 0.25
            let sub = sin(phase3) * 0.2 * (t < 0.3 ? 1.0 : exp(-5.0 * (t - 0.3)))

            let signal = (sweep + shimmer + sub) * envelope + click
            let clamped = max(-1.0, min(1.0, signal))
            var sample = Int16(clamped * Double(Int16.max))
            withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
        }

        return data
    }

    private func installObserversIfNeeded(session: AVAudioSession) {
        guard !observersInstalled else { return }
        observersInstalled = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: session
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
    }
}
