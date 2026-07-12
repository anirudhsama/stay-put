import AppKit
import SwiftUI

struct SelectedRuleCommands {
    let canAct: Bool
    let copy: () -> Void
    let remove: () -> Void
}

private struct SelectedRuleCommandsKey: FocusedValueKey {
    typealias Value = SelectedRuleCommands
}

extension FocusedValues {
    var selectedRuleCommands: SelectedRuleCommands? {
        get { self[SelectedRuleCommandsKey.self] }
        set { self[SelectedRuleCommandsKey.self] = newValue }
    }
}

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
            RulesCommands(store: store)
        }
    }
}

private struct RulesCommands: Commands {
    let store: RuleStore
    @FocusedValue(\.selectedRuleCommands) private var selectedRuleCommands

    var body: some Commands {
        CommandMenu("Rules") {
            Button("Apply Rules") { store.applyNow() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Refresh Running Applications") { store.refreshApplications() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Copy Selected Rules") { selectedRuleCommands?.copy() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(selectedRuleCommands?.canAct != true)
            Button("Remove Selected Rules") { selectedRuleCommands?.remove() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selectedRuleCommands?.canAct != true)
        }
    }
}
