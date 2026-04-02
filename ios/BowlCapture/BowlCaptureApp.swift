import SwiftUI

@main
struct BowlCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureView()
                .preferredColorScheme(.dark)
        }
    }
}
