import Foundation
import os

private let log = Logger(subsystem: "com.wellbowled", category: "Analysis")

struct GeminiSegmentDeliveryDetection: Equatable {
    let localTimestamp: Double
    let confidence: Double
}

/// Analyzes delivery clips using Gemini generateContent REST API.
/// Implements DeliveryAnalyzing protocol for post-session analysis.
final class GeminiAnalysisService: DeliveryAnalyzing {

    // MARK: - Analysis Prompt

    private static let analysisPrompt = """
    You are analyzing a 5-second video clip.

    FIRST: Does this clip show an actual cricket bowling delivery (overarm action, ball released)?
    If NOT — return: { "pace_estimate": "none", "length": "unknown", "line": "unknown", "type": "unknown", \
    "observation": "No bowling delivery visible in this clip.", "confidence": 0.0 }

    If YES — watch the FULL action before classifying. Respond with STRICT JSON only:
    {
      "pace_estimate": "medium pace",
      "length": "good_length",
      "line": "off",
      "type": "seam",
      "observation": "Good seam position at release, hitting a nice length",
      "confidence": 0.7
    }

    CLASSIFICATION GUIDE:
    - pace_estimate: "quick" (>125 kph indicators: explosive run-up, braced front knee, high arm speed, \
    steep bounce, keeper standing well back), "medium pace" (110-125 kph: controlled run-up, moderate arm speed), \
    "slow" (<110 kph: short run-up, gentle action), "spin" (visible wrist/finger rotation at release, \
    loop in flight, slow through the air)
    - length: "yorker" (pitches at batsman's toes/crease), "full" (first third from batsman), \
    "good_length" (6-8m from batsman, maximum indecision zone), "short" (bouncer's half, rises above waist), \
    "bouncer" (dug in short, rises to chest/head), "unknown"
    - line: "off" (at or outside off stump), "middle" (middle stump corridor), \
    "leg" (leg stump or down leg side), "wide" (well outside off or leg), "unknown"
    - type: "seam" (upright or angled seam, pace-based), "spin" (visible revolutions), "unknown"
    - observation: ONE sentence — the most biomechanically significant aspect you can see (seam position, \
    front knee angle, release point, head position, follow-through direction)
    - confidence: 0.0-1.0. Lower if camera angle is oblique, video is blurry, or action is partially obscured.

    Be honest. If you cannot see a clear release or the camera cuts away, say so and use confidence < 0.4.

    Draw on your full cricket knowledge — the classification guide above ensures consistent output format, \
    but your observation should reflect whatever you genuinely notice about this specific delivery. \
    If the bowler has a distinctive feature (unusual grip, sling action, spinner's loop), name it.
    """


    // MARK: - Deep Analysis Prompt (On-Demand)

