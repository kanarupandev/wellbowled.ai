import SwiftUI
import AVFoundation
import Combine
import UIKit

private let appLaunchTime = CACurrentMediaTime()

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct wellBowledApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var isLoading = true
    @StateObject private var appState = AppLaunchState()
    @State private var didPlayStartupWhizz = false
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isLoading {
                    SplashView()
                        .transition(.opacity)
                } else {
                    HomeView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: isLoading)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                print("🚀 [PERF] [T0] App Launched at \(Date()). Reference time: \(appLaunchTime)")
                Task {
                    await appState.initialize()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await MainActor.run {
                        isLoading = false
                    }
                    triggerStartupWhizzIfNeeded()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Keep idle timer disabled whenever app is active — phone must not lock during sessions
                if newPhase == .active {
                    UIApplication.shared.isIdleTimerDisabled = true
                    triggerStartupWhizzIfNeeded()
                }
            }
        }
    }

    @MainActor
    private func triggerStartupWhizzIfNeeded() {
        guard !didPlayStartupWhizz else { return }
        didPlayStartupWhizz = true
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            AudioSessionManager.shared.playStartupWhizzIfNeeded()
        }
    }
}

@MainActor
class AppLaunchState: ObservableObject {
    @Published var isReady = false
    
    func initialize() async {
        await AVCaptureDevice.requestAccess(for: .video)
        await AVCaptureDevice.requestAccess(for: .audio)
        isReady = true
    }
}
