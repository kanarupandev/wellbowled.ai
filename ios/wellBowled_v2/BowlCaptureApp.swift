import SwiftUI

@main
struct wellBowledApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureView()
                .preferredColorScheme(.dark)
        }
    }
}
