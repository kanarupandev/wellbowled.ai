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
    You are an elite cricket biomechanics analyst reviewing a 5-second bowling delivery clip.

    Watch the FULL action sequence — run-up through follow-through — before classifying.

    Respond with STRICT JSON only:
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

    // MARK: - DNA Extraction Prompt

    private static let dnaExtractionPrompt = """
    You are a cricket biomechanics specialist extracting a bowler's action signature from a 5-second delivery clip.

    Watch the COMPLETE action from run-up entry to follow-through completion before classifying any field.

    Respond with STRICT JSON matching this schema:
    {
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
      "balance_at_finish": "balanced" | "falling" | "stumbling"
    }

    BIOMECHANICAL REFERENCE for each field:
    - gather_alignment: Check hip-shoulder orientation at back-foot contact (BFC). \
    "side_on" = back foot parallel to crease, chest facing gully. "front_on" = chest facing batsman. \
    "semi" = between the two (~30-45 degrees open).
    - back_foot_contact: "braced" = planted firmly, absorbing force. "jumping" = airborne bound. \
    "sliding" = foot drags or skids on landing.
    - trunk_lean: Lateral flexion of the torso at release. "upright" = <20 degrees. \
    "slight" = 20-40 degrees. "pronounced" = >40 degrees (injury risk flag).
    - front_arm_action: "pull" = drives down and through (textbook). "sweep" = flings out laterally. \
    "delayed" = stays up late, delays circumduction (associated with higher pace).
    - arm_path: "high" = release near 12 o'clock (McGrath, Anderson). "round_arm" = ~10 o'clock (Malinga-style). \
    "sling" = chest-height release, catapult motion.
    - wrist_position: "behind" = fingers directly behind the ball at release (seam bowler default). \
    "cocked" = wrist angled, seam tilted (swing variant). "side_arm" = wrist rotated laterally.
    - seam_orientation: "upright" = bolt upright like Anderson (maximises conventional swing). \
    "angled" = seam tilted toward slip or fine leg. "scrambled" = wobbling, no clean axis.
    - head_stability: "stable" = head over front foot at release, eyes level. \
    "tilted" = head leaning to off side. "falling" = head dropping away from the action.

    Use null for ANY field you cannot confidently determine from the video angle or quality. \
    Partial DNA is valid — do not guess. Only classify what you can clearly see.

    The schema above captures the 16 core dimensions. If you recognise something distinctive \
    about this action that the schema doesn't capture (e.g. Bumrah-style hyperextension, \
    Malinga's elastic energy storage, a spinner's stock ball vs variation), the enum values \
    should still reflect the closest match — the downstream matcher will handle nuance.
    """

    // MARK: - Deep Analysis Prompt (On-Demand)

    private static let deepAnalysisPromptBase = """
    You are an elite cricket bowling biomechanics expert analyzing a single 5-second delivery clip.

    Watch the ENTIRE clip first — run-up entry through follow-through completion — before writing any analysis. \
    Pay close attention to the transition between phases, not just static positions.

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
      "balance_at_finish": "balanced" | "falling" | "stumbling"
    }
    """

    /// Build the deep analysis prompt, optionally injecting measured speed context.
    static func deepAnalysisPrompt(speedContext: SpeedContext? = nil) -> String {
        var prompt = deepAnalysisPromptBase
        if let ctx = speedContext {
            prompt += """

            SPEED MEASUREMENT:
            Ball speed measured at \(String(format: "%.1f", ctx.kph)) kph (\(ctx.method), \(ctx.fps)fps recording).
            Error margin: \(String(format: "%.1f", ctx.errorMarginKph)) kph.
            Use this speed in your analysis. Reference it when discussing pace.
            Do NOT override this with your own estimate — use the measured value.
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
    You are analyzing one cricket bowling video segment.
    Detect each bowling RELEASE instant (the ball leaving the hand).

    Return STRICT JSON only:
    {
      "deliveries": [
        {
          "release_time_sec": 12.4,
          "confidence": 0.86
        }
      ]
    }

    Rules:
    - `release_time_sec` is seconds from segment start.
    - Keep times sorted ascending.
    - Ignore non-bowling motion and partial run-ups without release.
    - Use confidence in [0, 1].
    - If none found, return { "deliveries": [] }.
    """

    private static let segmentDeliveryDetectionHighRecallPrompt = """
    You are analyzing one cricket bowling video segment in HIGH-RECALL mode.
    Detect each likely bowling RELEASE instant (ball leaving the hand) from an overarm bowling action.
    Prefer recall over precision: include plausible releases with lower confidence instead of dropping them.

    Return STRICT JSON only:
    {
      "deliveries": [
        {
          "release_time_sec": 12.4,
          "confidence": 0.62
        }
      ]
    }

    Rules:
    - `release_time_sec` is seconds from segment start.
    - Keep times sorted ascending.
    - Ignore obvious non-bowling movement.
    - If uncertain, still include the candidate with lower confidence.
    - Use confidence in [0, 1].
    - If none found, return { "deliveries": [] }.
    """

    // MARK: - DNA Extraction

    /// Extracts BowlingDNA from a clip using Gemini vision + MediaPipe-derived wrist data.
    func extractBowlingDNA(
        clipURL: URL,
        wristOmega: Double?,
        releaseWristY: Double?
    ) async throws -> BowlingDNA {
        let videoData = try Data(contentsOf: clipURL)
        let base64Video = videoData.base64EncodedString()

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["inlineData": ["mimeType": "video/mp4", "data": base64Video]],
                    ["text": Self.dnaExtractionPrompt]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]

        log.debug("Extracting BowlingDNA from: \(clipURL.lastPathComponent)")
        let data = try await requestJSON(
            payload: payload,
            candidateModels: [WBConfig.deepAnalysisModel, WBConfig.analysisModel]
        )

        var dna = try parseDNAResponse(data)

        // Fill in MediaPipe-derived fields
        if let omega = wristOmega {
            dna.wristOmegaNormalized = Self.normalizeOmega(omega)
        }
        if let y = releaseWristY {
            dna.releaseWristYNormalized = min(max(y, 0), 1)
        }

        return dna
    }

    /// Normalize wrist angular velocity: clamp((|omega| - 800) / 1200, 0, 1)
    static func normalizeOmega(_ omega: Double) -> Double {
        return min(max((abs(omega) - 800.0) / 1200.0, 0.0), 1.0)
    }

    private func parseDNAResponse(_ data: Data) throws -> BowlingDNA {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first(where: { $0["text"] != nil })?["text"] as? String else {
            throw AnalysisError.parseError
        }

        guard let textData = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: textData) as? [String: Any] else {
            throw AnalysisError.parseError
        }

        log.debug("DNA result: \(text.prefix(200))")

        return BowlingDNA(
            runUpStride: (result["run_up_stride"] as? String).flatMap(RunUpStrideCategory.init),
            runUpSpeed: (result["run_up_speed"] as? String).flatMap(RunUpSpeed.init),
            approachAngle: (result["approach_angle"] as? String).flatMap(ApproachAngle.init),
            gatherAlignment: (result["gather_alignment"] as? String).flatMap(BodyAlignment.init),
            backFootContact: (result["back_foot_contact"] as? String).flatMap(BackFootContact.init),
            trunkLean: (result["trunk_lean"] as? String).flatMap(TrunkLean.init),
            deliveryStrideLength: (result["delivery_stride_length"] as? String).flatMap(StrideLength.init),
            frontArmAction: (result["front_arm_action"] as? String).flatMap(FrontArmAction.init),
            headStability: (result["head_stability"] as? String).flatMap(HeadStability.init),
            armPath: (result["arm_path"] as? String).flatMap(ArmPath.init),
            releaseHeight: (result["release_height"] as? String).flatMap(ReleaseHeight.init),
            wristPosition: (result["wrist_position"] as? String).flatMap(WristPosition.init),
            seamOrientation: (result["seam_orientation"] as? String).flatMap(SeamOrientation.init),
            revolutions: (result["revolutions"] as? String).flatMap(Revolutions.init),
            followThroughDirection: (result["follow_through_direction"] as? String).flatMap(FollowThroughDir.init),
            balanceAtFinish: (result["balance_at_finish"] as? String).flatMap(BalanceAtFinish.init)
        )
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
        You are evaluating a cricket bowling delivery against a target.

        TARGET: "\(target)"

        Did the bowler achieve the target? Respond with JSON:
        {
          "matches_target": true,
          "confidence": 0.7,
          "explanation": "Good yorker on off stump, right on target",
          "detected_length": "yorker",
          "detected_line": "off"
        }
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
            candidateModels: [WBConfig.deliveryDetectionModel, WBConfig.deepAnalysisModel, WBConfig.analysisModel]
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
            dna = BowlingDNA(
                runUpStride: (dnaDict["run_up_stride"] as? String).flatMap(RunUpStrideCategory.init),
                runUpSpeed: (dnaDict["run_up_speed"] as? String).flatMap(RunUpSpeed.init),
                approachAngle: (dnaDict["approach_angle"] as? String).flatMap(ApproachAngle.init),
                gatherAlignment: (dnaDict["gather_alignment"] as? String).flatMap(BodyAlignment.init),
                backFootContact: (dnaDict["back_foot_contact"] as? String).flatMap(BackFootContact.init),
                trunkLean: (dnaDict["trunk_lean"] as? String).flatMap(TrunkLean.init),
                deliveryStrideLength: (dnaDict["delivery_stride_length"] as? String).flatMap(StrideLength.init),
                frontArmAction: (dnaDict["front_arm_action"] as? String).flatMap(FrontArmAction.init),
                headStability: (dnaDict["head_stability"] as? String).flatMap(HeadStability.init),
                armPath: (dnaDict["arm_path"] as? String).flatMap(ArmPath.init),
                releaseHeight: (dnaDict["release_height"] as? String).flatMap(ReleaseHeight.init),
                wristPosition: (dnaDict["wrist_position"] as? String).flatMap(WristPosition.init),
                seamOrientation: (dnaDict["seam_orientation"] as? String).flatMap(SeamOrientation.init),
                revolutions: (dnaDict["revolutions"] as? String).flatMap(Revolutions.init),
                followThroughDirection: (dnaDict["follow_through_direction"] as? String).flatMap(FollowThroughDir.init),
                balanceAtFinish: (dnaDict["balance_at_finish"] as? String).flatMap(BalanceAtFinish.init)
            )
            log.debug("DNA extracted from deep analysis response")
        }

        return DeliveryDeepAnalysisResult(
            paceEstimate: paceEstimate,
            summary: summary,
            phases: phases,
            expertAnalysis: expertAnalysis,
            dna: dna
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

    private func requestJSON(payload: [String: Any], candidateModels: [String]) async throws -> Data {
        var lastError: Error = AnalysisError.parseError
        var triedAtLeastOne = false

        for model in candidateModels where !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            triedAtLeastOne = true
            do {
                log.debug("JSON request attempt: model=\(model, privacy: .public)")
                let url = WBConfig.generateContentURL(model: model)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AnalysisError.parseError
                }
                guard httpResponse.statusCode == 200 else {
                    log.debug("JSON request non-200: model=\(model, privacy: .public), status=\(httpResponse.statusCode)")
                    if httpResponse.statusCode == 404 || httpResponse.statusCode == 400 {
                        continue
                    }
                    throw AnalysisError.apiError(httpResponse.statusCode)
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