    private static let deepAnalysisPromptBase = """
    You are analyzing a 5-second video clip for cricket bowling biomechanics.

    FIRST: Does this clip show an actual cricket bowling delivery? If you cannot see a bowler \
    delivering a ball with an overarm action, return: \
    { "pace_estimate": "none", "summary": "No bowling delivery visible in this clip.", "phases": [] }

    If a genuine delivery IS visible: watch the ENTIRE clip first — run-up through follow-through — \
    before writing any analysis. Only describe what you actually see. Do NOT fabricate observations.

    Return STRICT JSON only:
    {
      "pace_estimate": "medium pace",
      "summary": "One sentence: the single most important technical takeaway from this delivery.",
      "phases": [
        {
          "name": "Run-up",
          "status": "GOOD",
          "observation": "What you actually see — reference specific body positions.",
          "tip": "One concrete drill or cue the bowler can try next ball.",
          "clip_ts": 0.8
        }
      ],
      "drills": [
        {
          "name": "Front arm pull-down",
          "why": "Your front arm is flying out — leaking energy and pulling your head off-line.",
          "how": "Stand at the crease, no run-up. Bowl 5 balls focusing ONLY on pulling the front arm straight down to your hip pocket at release. Exaggerate it.",
          "reps": "5 balls"
        }
      ],
      "expert_analysis": {
        "phases": [
          {
            "phaseName": "Run-up",
            "start": 0.0,
            "end": 1.0,
            "feedback": {
              "good": ["LEFT_HIP"],
              "slow": ["RIGHT_SHOULDER"],
              "injury_risk": ["RIGHT_KNEE"]
            }
          }
        ]
      },
      "dna": {
        "run_up_stride": "medium",
        "run_up_speed": "fast",
        "approach_angle": "straight",
        "gather_alignment": "semi",
        "back_foot_contact": "braced",
        "trunk_lean": "slight",
        "delivery_stride_length": "normal",
        "front_arm_action": "pull",
        "head_stability": "stable",
        "arm_path": "high",
        "release_height": "high",
        "wrist_position": "behind",
        "seam_orientation": "upright",
        "revolutions": "medium",
        "follow_through_direction": "straight",
        "balance_at_finish": "balanced"
      }
    }

    PHASE ANALYSIS GUIDE — evaluate these 5 phases in order:

    1. RUN-UP & APPROACH (clip_ts: early in clip)
       Look for: rhythm and acceleration (should be progressive, not flat). Approach angle — \
    straight line toward target or drifting wide? Run-up speed relative to bowler type.
       Common faults: kink/deviation at the end of run-up (causes falling away downstream), \
    decelerating before the crease, stuttering final strides.

    2. GATHER & LOAD (back-foot contact)
       Look for: hip-shoulder alignment at BFC — are hips and shoulders aligned (side-on, semi, front-on) \
    or misaligned (mixed action = injury risk)? Height and quality of the bound. Coil/separation \
    between hips and shoulders. Back-foot landing angle relative to crease.
       Common faults: mixed action (hips front-on, shoulders side-on — lumbar stress fracture risk), \
    collapsing on back foot, no hip-shoulder separation.
       INJURY FLAG: If shoulders counter-rotate excessively relative to hips, flag as injury_risk.

    3. DELIVERY STRIDE (front-foot contact through release)
       Look for: front knee angle at FFC and at release — is it bracing (extending/straightening) \
    or collapsing? Stride length and alignment (BFC, FFC, and follow-through should be in a straight line). \
    Front arm action: pulling down and through (good) vs flinging out laterally (energy leak). \
    Head position: should be directly over front foot at release, eyes level.
       Common faults: front knee collapse (absorbs energy instead of transferring to ball), \
    front arm pulling away (causes head and body to fall off), over-striding (BFC to FFC too far apart).
       KEY: The front leg works through eccentric control — controlled deceleration, not rigid bracing.

    4. RELEASE
       Look for: arm path (high = ~12 o'clock ideal for seamers), release point height and consistency. \
    Wrist position behind the ball. Seam orientation at release — upright (maximises swing), \
    angled (cross-seam/cutters), or scrambled (inconsistent). Ball coming out cleanly or wobbling.
       Common faults: early release (ball comes out too soon — usually arm speed inconsistency), \
    wrist falling away at release, low release point reducing bounce and control.

    5. FOLLOW-THROUGH
       Look for: does the first stride continue the straight line from BFC → FFC? Is the bowling arm \
    completing its arc naturally? Balance at finish — upright and controlled, or falling to one side?
       Common faults: falling away to off side (symptom of upstream issues — usually head position \
    or front arm), abbreviated follow-through (increases deceleration stress), stumbling.

    RULES:
    - Use exactly 5 phases: "Run-up", "Gather", "Delivery stride", "Release", "Follow-through".
    - status: "GOOD" or "NEEDS WORK". Be honest — don't mark everything GOOD.
    - clip_ts: the timestamp in seconds (0.0-5.0) where this phase is MOST visible.
    - observation: describe what you ACTUALLY SEE. Reference specific body parts and positions. \
    Not "nice action" — instead "front knee extends from ~30° to near-full extension through delivery stride".
    - tip: a SPECIFIC drill or technical cue, not vague advice. \
    Examples: "Try bowling from 3 steps to isolate the release without run-up momentum", \
    "Focus on pulling your front arm down to your hip — not across your body", \
    "Film from behind to check your run-up stays in a straight corridor".
    - summary: the single most important thing — if this bowler could fix ONE thing, what is it?
    - expert_analysis body parts: ONLY use HEAD, LEFT_SHOULDER, RIGHT_SHOULDER, LEFT_HIP, RIGHT_HIP, \
    LEFT_KNEE, RIGHT_KNEE, LEFT_ANKLE, RIGHT_ANKLE.
    - injury_risk: genuine biomechanical concern (mixed action, excessive lateral trunk flexion >50°, \
    front knee hyperextension, excessive shoulder counter-rotation).
    - slow: needs improvement but not dangerous.
    - good: strong technique worth maintaining and reinforcing.
    - Max 3-5 body part annotations total across all phases. Only include annotations you are >90% confident about. Quality over quantity.

    USE YOUR KNOWLEDGE:
    The phase guide above is a framework, not a ceiling. You have deep cricket biomechanics knowledge — \
    use it. If you see something not listed above (e.g. elbow hyperextension like Bumrah, a distinctive \
    sling action, wrist-spin finger mechanics, reverse swing grip cues, or a technical nuance specific \
    to this bowler's style), call it out. The guide ensures consistency; your expertise fills the gaps. \
    Prioritise what is most important for THIS specific delivery over mechanically covering every phase.

    ACTION DNA SIGNATURE — include in the same response:
    Also classify the bowler's action signature into the "dna" object below. This is used for vector \
    matching against famous bowlers. Use null for ANY field you cannot confidently determine.

    "dna": {
      "run_up_stride": "short" | "medium" | "long",
      "run_up_speed": "slow" | "moderate" | "fast" | "explosive",
      "approach_angle": "straight" | "angled" | "wide",
      "gather_alignment": "front_on" | "semi" | "side_on",
      "back_foot_contact": "braced" | "sliding" | "jumping",
      "trunk_lean": "upright" | "slight" | "pronounced",
      "delivery_stride_length": "short" | "normal" | "over_striding",
      "front_arm_action": "pull" | "sweep" | "delayed",
      "head_stability": "stable" | "tilted" | "falling",
      "arm_path": "high" | "round_arm" | "sling",
      "release_height": "high" | "medium" | "low",
      "wrist_position": "behind" | "cocked" | "side_arm",
      "seam_orientation": "upright" | "scrambled" | "angled",
      "revolutions": "low" | "medium" | "high",
      "follow_through_direction": "across" | "straight" | "wide",
      "balance_at_finish": "balanced" | "falling" | "stumbling",
      "run_up_quality": 0.6,
      "gather_quality": 0.5,
      "delivery_stride_quality": 0.4,
      "release_quality": 0.5,
      "follow_through_quality": 0.3
    }

    EXECUTION QUALITY RATINGS (0.1–1.0, round to nearest 0.1):
    Rate HOW WELL each phase is executed, not just WHAT the technique is.
    - 0.9–1.0: International elite — textbook or uniquely effective (e.g., McGrath's run-up rhythm)
    - 0.7–0.8: Club/county level — solid technique with minor flaws
    - 0.5–0.6: Regular recreational — decent intent, inconsistent execution
    - 0.3–0.4: Beginner — obvious technical gaps, uncoordinated timing
    - 0.1–0.2: Raw novice — no discernible technique in this phase
    Be HONEST. Most recreational bowlers should score 0.3–0.6. Do not flatter.

    DRILLS — include 1-2 immediate high-ROI drills in the "drills" array:
    Pick the 1-2 phases marked "NEEDS WORK" that would give the biggest improvement if fixed. \
    For each, give a specific, actionable drill:
    - "name": short name (e.g. "Standing start release", "Front arm pull-down")
    - "why": one sentence — what's wrong and why this drill fixes it
    - "how": exact instructions the bowler can follow right now (reps, setup, focus point)
    - "reps": how many (e.g. "5 balls", "3 sets of 5")
    If all phases are GOOD, return an empty drills array. Do NOT invent drills for things that are fine.
    """

