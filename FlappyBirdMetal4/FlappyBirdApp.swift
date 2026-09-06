import SwiftUI

@main
struct FlappyBirdApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(iOS)
                .preferredColorScheme(.dark)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 420, height: 720)
        .windowResizability(.contentSize)
        #endif
    }
}
