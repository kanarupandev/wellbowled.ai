import SwiftUI

/// Admin dashboard for tuning all configurable thresholds, grouped by feature area.
/// Each value has a tooltip explaining what it controls.
struct AdminDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expandedSection: String?

    var body: some View {
        NavigationView {
            List {
                cliffDetectionSection
                speedEstimationSection
                calibrationSection
                cameraSection
                deliveryDetectionSection
                ttsSection
                liveAPISection
                postSessionSection
                liveSegmentSection
                analysisSection
                featureFlagsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Admin Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Cliff Detection

    private var cliffDetectionSection: some View {
        Section {
            ConfigSlider(
                title: "Drop Threshold",
                value: Binding(get: { AdminConfig.cliffDropThreshold }, set: { AdminConfig.cliffDropThreshold = $0 }),
                range: 0.1...0.8, step: 0.05,
                tooltip: "Energy ratio for cliff trigger. 0.4 = 60% drop needed. Lower = more sensitive, more false positives."
            )
            ConfigSlider(
                title: "Min Pre-Energy",
                value: Binding(get: { AdminConfig.cliffMinPreEnergy }, set: { AdminConfig.cliffMinPreEnergy = $0 }),
                range: 0.5...5.0, step: 0.1,
                tooltip: "Minimum energy before a cliff can be detected. Lower = catches slow deliveries but more noise."
            )
            ConfigStepper(
                title: "Rising Window",
                value: Binding(get: { AdminConfig.cliffRisingWindow }, set: { AdminConfig.cliffRisingWindow = $0 }),
                range: 1...8,
                tooltip: "Frames of rising energy required before the drop. Fewer = faster trigger, more false positives."
            )
            ConfigSlider(
                title: "Min Disarm (sec)",
                value: Binding(get: { AdminConfig.cliffMinDisarmSeconds }, set: { AdminConfig.cliffMinDisarmSeconds = $0 }),
                range: 0.5...5.0, step: 0.5,
                tooltip: "Minimum seconds after stumps hit before checking for re-arm. Prevents double-triggers."
            )
            ConfigSlider(
                title: "Rearm Quiet (sec)",
                value: Binding(get: { AdminConfig.cliffRearmQuietSeconds }, set: { AdminConfig.cliffRearmQuietSeconds = $0 }),
                range: 0.5...5.0, step: 0.5,
                tooltip: "Seconds of continuous quiet needed to re-arm. Longer = safer but slower recovery."
            )
            ConfigSlider(
                title: "Quiet Threshold",
                value: Binding(get: { AdminConfig.cliffQuietThreshold }, set: { AdminConfig.cliffQuietThreshold = $0 }),
                range: 0.2...3.0, step: 0.1,
                tooltip: "Energy below this counts as 'quiet' for re-arming. Lower = stricter, slower re-arm."
            )
            ConfigSlider(
                title: "Max Disarm (sec)",
                value: Binding(get: { AdminConfig.cliffMaxDisarmSeconds }, set: { AdminConfig.cliffMaxDisarmSeconds = $0 }),
                range: 30...300, step: 10,
                tooltip: "Force re-arm after this many seconds. Safety valve against stuck-disarmed state."
            )
        } header: {
            Label("Cliff Detection", systemImage: "waveform.path.ecg")
        } footer: {
            Text("Controls stump impact detection sensitivity. Favor false positives over missed deliveries.")
        }
    }

    // MARK: - Speed Estimation

    private var speedEstimationSection: some View {
        Section {
            ConfigSlider(
                title: "ROI Width Ratio",
                value: Binding(get: { Double(WBConfig.speedROIWidthRatio) }, set: { _ in }),
                range: 0.05...0.3, step: 0.01,
                tooltip: "Width of stump ROI for frame differencing (fraction of frame width). Wider = catches more but adds noise."
            )
            ConfigSlider(
                title: "Motion Threshold",
                value: Binding(get: { WBConfig.speedMotionThreshold }, set: { _ in }),
                range: 10...80, step: 5,
                tooltip: "Pixel-difference threshold for motion energy. Lower = more sensitive to subtle ball movement."
            )
            ConfigSlider(
                title: "Min Transit (sec)",
                value: Binding(get: { WBConfig.speedMinTransitSeconds }, set: { _ in }),
                range: 0.1...0.5, step: 0.05,
                tooltip: "Minimum plausible transit time. Caps maximum detectable speed (~362 kph at 0.2s)."
            )
            ConfigSlider(
                title: "Max Transit (sec)",
                value: Binding(get: { WBConfig.speedMaxTransitSeconds }, set: { _ in }),
                range: 0.5...3.0, step: 0.1,
                tooltip: "Maximum plausible transit time. Floors minimum detectable speed (~48 kph at 1.5s)."
            )
            ConfigStepper(
                title: "Speed Cal FPS",
                value: Binding(get: { WBConfig.speedCalibrationFPS }, set: { _ in }),
                range: 60...240,
                tooltip: "Target camera FPS when speed calibration is active. Higher = more accurate timing."
            )
        } header: {
            Label("Speed Estimation", systemImage: "gauge.with.needle")
        }
    }

    // MARK: - Calibration

    private var calibrationSection: some View {
        Section {
            ConfigSlider(
                title: "Pitch Length (m)",
                value: Binding(get: { WBConfig.pitchLengthMetres }, set: { _ in }),
                range: 10...25, step: 0.1,
                tooltip: "Cricket pitch length stumps-to-stumps. Standard is 20.12m."
            )
            ConfigSlider(
                title: "Box Width Ratio",
                value: Binding(get: { Double(WBConfig.calibrationBoxWidthRatio) }, set: { _ in }),
                range: 0.1...0.4, step: 0.02,
                tooltip: "Width of calibration guide box as fraction of frame width."
            )
            ConfigSlider(
                title: "Box Height Ratio",
                value: Binding(get: { Double(WBConfig.calibrationBoxHeightRatio) }, set: { _ in }),
                range: 0.1...0.5, step: 0.02,
                tooltip: "Height of calibration guide box as fraction of frame height."
            )
            ConfigStepper(
                title: "Stability Frames",
                value: Binding(get: { WBConfig.calibrationStabilityFrames }, set: { _ in }),
                range: 5...30,
                tooltip: "Consecutive stable detections needed to lock stump position."
            )
        } header: {
            Label("Stump Calibration", systemImage: "scope")
        }
    }

    // MARK: - Camera

    private var cameraSection: some View {
        Section {
            ConfigStepper(
                title: "Target FPS",
                value: Binding(get: { WBConfig.cameraTargetFPS }, set: { _ in }),
                range: 24...240,
                tooltip: "Target camera FPS for the capture pipeline."
            )
            ConfigStepper(
                title: "Max FPS",
                value: Binding(get: { WBConfig.cameraMaxFPS }, set: { _ in }),
                range: 24...240,
                tooltip: "Hard ceiling for requested camera FPS."
            )
            ConfigStepper(
                title: "Fallback FPS",
                value: Binding(get: { WBConfig.cameraFallbackFPS }, set: { _ in }),
                range: 15...60,
                tooltip: "Fallback FPS when target format is unavailable."
            )
        } header: {
            Label("Camera", systemImage: "camera")
        }
    }

    // MARK: - Delivery Detection

    private var deliveryDetectionSection: some View {
        Section {
            ConfigSlider(
                title: "Wrist Velocity Threshold",
                value: Binding(get: { WBConfig.wristVelocityThreshold }, set: { _ in }),
                range: 200...1000, step: 25,
                tooltip: "Min angular velocity (deg/s) to trigger delivery. Bowling peaks 1000-1900, arm swings 200-350."
            )
            ConfigSlider(
                title: "Delivery Cooldown (sec)",
                value: Binding(get: { WBConfig.deliveryCooldown }, set: { _ in }),
                range: 1...15, step: 0.5,
                tooltip: "Minimum seconds between delivery detections. Prevents double-counting."
            )
            ConfigSlider(
                title: "Clip Pre-Roll (sec)",
                value: Binding(get: { WBConfig.clipPreRoll }, set: { _ in }),
                range: 1...5, step: 0.5,
                tooltip: "Seconds before delivery to include in clip."
            )
            ConfigSlider(
                title: "Clip Post-Roll (sec)",
                value: Binding(get: { WBConfig.clipPostRoll }, set: { _ in }),
                range: 1...5, step: 0.5,
                tooltip: "Seconds after delivery to include in clip."
            )
        } header: {
            Label("Delivery Detection", systemImage: "figure.cricket")
        }
    }

    // MARK: - TTS

    private var ttsSection: some View {
        Section {
            ConfigSlider(
                title: "Speech Rate",
                value: Binding(get: { Double(WBConfig.ttsRate) }, set: { _ in }),
                range: 0.3...0.7, step: 0.02,
                tooltip: "TTS speech rate. 0.0 = slowest, 1.0 = fastest. Default 0.52."
            )
        } header: {
            Label("Text-to-Speech", systemImage: "speaker.wave.2")
        }
    }

    // MARK: - Live API

    private var liveAPISection: some View {
        Section {
            ConfigSlider(
                title: "Frame Rate to API",
                value: Binding(get: { WBConfig.liveAPIFrameRate }, set: { _ in }),
                range: 0.5...5.0, step: 0.5,
                tooltip: "FPS sent to Live API. Lower = less bandwidth. Higher = better visual context."
            )
            ConfigStepper(
                title: "JPEG Quality",
                value: Binding(get: { WBConfig.liveAPIJPEGQuality }, set: { _ in }),
                range: 20...100,
                tooltip: "JPEG compression quality for API frames. Lower = smaller, faster. Higher = clearer."
            )
            ConfigStepper(
                title: "Max Frame Dimension",
                value: Binding(get: { WBConfig.liveAPIMaxFrameDimension }, set: { _ in }),
                range: 256...1024,
                tooltip: "Maximum pixel dimension for frames sent to API."
            )
            ConfigSlider(
                title: "Default Session (sec)",
                value: Binding(get: { WBConfig.liveSessionDefaultDurationSeconds }, set: { _ in }),
                range: 60...900, step: 30,
                tooltip: "Default session duration before mate sets it. 300 = 5 minutes."
            )
        } header: {
            Label("Live API", systemImage: "antenna.radiowaves.left.and.right")
        }
    }

    // MARK: - Post-Session

    private var postSessionSection: some View {
        Section {
            ConfigSlider(
                title: "Segment Duration (sec)",
                value: Binding(get: { WBConfig.deliveryDetectionSegmentDurationSeconds }, set: { _ in }),
                range: 15...120, step: 5,
                tooltip: "Rolling segment length for post-session release detection."
            )
            ConfigSlider(
                title: "Segment Overlap (sec)",
                value: Binding(get: { WBConfig.deliveryDetectionSegmentOverlapSeconds }, set: { _ in }),
                range: 1...15, step: 1,
                tooltip: "Overlap between segments to catch deliveries at boundaries."
            )
            ConfigSlider(
                title: "Merge Window (sec)",
                value: Binding(get: { WBConfig.deliveryDetectionMergeWindowSeconds }, set: { _ in }),
                range: 0.2...2.0, step: 0.1,
                tooltip: "Dedupe window for merging live and Gemini release timestamps."
            )
        } header: {
            Label("Post-Session Analysis", systemImage: "chart.bar.doc.horizontal")
        }
    }

    // MARK: - Live Segment

    private var liveSegmentSection: some View {
        Section {
            ConfigSlider(
                title: "Segment Duration (sec)",
                value: Binding(get: { WBConfig.liveSegmentDurationSeconds }, set: { _ in }),
                range: 10...60, step: 5,
                tooltip: "Duration of each segment sent to Gemini Flash for live delivery detection."
            )
            ConfigSlider(
                title: "Confidence Threshold",
                value: Binding(get: { WBConfig.liveSegmentConfidenceThreshold }, set: { _ in }),
                range: 0.5...1.0, step: 0.02,
                tooltip: "Minimum Gemini Flash confidence to trigger deep analysis. High = fewer false positives."
            )
            ConfigSlider(
                title: "Overlap (sec)",
                value: Binding(get: { WBConfig.liveSegmentOverlapSeconds }, set: { _ in }),
                range: 1...10, step: 1,
                tooltip: "Overlap between consecutive live segments."
            )
        } header: {
            Label("Live Segment Detection", systemImage: "waveform")
        }
    }

    // MARK: - Analysis

    private var analysisSection: some View {
        Section {
            ConfigSlider(
                title: "Temperature",
                value: Binding(get: { WBConfig.analysisTemperature }, set: { _ in }),
                range: 0.0...1.0, step: 0.05,
                tooltip: "Gemini temperature for analysis calls. Low = more consistent. High = more creative."
            )
        } header: {
            Label("Gemini Analysis", systemImage: "brain")
        }
    }

    // MARK: - Feature Flags

    private var featureFlagsSection: some View {
        Section {
            ConfigToggle(title: "TTS", value: WBConfig.enableTTS, tooltip: "Enable on-device speech announcements.")
            ConfigToggle(title: "Live API Mate", value: WBConfig.enableLiveAPI, tooltip: "Enable live voice mate coaching via Gemini.")
            ConfigToggle(title: "Challenge Mode", value: WBConfig.enableChallengeMode, tooltip: "Enable target challenge drills.")
            ConfigToggle(title: "Post-Session Analysis", value: WBConfig.enablePostSessionAnalysis, tooltip: "Enable Gemini post-session deep analysis.")
            ConfigToggle(title: "Speed Calibration", value: WBConfig.enableSpeedCalibration, tooltip: "Enable stump calibration for speed estimation.")
        } header: {
            Label("Feature Flags", systemImage: "flag")
        }
    }
}

// MARK: - Reusable Config Components

private struct ConfigSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tooltip: String

    @State private var showTooltip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Button { showTooltip.toggle() } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(formatValue(value))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
            if showTooltip {
                Text(tooltip)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 2)
            }
            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 2)
    }

    private func formatValue(_ v: Double) -> String {
        if v == v.rounded() && v >= 10 { return String(format: "%.0f", v) }
        if v < 0.01 { return String(format: "%.3f", v) }
        return String(format: "%.2f", v)
    }
}