    /// Build the deep analysis prompt, optionally injecting measured speed context.
    static func deepAnalysisPrompt(speedContext: SpeedContext? = nil) -> String {
        var prompt = deepAnalysisPromptBase
        if let ctx = speedContext {
            prompt += """

            SPEED MEASUREMENT (video frame-differencing):
            Ball speed measured at \(String(format: "%.1f", ctx.kph)) kph (\(ctx.method), \(ctx.fps)fps).
            Frame-timing error margin: ±\(String(format: "%.1f", ctx.errorMarginKph)) kph.
            Use this speed in your analysis. Reference it as "estimated at" or "roughly".
            Do NOT override with your own estimate — use the measured value.

            Add a "speed_confidence" field to your JSON response (0.0-1.0):
            Assess how trustworthy this speed measurement is based on what you SEE:
            - Can you clearly see the ball travel the full pitch? (if not, lower confidence)
            - Is the camera angle front-on with both sets of stumps visible? (if not, lower)
            - Is there camera shake or motion blur? (if yes, lower)
            - Is the ball clearly distinguishable from background? (if not, lower)
            0.8+ = clear ball path, good angle, both stumps visible, minimal blur
            0.5-0.8 = some occlusion or suboptimal angle but ball path mostly visible
            <0.5 = significant issues (ball lost, heavy blur, bad angle, one stump set missing)
            """
        }
        return prompt
    }

    /// Context for injecting measured speed into the deep analysis prompt.
    struct SpeedContext {
        let kph: Double
        let errorMarginKph: Double
        let method: String
        let fps: Int
    }

    // MARK: - Chip Guidance Prompt

