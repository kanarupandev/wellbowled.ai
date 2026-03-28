import SwiftUI

private let peacockBlue = Color(red: 0, green: 0.427, blue: 0.467)

/// Inline overlay shown after stumps are detected.
/// User confirms distance, taps "Start Monitoring".
struct SpeedSetupOverlay: View {

    @Binding var distanceMetres: Double
    let onStart: () -> Void

    private enum Preset: String, CaseIterable {
        case stumps = "Stumps"
        case wall = "Wall"
        case custom = "Custom"

        var defaultDistance: Double? {
            switch self {
            case .stumps: return 18.9
            case .wall: return nil
            case .custom: return nil
            }
        }
    }

    @State private var selectedPreset: Preset = .stumps
    @State private var distanceText: String = "18.9"
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
                Text("Stumps Detected")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            // Preset tabs
            HStack(spacing: 0) {
                ForEach(Preset.allCases, id: \.self) { preset in
                    Button {
                        selectedPreset = preset
                        if let d = preset.defaultDistance {
                            distanceText = String(format: "%.1f", d)
                            distanceMetres = d
                        }
                        isEditing = preset != .stumps
                    } label: {
                        Text(preset.rawValue)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(selectedPreset == preset ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                selectedPreset == preset
                                    ? Color.white
                                    : Color.white.opacity(0.1)
                            )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Distance input
            HStack(spacing: 8) {
                Text("Distance")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                TextField("0.0", text: $distanceText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .focused($isEditing)
                    .onChange(of: distanceText) { newValue in
                        if let d = Double(newValue), d > 0 {
                            distanceMetres = d
                        }
                    }

                Text("m")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Start button
            Button(action: {
                isEditing = false
                onStart()
            }) {
                Text("Start Monitoring")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(peacockBlue)
                    .cornerRadius(8)
            }
            .disabled(distanceMetres <= 0)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 40)
        .onAppear {
            distanceText = String(format: "%.1f", distanceMetres)
        }
    }
}

#if DEBUG
struct SpeedSetupOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SpeedSetupOverlay(
                distanceMetres: .constant(18.9),
                onStart: {}
            )
        }
    }
}
#endif
