// Launches Yappy as a background accessory app and hands lifecycle control to AppKit.
import SwiftUI

@main
struct YappyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
