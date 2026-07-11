import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindowController?
    private static var store: RuleStore?

    static func configure(with store: RuleStore) {
        self.store = store
    }

    static func show() {
        guard let store else { return }
        if shared == nil {
            shared = SettingsWindowController(store: store)
        }
        shared?.showWindow(nil)
    }

    private init(store: RuleStore) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 900, height: 560)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = "Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .automatic
        window.toolbar = NSToolbar(identifier: "SettingsToolbar")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 760, height: 500)
        window.setFrameAutosaveName("SettingsWindow")
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SettingsView().environmentObject(store)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
    }
}
