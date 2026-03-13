import AVFoundation
import Foundation

/// Speaks delivery count, pace, and challenge info using AVSpeechSynthesizer.
/// Zero-latency, on-device, no network dependency.
final class TTSService: NSObject, SpeechAnnouncing, AVSpeechSynthesizerDelegate, @unchecked Sendable {

    private let synthesizer = AVSpeechSynthesizer()

    /// External flag: pause announcements when Live API mate is speaking.
    var mateSpeaking: Bool = false

    private(set) var isSpeaking: Bool = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - SpeechAnnouncing

    func announceDelivery(count: Int, pace: PaceBand) {
        let text = "\(count). \(pace.label)."
        speak(text)
    }

    func announceChallenge(target: String) {
        speak(target)
    }

    func announceChallengeResult(_ text: String) {
        speak(text)
    }

    func speak(_ text: String) {
        guard WBConfig.enableTTS, !mateSpeaking else { return }

        // Interrupt any current speech for delivery announcements
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = WBConfig.ttsRate
        utterance.voice = AVSpeechSynthesisVoice(language: WBConfig.ttsLanguage)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
