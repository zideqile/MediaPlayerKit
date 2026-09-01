import SwiftUI

@main
public struct MediaPlayerKitDemoApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                #endif
        }
    }
}
