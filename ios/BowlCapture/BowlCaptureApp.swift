import SwiftUI

@main
struct BowlCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SessionSetupView()
            }
            .preferredColorScheme(.dark)
        }
    }
}
