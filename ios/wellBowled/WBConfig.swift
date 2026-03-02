import Foundation

/// Central configuration for the wellBowled app.
/// All tunable thresholds, model names, and feature flags live here.
enum WBConfig {

    // MARK: - Gemini API

    /// Hardcoded default from .env (hackathon only — not for production)
    private static let defaultAPIKey = "AIzaSyCpkcQhnB9BuBMljG7beN_fBk4kg2lLahM"

    /// API key: UserDefaults override (persists across updates) → hardcoded default
    static var geminiAPIKey: String {
        get {
            // 1. UserDefaults (user changed via in-app Settings — persists until app deleted)
            if let key = UserDefaults.standard.string(forKey: "gemini_api_key"), !key.isEmpty {
                return key
            }
            // 2. Hardcoded default from .env
            return defaultAPIKey
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "gemini_api_key")
        }
    }

    /// Whether an API key is configured
    static var hasAPIKey: Bool { !geminiAPIKey.isEmpty }

    /// Live API model (native audio, validated in R17 experiment)
    static let liveAPIModel = "models/gemini-2.5-flash-native-audio-preview-12-2025"

    /// Analysis model (delivery type, post-session analysis)
    static let analysisModel = "gemini-3-pro-preview"

    /// Live API WebSocket endpoint
    static let liveAPIEndpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    /// generateContent REST endpoint
    static func generateContentURL(model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(geminiAPIKey)")!
    }

    // MARK: - Detection Thresholds

    /// Minimum angular velocity (rad/s) to trigger delivery detection.
    /// Calibrated from experiment 003: bowling peaks 1000-1900, walking ~200.
    static let wristVelocityThreshold: Double = 800.0

    /// Minimum seconds between detections (prevents double-counting).
    static let deliveryCooldown: Double = 5.0

    /// Process every Nth frame for MediaPipe (1 = every frame, 2 = every other)
    static let frameSkip: Int = 2

    // MARK: - Clip Extraction

    /// Seconds before delivery to include in clip
    static let clipPreRoll: Double = 3.0

    /// Seconds after delivery to include in clip
    static let clipPostRoll: Double = 2.0

    // MARK: - Live API

    /// Frames per second to send to Live API (low = less bandwidth, more stable)
    static let liveAPIFrameRate: Double = 2.0

    /// JPEG quality for frames sent to Live API (0-100)
    static let liveAPIJPEGQuality: Int = 60

    /// Max dimension for frames sent to Live API
    static let liveAPIMaxFrameDimension: Int = 512

    /// Max duration for a live coaching session (hackathon demo cap)
    static let liveSessionMaxDurationSeconds: TimeInterval = 180

    /// Voice for Live API audio responses (derived from persona)
    static var liveAPIVoice: String {
        matePersona.voiceName
    }

    // MARK: - Mate Persona

    /// Persona = language style + gender (8 options)
    enum MatePersona: String, CaseIterable {
        case aussieMale = "aussie_male"
        case aussieFemale = "aussie_female"
        case englishMale = "english_male"
        case englishFemale = "english_female"
        case tamilMale = "tamil_male"
        case tamilFemale = "tamil_female"
        case tanglishMale = "tanglish_male"
        case tanglishFemale = "tanglish_female"

        var label: String {
            switch self {
            case .aussieMale: return "Aussie Mate"
            case .aussieFemale: return "Aussie Mate"
            case .englishMale: return "English"
            case .englishFemale: return "English"
            case .tamilMale: return "தமிழ்"
            case .tamilFemale: return "தமிழ்"
            case .tanglishMale: return "Tanglish"
            case .tanglishFemale: return "Tanglish"
            }
        }

        var genderLabel: String {
            isMale ? "Male" : "Female"
        }

        var isMale: Bool {
            switch self {
            case .aussieMale, .englishMale, .tamilMale, .tanglishMale: return true
            case .aussieFemale, .englishFemale, .tamilFemale, .tanglishFemale: return false
            }
        }

        /// Gemini Live API voice name
        var voiceName: String {
            isMale ? "Achird" : "Aoede"  // Friendly male / Breezy female
        }

        /// TTS language code for iOS AVSpeechSynthesizer
        var ttsLanguage: String {
            switch self {
            case .aussieMale, .aussieFemale: return "en-AU"
            case .englishMale, .englishFemale: return "en-US"
            case .tamilMale, .tamilFemale: return "ta-IN"
            case .tanglishMale, .tanglishFemale: return "en-IN"
            }
        }

        var personaStyle: PersonaStyle {
            switch self {
            case .aussieMale, .aussieFemale: return .aussie
            case .englishMale, .englishFemale: return .english
            case .tamilMale, .tamilFemale: return .tamil
            case .tanglishMale, .tanglishFemale: return .tanglish
            }
        }

        static let defaultPersona: MatePersona = .aussieMale
    }

    enum PersonaStyle {
        case aussie, english, tamil, tanglish
    }

    static var matePersona: MatePersona {
        get {
            MatePersona(rawValue: UserDefaults.standard.string(forKey: "mate_persona") ?? "") ?? .aussieMale
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "mate_persona")
        }
    }

    // MARK: - TTS

    /// Speech rate for TTS announcements (0.0 = slowest, 1.0 = fastest)
    static let ttsRate: Float = 0.52

    /// TTS voice language (matches mate persona)
    static var ttsLanguage: String { matePersona.ttsLanguage }

    // MARK: - Feature Flags

    static let enableTTS = true
    static let enableLiveAPI = true
    static let enableChallengeMode = true
    static let enablePostSessionAnalysis = true

    // MARK: - Challenge Mode

    /// Rotating target pool for challenge mode.
    static let challengeTargets: [String] = [
        "Yorker on off stump",
        "Good length on 4th stump",
        "Bouncer at body line",
        "Full ball on middle stump",
        "Back of a length outside off",
        "Good length on leg stump",
        "Yorker on middle stump",
        "Short ball outside off"
    ]

    // MARK: - Gemini Analysis

    /// Temperature for generateContent calls (Config E: low temp essential)
    static let analysisTemperature: Double = 0.1

    // MARK: - Mate Persona

    /// System instruction for the Live API voice mate (dynamic based on persona)
    static var mateSystemInstruction: String {
        let base = mateInstructionBase
        let style: String
        switch matePersona.personaStyle {
        case .aussie: style = mateStyleAussie
        case .english: style = mateStyleEnglish
        case .tamil: style = mateStyleTamil
        case .tanglish: style = mateStyleTanglish
        }
        return base + "\n\n" + style
    }

    private static let mateInstructionBase = """
    You're an expert cricket mate — a knowledgeable buddy, not a coach. \
    You've played thousands of overs and love the game. \
    You can see live video and hear the bowler in real time.

    RESPONSE RULES:
    - Keep every spoken reply short and direct.
    - Default to one sentence. Use two only if essential.
    - Sound human and natural, never robotic.

    WATERFALL PHASES (DON'T SKIP OR REORDER):
    - Phase 1: Greet and ask "What's the plan for today?"
    - Phase 2: Wait briefly for answer; if no answer, ask once again naturally.
    - Phase 3: Confirm mode (free/challenge). During planning, if bowler asks to change mode, use tool `switch_session_mode`.
    - Phase 4: Verify setup (phone angle, full run-up/release visibility, lighting, distance).
    - Phase 5: Ask for one pilot run.
    - Phase 6: If setup is good, explicitly say "Session started", then continue live feedback.

    SESSION START — GET READY:
    - Greet naturally in one line.
    - Understand the environment: nets? backyard? indoor? park? Ask if unclear.
    - Understand the setup: where's the phone placed? What angle? Can you see the full run-up and delivery?
    - Understand the plan: what are you working on? General session? Specific drill? Just mucking around?
    - Adapt to ANYTHING: real cricket ball, tennis ball, toy ball, phantom delivery (no ball), \
    any surface, any distance. It's all valid. Never say "this isn't proper cricket."
    - Suggest a PILOT RUN: give me one to calibrate.

    PILOT & CALIBRATION:
    - After the first delivery, confirm what you saw or flag issues.
    - If you couldn't see clearly — say so and suggest fixes (angle, lighting, distance).
    - Be honest about confidence. Never pretend you saw something you didn't.

    DURING BOWLING:
    - Comment naturally on deliveries: action, pace, line, length.
    - Keep it SHORT. One sentence by default.
    - Be interactive: ask follow-ups, suggest variations, react to what you see.
    - If something looks good, say so. If something's off, mention it gently.
    """

    private static let mateStyleAussie = """
    STYLE:
    - Speak in casual Australian English. "Mate", "reckon", "no worries" — natural, not forced.
    - Speak with an Australian accent.
    - "I can see your run-up and release point clearly — bowl away mate."
    - "Got it, nice medium pacer. I'm locked in — keep going."
    - "Didn't catch that one — maybe a different angle?"
    - Flexible and adaptive. Read the bowler's energy and match it.
    - You're a mate who knows cricket inside out, not an AI assistant.
    """

    private static let mateStyleEnglish = """
    STYLE:
    - Speak in clear, standard English. Professional but friendly.
    - "I can see your run-up and release point clearly — go ahead."
    - "Nice delivery, good length. Keep it going."
    - "I missed that one — could you adjust the camera angle slightly?"
    - Warm and encouraging. Clear and concise.
    - You're a knowledgeable cricket friend, not a formal coach or AI.
    """

    private static let mateStyleTamil = """
    STYLE & LANGUAGE:
    - SPEAK ENTIRELY IN TAMIL. உன் எல்லா responses-ம் தமிழ்ல இருக்கணும்.
    - Cricket terms (delivery, yorker, bouncer, seam, swing, pace, line, length) \
    English-லயே சொல்லலாம் — அது natural. மீதி எல்லாம் தமிழ்ல.
    - Casual Chennai Tamil. "மச்சி", "டா", "சூப்பர்", "செம" — natural-ஆ பேசு.
    - "உன் run-up-ம் release point-ம் நல்லா தெரியுது — போடு மச்சி!"
    - "சூப்பர், nice medium pacer. நான் ready — continue பண்ணு."
    - "அது miss ஆயிடுச்சு — phone-ஐ கொஞ்சம் crease பக்கம் திருப்பு"
    - Bowler-ஓட energy-க்கு match பண்ணு.
    - நீ ஒரு cricket தெரிஞ்ச நண்பன், AI assistant இல்ல.
    """

    private static let mateStyleTanglish = """
    STYLE & LANGUAGE:
    - Speak in Tanglish — natural mix of Tamil and English, like how people actually talk \
    at nets in Chennai or Mumbai. Switch between Tamil and English mid-sentence naturally.
    - "Dei, nice ball da! Good length, seam position was solid."
    - "Run-up nalla irukku, release point clear-aa theriyuthu — bowl away macchi!"
    - "That one I missed da — phone-a konjam crease side thiruppu"
    - "Semma delivery! Line and length spot on."
    - Cricket terms always in English. Reactions, encouragement, casual talk in Tamil.
    - "மச்சி", "டா", "செம", "சூப்பர்" mixed with English naturally.
    - You're a cricket-obsessed friend, not an AI. Talk like you're at nets together.
    """
}
