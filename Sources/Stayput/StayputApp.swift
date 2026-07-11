import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        SettingsWindowController.show()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            SettingsWindowController.show()
        }
        return true
    }
}

@main
struct StayPutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: RuleStore

    init() {
        let store = RuleStore()
        _store = StateObject(wrappedValue: store)
        SettingsWindowController.configure(with: store)
    }

    var body: some Scene {
        MenuBarExtra("Stay Put", systemImage: "macwindow.on.rectangle") {
            Button("Apply Rules") { store.applyNow() }
                .keyboardShortcut("r")
            Button("Settings…") { SettingsWindowController.show() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Stay Put") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindowController.show() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
