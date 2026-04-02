import SwiftUI

struct SessionSetupView: View {
    @StateObject private var session = BowlSession()
    @State private var distanceText = "58"
    @State private var navigateToCapture = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Title
                VStack(spacing: 8) {
                    Image(systemName: "sportscourt.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color(red: 0, green: 0.427, blue: 0.467))

                    Text("Bowl Capture")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)

                    Text("120fps Bowling Analysis")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                // Reference Distance
                VStack(spacing: 16) {
                    Text("Reference Distance")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Set a known distance in your scene for measurement.\nDefault: bowling crease to stumps (58 ft)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        TextField("58", text: $distanceText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .frame(width: 120)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)

                        Text("feet")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                }
                .padding(24)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)

                Spacer()

                // Start Button
                NavigationLink(destination: CaptureView(session: session), isActive: $navigateToCapture) {
                    EmptyView()
                }

                Button {
                    if let dist = Double(distanceText), dist > 0 {
                        session.referenceDistanceFeet = dist
                    }
                    navigateToCapture = true
                } label: {
                    HStack {
                        Image(systemName: "video.fill")
                        Text("Start Session")
                    }
                    .font(.title3.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0, green: 0.427, blue: 0.467))
                    .cornerRadius(14)
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 32)
        }
        .navigationBarHidden(true)
    }
}
