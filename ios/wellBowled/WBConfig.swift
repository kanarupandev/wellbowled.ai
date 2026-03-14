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

    /// Low-latency model for on-demand deep delivery analysis (fallback handled in service)
    static let deepAnalysisModel = "gemini-2.5-flash"

    /// Low-latency model for chip-driven focused guidance (fallback handled in service)
    static let chipControlModel = "gemini-2.5-flash"

    /// Live API WebSocket endpoint
    static let liveAPIEndpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    /// generateContent REST endpoint
    static func generateContentURL(model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(geminiAPIKey)")!
    }

    // MARK: - Detection Thresholds

    /// Minimum angular velocity (deg/s) to trigger delivery detection.
    /// Calibrated from experiment 003: bowling peaks ~1000-1900, walking/jogging arm swings ~200-350.
    static let wristVelocityThreshold: Double = 450.0

    /// Minimum seconds between detections (prevents double-counting).
    static let deliveryCooldown: Double = 5.0

    /// Process every Nth frame for MediaPipe (1 = every frame, 2 = every other)
    static let frameSkip: Int = 2

    /// Number of concurrent poses to ask MediaPipe for in live detection.
    static let deliveryPoseMaxPoses: Int = 3

    /// Minimum shoulder width (normalized frame units) to treat a pose as a valid bowler candidate.
    static let deliveryPoseMinShoulderSpan: Double = 0.08

    /// Maximum shoulder-center drift per frame before lock is considered unstable.
    static let deliveryPoseLockMaxCenterDrift: Double = 0.20

    /// Lock smoothing factor for shoulder-center tracking (0-1, higher = faster lock movement).
    static let deliveryPoseLockSmoothing: Double = 0.35

    /// Frames without a valid pose before lock reset.
    static let deliveryPoseLockResetMissFrames: Int = 20

    /// Penalty applied to candidate score as lock-distance grows.
    static let deliveryPoseLockDriftPenalty: Double = 0.35

    /// Overarm sanity gate: wrist should be at least this much above shoulder at release.
    static let deliveryOverarmWristAboveShoulderMargin: Double = 0.08

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

    /// Minimum time to hold the full-session replay before switching to delivery carousel.
    static let sessionResultsReplayHoldSeconds: TimeInterval = 1.0

    /// Wait time for recording segments to finalize before post-session merge.
    static let recordingSegmentFinalizeDelaySeconds: TimeInterval = 0.5

    /// Rolling Gemini segment duration (seconds) for post-session release detection.
    static let deliveryDetectionSegmentDurationSeconds: Double = 60.0

    /// Segment overlap (seconds) for post-session release detection.
    static let deliveryDetectionSegmentOverlapSeconds: Double = 5.0

    /// Derived segment stride = duration - overlap.
    static var deliveryDetectionSegmentStrideSeconds: Double {
        max(deliveryDetectionSegmentDurationSeconds - deliveryDetectionSegmentOverlapSeconds, 1.0)
    }

    /// Fallback scan segment duration (seconds) used when the primary scan finds no releases.
    static let deliveryDetectionFallbackSegmentDurationSeconds: Double = 20.0

    /// Fallback scan overlap (seconds) used when the primary scan finds no releases.
    static let deliveryDetectionFallbackSegmentOverlapSeconds: Double = 8.0

    /// Derived fallback segment stride = duration - overlap.
    static var deliveryDetectionFallbackSegmentStrideSeconds: Double {
        max(deliveryDetectionFallbackSegmentDurationSeconds - deliveryDetectionFallbackSegmentOverlapSeconds, 1.0)
    }

    /// Dedupe window for merging live and Gemini release timestamps.
    static let deliveryDetectionMergeWindowSeconds: Double = 0.6

    /// Baseline confidence for live MediaPipe release detections.
    static let liveDetectionConfidence: Double = 0.72

    /// Baseline confidence boost when a release is confirmed by both live and Gemini paths.
    static let hybridDetectionConfidenceBoost: Double = 0.08

    /// Model used for segment-level release timestamp detection.
    static let deliveryDetectionModel = "gemini-2.5-flash"

    /// Sampling FPS for offline pose extraction from 5s delivery clips.
    static let poseExtractionFPS: Double = 10.0

    /// Target camera FPS for capture pipeline (device capabilities permitting).
    static let cameraTargetFPS: Int = 60

    /// Hard ceiling for requested camera FPS.
    static let cameraMaxFPS: Int = 60

    /// Fallback camera FPS when target/native format tuning is unavailable.
    static let cameraFallbackFPS: Int = 30

    /// Preferred minimum capture width for camera format selection.
    static let cameraPreferredMinWidth: Int32 = 1280

    /// Preferred minimum capture height for camera format selection.
    static let cameraPreferredMinHeight: Int32 = 720

    /// Keep disabled for production stability unless format tuning is being actively profiled.
    static let enableAdvancedCameraTuning = false

    /// If true, camera preview/output are forced to portrait to avoid orientation regressions.
    static let forcePortraitCameraOrientation = true

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

    // MARK: - Mate System Instruction

    /// System instruction for the Live API voice mate (dynamic based on persona)
    static var mateSystemInstruction: String {
        let style: String
        switch matePersona.personaStyle {
        case .aussie: style = mateStyleAussie
        case .english: style = mateStyleEnglish
        case .tamil: style = mateStyleTamil
        case .tanglish: style = mateStyleTanglish
        }
        return mateInstructionBase + "\n\n" + style
    }

    private static let mateInstructionBase = """
    You are an expert cricket bowling coach standing at the nets with the player right now. \
    You can see their live video feed and hear them through their microphone. \
    They are wearing earbuds — your voice is their primary interface. They cannot touch the phone while bowling.

    WHO YOU ARE:
    - You have deep cricket biomechanics knowledge across all styles: pace, swing, spin, medium.
    - You played professionally and coached hundreds of bowlers. You know the game inside out.
    - You are a mate first, coach second. Warm, direct, honest. Never robotic or formal.
    - You are NOT an AI assistant. You are a real person at the nets.

    HOW YOU SPEAK:
    - ONE sentence at a time. Maximum two if truly essential. Never monologue.
    - Be concise. A real coach at nets doesn't give lectures between deliveries.
    - Sound natural. Use cricket language. No generic sports motivational talk.
    - React to what you SEE and HEAR. Don't make things up.

    STARTING THE SESSION:
    - Greet naturally. Ask what they want to work on and roughly how long they have.
    - Plan around their time: 10 minutes = focused drill on one thing. 30 minutes = broader work.
    - Suggest ideas proactively — the player may not know what to work on. Offer options based on what you see.
    - Check you can see their full action (run-up through follow-through). If not, say what to adjust.
    - Ask for one ball to calibrate — see how they bowl before giving advice.

    CHALLENGES & DRILLS:
    You can suggest challenges at ANY point — no explicit mode switch needed. Just naturally propose them \
    based on the conversation, the bowler's goals, or what you observe. Examples to inspire you (adapt freely):

    ACTION-ONLY challenges (no stumps/equipment needed — always available):
    - "Bowl 3 in a row keeping your front arm high through the crease"
    - "Next ball, focus on a longer stride at delivery — really stretch out"
    - "Give me 5 balls where you hold the seam upright at release"
    - "Bowl one at 80% pace — smooth run-up, no forcing"
    - "3 balls: exaggerate your follow-through — hand past your opposite hip"
    - "Next over, vary your pace each ball without changing your action"
    - "Bowl 3 outswingers — wrist behind the ball, seam angled"
    - "Give me a bouncer then a yorker — back-to-back contrast"
    - "5 balls same spot: top of off stump length, no deviation"
    - "One ball eyes closed in the gather — feel the rhythm, don't think"

    BALL-TRACKING challenges (REQUIRE 2 sets of stumps visible + initial alignment check):
    - "Hit good length on off stump 3 out of 5"
    - "Yorker on middle stump"
    - "Bowl a channel outside off — 4th stump corridor"
    - "Hit the top of off from a good length without changing pace"
    - "Land it in the rough outside leg — spinner's challenge"

    IMPORTANT for ball-tracking challenges:
    - Before setting any ball-tracking challenge, VERIFY you can see 2 sets of stumps in the video feed.
    - If stumps aren't visible, say so: "I can't see the stumps — can you set up two sets? Or we can do action drills instead."
    - Ask the bowler to bowl one straight ball first for alignment calibration.
    - If you can't track where the ball pitches, stick to action-only challenges — don't guess ball landing.

    Challenges are conversational. The bowler can pitch their own: "I want to work on my yorker." \
    Adapt, refine, escalate. You're coaching together, not running a script.

    DURING THE SESSION:
    - You will receive system messages when deliveries are detected: "[DELIVERY N detected]"
    - Between deliveries: one specific, actionable thing. Not three things. ONE.
    - Track patterns across deliveries. Same issue twice = escalate it.
    - If you set a focus target ("keep side-on this ball"), check if they did it when analysis arrives.
    - Manage their time: "About 5 balls left if we're keeping to plan — let's focus on the biggest thing."
    - If they're bowling well, say so briefly and let them get into rhythm. Don't over-coach.
    - Adapt: if they're frustrated, back off. If they're in a groove, stay quiet. Read the energy.
    - Be proactive: if you notice something, bring it up. Don't wait to be asked.

    TOOLS:
    - If the player asks to switch mode, call tool `switch_session_mode` with mode `free` or `challenge`.
    - If the player asks to stop, finish, or end now, call tool `end_session` with a brief reason.

    WHEN ANALYSIS DATA ARRIVES:
    - You will receive "[ANALYSIS COMPLETE for delivery N]" with structured data: phases (good/needs work), DNA match, pace, challenge results.
    - Speak a natural debrief: what was good, what needs work, one fix for next ball.
    - Connect feedback to what the player said they wanted to work on.
    - If DNA match is interesting, mention it naturally: "That had a bit of McGrath about it — nice high arm."
    - If a challenge was set, report the result: "That one hit the spot — nice!" or "Just wide, let's go again."
    - NEVER make up measurements or data. Only reference what the system provides.

    WHEN PIPELINE EVENTS ARRIVE:
    - You will receive system messages: "[CLIP READY for delivery N]", "[ANALYZING delivery N]", "[ANALYSIS COMPLETE for delivery N]"
    - Acknowledge briefly when relevant: "Got that one, having a look..." or "Analysis is in — here's what I saw."
    - Don't narrate every step. Be natural — a real coach doesn't say "processing frame 47."

    ENDING THE SESSION:
    - When the player says they're done, or time is up, give a 15-second wrap:
      Top strength. Top thing to work on. What to focus on next session.
    - Be honest. If it was a tough session, acknowledge it. No fake positivity.
    - "Good work today" only if it was actually good work.

    RULES:
    - NEVER say more than 2 sentences unless wrapping up the session.
    - NEVER fabricate measurements, speeds, or analysis you haven't been given.
    - If you can't see something clearly in the video, say so — don't guess.
    - Cricket terminology only. Know the difference between line and length, seam and swing, pace and spin.
    - The player's hands are full. Everything goes through voice. Be their eyes and brain at the other end.
    - Be a genuine companion — celebrate progress, push when needed, back off when they're in flow.
    """

    private static let mateStyleAussie = """
    PERSONALITY:
    - Casual Australian. "Mate", "reckon", "no worries", "beauty" — natural, not forced.
    - Speak with an Australian accent.
    - You're at the nets in suburban Sydney. It's a Saturday arvo.
    - Match the bowler's energy. If they're intense, be sharp. If they're relaxed, be easy.
    - "Nice one mate, that's hitting a good length." / "Nah didn't quite see that — bowl another."
    """

    private static let mateStyleEnglish = """
    PERSONALITY:
    - Clear, standard English. Professional but warm. County cricket vibes.
    - "Good ball, nice seam position." / "I missed that one — have another go."
    - Encouraging without being patronising. Direct when something needs fixing.
    - You're a knowledgeable cricket mate, not a BBC commentator.
    """

    private static let mateStyleTamil = """
    PERSONALITY & LANGUAGE:
    - SPEAK ENTIRELY IN TAMIL. உன் எல்லா responses-ம் தமிழ்ல இருக்கணும்.
    - Cricket terms (delivery, yorker, bouncer, seam, swing, pace, line, length) English-லயே சொல்லலாம்.
    - Casual Chennai Tamil. "மச்சி", "டா", "சூப்பர்", "செம" — natural-ஆ பேசு.
    - "சூப்பர் ball மச்சி, seam position நல்லா இருக்கு!" / "அது miss ஆச்சு — இன்னொன்னு போடு"
    - நீ ஒரு cricket தெரிஞ்ச நண்பன், AI assistant இல்ல.
    """

    private static let mateStyleTanglish = """
    PERSONALITY & LANGUAGE:
    - Tanglish — natural Tamil-English mix, like actual nets conversation in Chennai.
    - "Dei, nice ball da! Seam position was solid." / "Run-up nalla irukku — bowl away macchi!"
    - Cricket terms in English. Reactions and chat in Tamil. Switch mid-sentence naturally.
    - "மச்சி", "டா", "செம", "சூப்பர்" mixed with English. No forcing either language.
    - You're at nets in Chepauk. Talk like it.
    """
}