private struct ConfigStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let tooltip: String

    @State private var showTooltip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Button { showTooltip.toggle() } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(value)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
            }
            if showTooltip {
                Text(tooltip)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 2)
            }
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

private struct ConfigToggle: View {
    let title: String
    let value: Bool
    let tooltip: String

    @State private var showTooltip = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Button { showTooltip.toggle() } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: value ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(value ? .green : .secondary)
            }
            if showTooltip {
                Text(tooltip)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AdminConfig (Persisted Cliff Detection Overrides)

/// Writable admin overrides stored in UserDefaults.
/// CliffDetector reads these at init. Other WBConfig values are read-only in the dashboard for now.
enum AdminConfig {
    private static let defaults = UserDefaults.standard

    static var cliffDropThreshold: Double {
        get { defaults.object(forKey: "admin.cliff.dropThreshold") as? Double ?? 0.4 }
        set { defaults.set(newValue, forKey: "admin.cliff.dropThreshold") }
    }
    static var cliffMinPreEnergy: Double {
        get { defaults.object(forKey: "admin.cliff.minPreEnergy") as? Double ?? 1.5 }
        set { defaults.set(newValue, forKey: "admin.cliff.minPreEnergy") }
    }
    static var cliffRisingWindow: Int {
        get { defaults.object(forKey: "admin.cliff.risingWindow") as? Int ?? 2 }
        set { defaults.set(newValue, forKey: "admin.cliff.risingWindow") }
    }
    static var cliffMinDisarmSeconds: Double {
        get { defaults.object(forKey: "admin.cliff.minDisarmSeconds") as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: "admin.cliff.minDisarmSeconds") }
    }
    static var cliffRearmQuietSeconds: Double {
        get { defaults.object(forKey: "admin.cliff.rearmQuietSeconds") as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: "admin.cliff.rearmQuietSeconds") }
    }
    static var cliffQuietThreshold: Double {
        get { defaults.object(forKey: "admin.cliff.quietThreshold") as? Double ?? 0.8 }
        set { defaults.set(newValue, forKey: "admin.cliff.quietThreshold") }
    }
    static var cliffMaxDisarmSeconds: Double {
        get { defaults.object(forKey: "admin.cliff.maxDisarmSeconds") as? Double ?? 120.0 }
        set { defaults.set(newValue, forKey: "admin.cliff.maxDisarmSeconds") }
    }
}

#if DEBUG
struct AdminDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        AdminDashboardView()
    }
}
#endif