    private static let chipGuidancePrompt = """
    You are controlling replay guidance for one bowling delivery.
    Respond with STRICT JSON only:
    {
      "reply": "One short natural sentence.",
      "action": "focus",
      "phase_name": "Release",
      "focus_start": 1.8,
      "focus_end": 2.6,
      "playback_rate": 0.45
    }

    Allowed actions: "focus", "pause", "slow_mo", "none".

    Rules:
    - Keep reply one short sentence.
    - If action is focus, provide focus_start and focus_end in [0, 5].
    - If action is slow_mo, playback_rate should be between 0.35 and 0.6.
    - If pause or none, focus_start/focus_end can be null.
    """

    // MARK: - Segment Delivery Detection Prompt

    private static let segmentDeliveryDetectionPrompt = """
    You are analyzing a video segment. Your job: detect cricket bowling deliveries ONLY.

    FIRST: Is there actual cricket bowling happening in this video?
    - Is there a bowler with a ball running in and delivering with an overarm action?
    - Is there a cricket pitch, stumps, or net visible?
    - If NO cricket bowling is visible — return { "deliveries": [] } immediately.
    - Do NOT hallucinate deliveries. A person walking, waving, or any non-bowling motion is NOT a delivery.
    - A wall, empty room, backyard without bowling, or static scene = ZERO deliveries.

    IF genuine cricket bowling IS happening, detect each RELEASE instant (ball leaving the hand):
    {
      "deliveries": [
        {
          "release_time_sec": 12.4,
          "confidence": 0.86
        }
      ]
    }

    Rules:
    - `release_time_sec` is seconds from segment start, sorted ascending.
    - confidence 0.0-1.0: only report 0.8+ for clear, unambiguous overarm bowling releases.
    - Ignore partial run-ups without a release, throws, catches, or practice swings.
    - When in doubt, do NOT report it. False positives are worse than missed detections.
    - If none found, return { "deliveries": [] }.
    """

    private static let segmentDeliveryDetectionHighRecallPrompt = """
    You are analyzing a video segment in HIGH-RECALL mode for cricket bowling deliveries.

    FIRST: Is there actual cricket bowling happening? If not, return { "deliveries": [] }.
    Do NOT hallucinate. A static scene, empty room, or non-cricket activity = ZERO deliveries.

    IF genuine bowling IS happening, detect each likely RELEASE (ball leaving hand, overarm action).
    Include plausible releases with lower confidence — prefer recall over precision.
    {
      "deliveries": [
        {
          "release_time_sec": 12.4,
          "confidence": 0.62
        }
      ]
    }

    Rules:
    - `release_time_sec` seconds from segment start, sorted ascending.
    - confidence 0.0-1.0. Include uncertain candidates at 0.5+.
    - Ignore obvious non-bowling motion (walking, waving, throwing).
    - If none found, return { "deliveries": [] }.
    """

    /// Normalize wrist angular velocity: clamp((|omega| - 800) / 1200, 0, 1)
    static func normalizeOmega(_ omega: Double) -> Double {
        return min(max((abs(omega) - 800.0) / 1200.0, 0.0), 1.0)
    }

    // MARK: - DeliveryAnalyzing

    func analyzeDelivery(clipURL: URL) async throws -> DeliveryAnalysis {
        let videoData = try Data(contentsOf: clipURL)
        let base64Video = videoData.base64EncodedString()
        log.debug("Starting standard delivery analysis: clip=\(clipURL.lastPathComponent, privacy: .public)")

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inlineData": ["mimeType": "video/mp4", "data": base64Video]],
                    ["text": Self.analysisPrompt]
                ]
            ]],
            "generationConfig": [
                "temperature": WBConfig.analysisTemperature,
                "responseMimeType": "application/json"
            ]
        ]

        let url = WBConfig.generateContentURL(model: WBConfig.analysisModel)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        log.debug("Analyzing clip: \(clipURL.lastPathComponent) (\(videoData.count / 1024)KB)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            log.error("Analysis API error: HTTP \(statusCode)")
            throw AnalysisError.apiError(statusCode)
        }

        let analysis = try parseAnalysisResponse(data)
        log.debug("Standard delivery analysis completed: clip=\(clipURL.lastPathComponent, privacy: .public), pace=\(analysis.paceEstimate, privacy: .public)")
        return analysis
    }

    func analyzeDeliveryDeep(clipURL: URL, speedContext: SpeedContext? = nil) async throws -> DeliveryDeepAnalysisResult {
        let videoData = try Data(contentsOf: clipURL)
        let base64Video = videoData.base64EncodedString()
        log.debug("Starting deep delivery analysis: clip=\(clipURL.lastPathComponent, privacy: .public), hasSpeed=\(speedContext != nil)")

        let prompt = Self.deepAnalysisPrompt(speedContext: speedContext)
        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inlineData": ["mimeType": "video/mp4", "data": base64Video]],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.1,
                "responseMimeType": "application/json"
            ]
        ]

        let data = try await requestJSON(
            payload: payload,
            candidateModels: [WBConfig.deepAnalysisModel, WBConfig.analysisModel]
        )

        let result = try parseDeepAnalysisResponse(data)
        log.debug("Deep delivery analysis completed: clip=\(clipURL.lastPathComponent, privacy: .public), phases=\(result.phases.count)")
        return result
    }

    func generateChipGuidance(
        chip: String,
        deliverySummary: String,
        phases: [AnalysisPhase]
    ) async throws -> ChipGuidanceResponse {
        log.debug("Starting chip guidance request: chip=\(chip, privacy: .public), phases=\(phases.count)")
        let phaseLines = phases.map { phase in
            let ts = phase.clipTimestamp ?? 2.5
            return "- \(phase.name) | \(phase.status) | clip_ts: \(String(format: "%.2f", ts)) | obs: \(phase.observation)"
        }
        .joined(separator: "\n")

        let context = """
        Chip selected by bowler: \(chip)
        Delivery summary: \(deliverySummary)
        Available phases:
        \(phaseLines.isEmpty ? "- none" : phaseLines)
        """

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": Self.chipGuidancePrompt],
                    ["text": context]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.1,
                "responseMimeType": "application/json"
            ]
        ]

        let data = try await requestJSON(
            payload: payload,
            candidateModels: [WBConfig.chipControlModel, WBConfig.deepAnalysisModel, WBConfig.analysisModel]
        )

        let response = try parseChipGuidanceResponse(data)
        log.debug("Chip guidance completed: action=\(response.action, privacy: .public), phase=\(response.phaseName ?? "-", privacy: .public)")
        return response
    }

    func evaluateChallenge(clipURL: URL, target: String) async throws -> ChallengeResult {
        let videoData = try Data(contentsOf: clipURL)
        let base64Video = videoData.base64EncodedString()
        log.debug("Starting challenge evaluation: clip=\(clipURL.lastPathComponent, privacy: .public), target=\(target, privacy: .public)")

        let prompt = """
        You are evaluating a video clip of a cricket bowling delivery against a target.

        FIRST: Does this clip show an actual cricket bowling delivery? \
        If NOT — return: { "matches_target": false, "confidence": 0.0, \
        "explanation": "No bowling delivery visible", "detected_length": "unknown", "detected_line": "unknown" }

        TARGET: "\(target)"

        If a genuine delivery IS visible, evaluate honestly:
        {
          "matches_target": true,
          "confidence": 0.7,
          "explanation": "What you actually observed about where the ball pitched and its line",
          "detected_length": "yorker",
          "detected_line": "off"
        }

        Only claim a match if you genuinely see the ball achieving the target. \
        If uncertain, set confidence low and matches_target false.
        """

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inlineData": ["mimeType": "video/mp4", "data": base64Video]],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": [
                "temperature": WBConfig.analysisTemperature,
                "responseMimeType": "application/json"
            ]
        ]

        let url = WBConfig.generateContentURL(model: WBConfig.analysisModel)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            log.error("Challenge evaluation API error: HTTP \(statusCode)")
            throw AnalysisError.apiError(statusCode)
        }
        let result = try parseChallengeResponse(data)
        log.debug("Challenge evaluation completed: match=\(result.matchesTarget), confidence=\(result.confidence, privacy: .public)")
        return result
    }

    func detectDeliveryTimestampsInSegment(
        segmentURL: URL,
        segmentDuration: Double,
        highRecall: Bool = false
    ) async throws -> [GeminiSegmentDeliveryDetection] {
        let videoData = try Data(contentsOf: segmentURL)
        let base64Video = videoData.base64EncodedString()
        let durationText = String(format: "%.2f", max(segmentDuration, 0))
        log.debug(
            "Segment delivery detection started: segment=\(segmentURL.lastPathComponent, privacy: .public), duration=\(durationText, privacy: .public)s, highRecall=\(highRecall)"
        )

        let context = "Segment duration: \(durationText) seconds."
        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inlineData": ["mimeType": "video/mp4", "data": base64Video]],
                    ["text": highRecall ? Self.segmentDeliveryDetectionHighRecallPrompt : Self.segmentDeliveryDetectionPrompt],
                    ["text": context]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.0,
                "responseMimeType": "application/json"
            ]
        ]

        let data = try await requestJSON(
            payload: payload,
            candidateModels: [WBConfig.deliveryDetectionModel, WBConfig.deepAnalysisModel, WBConfig.analysisModel],
            timeoutSeconds: 60
        )
        let detections = try parseSegmentDeliveryDetections(data, segmentDuration: segmentDuration)
        let preview = detections.prefix(8).map {
            String(format: "%.2fs@%.2f", $0.localTimestamp, $0.confidence)
        }.joined(separator: ", ")
        log.debug(
            "Segment delivery detection completed: segment=\(segmentURL.lastPathComponent, privacy: .public), releases=\(detections.count), preview=[\(preview, privacy: .public)]"
        )
        return detections
    }

    func generateSessionSummary(deliveries: [Delivery]) async throws -> SessionSummary {
        // Build summary from local data (no API call needed)
        let dominant = PaceBand.medium // simplified
        return SessionSummary(
            totalDeliveries: deliveries.count,
            durationMinutes: 0,
            dominantPace: dominant,
            paceDistribution: [dominant: deliveries.count],
            keyObservation: "Session complete with \(deliveries.count) deliveries",
            challengeScore: nil
        )
    }

    // MARK: - Response Parsing

    private func parseAnalysisResponse(_ data: Data) throws -> DeliveryAnalysis {
        let text = try extractCandidateText(from: data)
        guard let textData = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: textData) as? [String: Any] else {
            throw AnalysisError.parseError
        }

        log.debug("Analysis result: \(text.prefix(100))")

        return DeliveryAnalysis(
            paceEstimate: result["pace_estimate"] as? String ?? "unknown",
            length: DeliveryLength(rawValue: result["length"] as? String ?? "unknown") ?? .unknown,
            line: DeliveryLine(rawValue: result["line"] as? String ?? "unknown") ?? .unknown,
            type: DeliveryType(rawValue: result["type"] as? String ?? "unknown") ?? .unknown,
            observation: result["observation"] as? String ?? "",
            confidence: result["confidence"] as? Double ?? 0.5
        )
    }

    private func parseChallengeResponse(_ data: Data) throws -> ChallengeResult {
        let text = try extractCandidateText(from: data)
        guard let textData = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: textData) as? [String: Any] else {
            throw AnalysisError.parseError
        }

        return ChallengeResult(
            matchesTarget: result["matches_target"] as? Bool ?? false,
            confidence: result["confidence"] as? Double ?? 0.5,
            explanation: result["explanation"] as? String ?? "",
            detectedLength: DeliveryLength(rawValue: result["detected_length"] as? String ?? ""),
            detectedLine: DeliveryLine(rawValue: result["detected_line"] as? String ?? "")
        )
    }

    private func parseDeepAnalysisResponse(_ data: Data) throws -> DeliveryDeepAnalysisResult {
        let text = try extractCandidateText(from: data)
        guard let textData = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: textData) as? [String: Any] else {
            throw AnalysisError.parseError
        }

        let paceEstimate = result["pace_estimate"] as? String ?? "medium pace"
        let summary = result["summary"] as? String ?? ""

        let phasesArray = (result["phases"] as? [[String: Any]] ?? [])
        let phases: [AnalysisPhase] = phasesArray.map { phase in
            AnalysisPhase(
                name: phase["name"] as? String ?? "Phase",
                status: phase["status"] as? String ?? "NEEDS WORK",
                observation: phase["observation"] as? String ?? "",
                tip: phase["tip"] as? String ?? "",
                clipTimestamp: (phase["clip_ts"] as? Double).flatMap { min(max($0, 0), 5.0) }
            )
        }
        .sorted { ($0.clipTimestamp ?? 10.0) < ($1.clipTimestamp ?? 10.0) }

        var expertAnalysis: ExpertAnalysis?
        if let expertDict = result["expert_analysis"] as? [String: Any],
           let expertData = try? JSONSerialization.data(withJSONObject: expertDict),
           let parsed = try? JSONDecoder().decode(ExpertAnalysis.self, from: expertData) {
            expertAnalysis = normalized(expertAnalysis: parsed)
        } else {
            expertAnalysis = ExpertAnalysisBuilder.build(from: phases).map { normalized(expertAnalysis: $0) }
        }

        // Parse DNA from the same response
        var dna: BowlingDNA?
        if let dnaDict = result["dna"] as? [String: Any] {
            // Log raw DNA values from Gemini for debugging parse failures
            log.info("DNA raw from Gemini: \(dnaDict)")

            // Helper: normalize Gemini's string to snake_case lowercase for enum matching
            func norm(_ key: String) -> String? {
                guard let raw = dnaDict[key] as? String else { return nil }
                let cleaned = raw.lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "-", with: "_")
                return cleaned
            }

            // Helper: parse quality value (0.1–1.0, snapped to nearest 0.1)
            func quality(_ key: String) -> Double? {
                guard let raw = dnaDict[key] as? Double, raw > 0 else { return nil }
                return BowlingDNA.snapQuality(min(max(raw, 0.1), 1.0))
            }

            dna = BowlingDNA(
                runUpStride: norm("run_up_stride").flatMap(RunUpStrideCategory.init),
                runUpSpeed: norm("run_up_speed").flatMap(RunUpSpeed.init),
                approachAngle: norm("approach_angle").flatMap(ApproachAngle.init),
                gatherAlignment: norm("gather_alignment").flatMap(BodyAlignment.init),
                backFootContact: norm("back_foot_contact").flatMap(BackFootContact.init),
                trunkLean: norm("trunk_lean").flatMap(TrunkLean.init),
                deliveryStrideLength: norm("delivery_stride_length").flatMap(StrideLength.init),
                frontArmAction: norm("front_arm_action").flatMap(FrontArmAction.init),
                headStability: norm("head_stability").flatMap(HeadStability.init),
                armPath: norm("arm_path").flatMap(ArmPath.init),
                releaseHeight: norm("release_height").flatMap(ReleaseHeight.init),
                wristPosition: norm("wrist_position").flatMap(WristPosition.init),
                seamOrientation: norm("seam_orientation").flatMap(SeamOrientation.init),
                revolutions: norm("revolutions").flatMap(Revolutions.init),
                followThroughDirection: norm("follow_through_direction").flatMap(FollowThroughDir.init),
                balanceAtFinish: norm("balance_at_finish").flatMap(BalanceAtFinish.init),
                runUpQuality: quality("run_up_quality"),
                gatherQuality: quality("gather_quality"),
                deliveryStrideQuality: quality("delivery_stride_quality"),
                releaseQuality: quality("release_quality"),
                followThroughQuality: quality("follow_through_quality")
            )
            // Log which fields parsed vs failed for debugging DNA quality
            let dnaFields: [(String, Any?)] = [
                ("run_up_stride", dna?.runUpStride), ("arm_path", dna?.armPath),
                ("gather_alignment", dna?.gatherAlignment), ("release_height", dna?.releaseHeight),
                ("wrist_position", dna?.wristPosition), ("follow_through_direction", dna?.followThroughDirection)
            ]
            let parsed = dnaFields.filter { $0.1 != nil }.count
            let total = dnaDict.count
            log.info("DNA parsed: \(parsed)/6 key fields from \(total) raw fields — keys: \(dnaDict.keys.sorted().joined(separator: ", "))")
            if parsed == 0 {
                log.warning("DNA extraction returned all-nil fields — raw values: \(dnaDict)")
                dna = nil // Don't create empty DNA — better to show "no match" than broken match
            }
        } else {
            log.warning("No 'dna' key in deep analysis response — keys present: \(result.keys.sorted().joined(separator: ", "))")
        }

        // Parse Gemini's visual speed confidence (0.0-1.0)
        let speedConfidence = (result["speed_confidence"] as? Double).flatMap { min(max($0, 0), 1.0) }

        // Parse drills
        let drills: [Drill]? = {
            guard let drillsArray = result["drills"] as? [[String: Any]] else { return nil }
            return drillsArray.compactMap { d in
                guard let name = d["name"] as? String,
                      let why = d["why"] as? String,
                      let how = d["how"] as? String,
                      let reps = d["reps"] as? String else { return nil }
                return Drill(name: name, why: why, how: how, reps: reps)
            }
        }()

        return DeliveryDeepAnalysisResult(
            paceEstimate: paceEstimate,
            summary: summary,
            phases: phases,
            expertAnalysis: expertAnalysis,
            dna: dna,
            speedConfidence: speedConfidence,
            drills: drills
        )
    }

    private func parseChipGuidanceResponse(_ data: Data) throws -> ChipGuidanceResponse {
        let text = try extractCandidateText(from: data)
        guard let textData = text.data(using: .utf8) else {
            throw AnalysisError.parseError
        }
        do {
            return try JSONDecoder().decode(ChipGuidanceResponse.self, from: textData)
        } catch {
            throw AnalysisError.parseError
        }
    }

    private func parseSegmentDeliveryDetections(
        _ data: Data,
        segmentDuration: Double
    ) throws -> [GeminiSegmentDeliveryDetection] {
        let text = try extractCandidateText(from: data)
        return try Self.parseSegmentDeliveryDetections(fromCandidateText: text, segmentDuration: segmentDuration)
    }

    static func parseSegmentDeliveryDetections(
        fromCandidateText text: String,
        segmentDuration: Double
    ) throws -> [GeminiSegmentDeliveryDetection] {
        let jsonText = extractJSONObjectText(from: text)
        guard let textData = jsonText.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: textData) as? [String: Any] else {
            throw AnalysisError.parseError
        }

        let rawDeliveries: [Any] = {
            if let deliveries = object["deliveries"] as? [Any] {
                return deliveries
            }
            if let releaseTimes = object["release_times_sec"] as? [Any] {
                return releaseTimes
            }
            if let releaseTimes = object["release_times"] as? [Any] {
                return releaseTimes
            }
            return []
        }()

        let maxDuration = max(segmentDuration, 0)
        var parsed: [GeminiSegmentDeliveryDetection] = []

        for item in rawDeliveries {
            if let number = parseDouble(item) {
                parsed.append(
                    GeminiSegmentDeliveryDetection(
                        localTimestamp: min(max(number, 0), maxDuration),
                        confidence: 0.5
                    )
                )
                continue
            }

            guard let dict = item as? [String: Any] else { continue }
            let rawTimestamp = (
                parseDouble(dict["release_time_sec"]) ??
                parseDouble(dict["time_sec"]) ??
                parseDouble(dict["timestamp"]) ??
                parseDouble(dict["release_timestamp"])
            )
            guard let rawTimestamp else { continue }

            let rawConfidence = parseDouble(dict["confidence"]) ?? 0.5
            parsed.append(
                GeminiSegmentDeliveryDetection(
                    localTimestamp: min(max(rawTimestamp, 0), maxDuration),
                    confidence: min(max(rawConfidence, 0), 1)
                )
            )
        }

        return parsed.sorted { lhs, rhs in
            if lhs.localTimestamp != rhs.localTimestamp {
                return lhs.localTimestamp < rhs.localTimestamp
            }
            return lhs.confidence > rhs.confidence
        }
    }

    private func extractCandidateText(from data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first(where: { $0["text"] != nil })?["text"] as? String else {
            throw AnalysisError.parseError
        }
        return text
    }

    private static func extractJSONObjectText(from raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            return String(cleaned[start...end])
        }
        return cleaned
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    /// Retryable HTTP status codes — try the next candidate model instead of failing.
    private static let retryableStatusCodes: Set<Int> = [400, 404, 429, 500, 502, 503]

    private func requestJSON(payload: [String: Any], candidateModels: [String], timeoutSeconds: TimeInterval = 120) async throws -> Data {
        var lastError: Error = AnalysisError.parseError
        var triedAtLeastOne = false

        // Serialize payload ONCE — avoids re-encoding the (potentially large) base64 video per retry.
        let body = try JSONSerialization.data(withJSONObject: payload)

        for model in candidateModels where !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            triedAtLeastOne = true
            do {
                log.debug("JSON request attempt: model=\(model, privacy: .public)")
                let url = WBConfig.generateContentURL(model: model)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeoutSeconds
                request.httpBody = body

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AnalysisError.parseError
                }
                guard httpResponse.statusCode == 200 else {
                    let status = httpResponse.statusCode
                    log.debug("JSON request non-200: model=\(model, privacy: .public), status=\(status)")
                    if Self.retryableStatusCodes.contains(status) {
                        lastError = AnalysisError.apiError(status)
                        continue
                    }
                    throw AnalysisError.apiError(status)
                }
                log.debug("JSON request success: model=\(model, privacy: .public)")
                return data
            } catch {
                log.debug("JSON request failed: model=\(model, privacy: .public), error=\(error.localizedDescription, privacy: .public)")
                lastError = error
                continue
            }
        }

        if !triedAtLeastOne {
            throw AnalysisError.parseError
        }
        throw lastError
    }

    private func normalized(expertAnalysis: ExpertAnalysis) -> ExpertAnalysis {
        let normalizedPhases = expertAnalysis.phases
            .map { phase -> ExpertAnalysis.Phase in
                let start = min(max(phase.start, 0), 5.0)
                let end = min(max(phase.end, start + 0.001), 5.0)
                return ExpertAnalysis.Phase(
                    phaseName: phase.phaseName,
                    start: start,
                    end: max(end, start + 0.001),
                    feedback: phase.feedback
                )
            }
            .sorted(by: { $0.start < $1.start })
        return ExpertAnalysis(phases: normalizedPhases)
    }
}

enum AnalysisError: LocalizedError {
    case apiError(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .apiError(let code): return "Gemini API error (HTTP \(code))"
        case .parseError: return "Failed to parse analysis response"
        }
    }
}
