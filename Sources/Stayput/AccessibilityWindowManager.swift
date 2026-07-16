import AppKit
import ApplicationServices
import StayputCore

struct RunningApplication: Identifiable, Hashable {
    let pid: pid_t
    let bundleIdentifier: String
    let name: String
    let icon: NSImage?

    var id: String { "\(bundleIdentifier):\(pid)" }
}

@MainActor
final class AccessibilityWindowManager {
    private struct ObserverEvent: @unchecked Sendable {
        let observer: AXObserver
        let element: AXUIElement
        let notification: String
    }

    private var primaryWindows: [pid_t: AXUIElement] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var observedRules: [pid_t: WindowRule] = [:]
    private var suppressedResizeTasks: [CFHashCode: Task<Void, Never>] = [:]
    var onPrimaryWindowResized: ((pid_t, CGSize) -> Void)?

    private nonisolated(unsafe) static let observerCallback: AXObserverCallback = {
        observer, element, notification, context in
        guard let context else { return }
        let manager = Unmanaged<AccessibilityWindowManager>.fromOpaque(context).takeUnretainedValue()
        let event = ObserverEvent(
            observer: observer,
            element: element,
            notification: notification as String
        )
        MainActor.assumeIsolated {
            manager.handle(
                observer: event.observer,
                element: event.element,
                notification: event.notification
            )
        }
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func runningApplications() -> [RunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                    app.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                    app.bundleIdentifier != nil
            }
            .compactMap { app in
                guard let bundleIdentifier = app.bundleIdentifier else { return nil }
                return RunningApplication(
                    pid: app.processIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    name: app.localizedName ?? bundleIdentifier,
                    icon: pickerIcon(from: app.icon)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func pickerIcon(from source: NSImage?) -> NSImage? {
        guard let icon = source?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    func frontWindowSize(for bundleIdentifier: String) -> CGSize? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }), let window = primaryWindow(for: app.processIdentifier) else {
            return nil
        }
        return size(of: window)
    }

    func syncObservers(for rules: [WindowRule]) {
        guard isTrusted else { return }
        let rulesByBundleIdentifier = Dictionary(uniqueKeysWithValues: rules.map {
            ($0.bundleIdentifier, $0)
        })
        let applications = NSWorkspace.shared.runningApplications
        let targetPIDs = Set(applications.compactMap { application -> pid_t? in
            guard let bundleIdentifier = application.bundleIdentifier,
                  rulesByBundleIdentifier[bundleIdentifier] != nil else { return nil }
            return application.processIdentifier
        })

        for pid in observers.keys where !targetPIDs.contains(pid) {
            stopObserving(pid: pid)
        }
        for application in applications {
            guard let bundleIdentifier = application.bundleIdentifier,
                  let rule = rulesByBundleIdentifier[bundleIdentifier] else { continue }
            startObserving(rule, pid: application.processIdentifier)
        }
    }

    func startObserving(_ rule: WindowRule, pid: pid_t) {
        observedRules[pid] = rule
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, Self.observerCallback, &observer) == .success,
              let observer else { return }

        let application = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(
            observer,
            application,
            kAXWindowCreatedNotification as CFString,
            context
        ) == .success else { return }
        for notification in [kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(
                observer,
                application,
                notification as CFString,
                context
            )
        }

        observers[pid] = observer
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    func stopObserving(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observedRules[pid] = nil
        primaryWindows[pid] = nil
    }

    func apply(_ rules: [WindowRule]) {
        guard isTrusted else { return }

        let applications = NSWorkspace.shared.runningApplications
        for rule in rules {
            for application in applications where application.bundleIdentifier == rule.bundleIdentifier {
                apply(rule, to: application.processIdentifier)
            }
        }
    }

    @discardableResult
    func apply(_ rule: WindowRule, to pid: pid_t, reselectPrimary: Bool = false) -> Int {
        guard isTrusted else { return 0 }
        if reselectPrimary {
            primaryWindows[pid] = nil
        }
        guard let window = primaryWindow(for: pid) else { return 0 }
        observeChanges(of: window, pid: pid)
        place(window, using: rule, pid: pid)
        return 1
    }

    private func primaryWindow(for pid: pid_t) -> AXUIElement? {
        if let tracked = primaryWindows[pid], frame(of: tracked) != nil {
            return tracked
        }
        primaryWindows[pid] = nil

        let application = AXUIElementCreateApplication(pid)
        if let mainWindow = elementAttribute(kAXMainWindowAttribute, of: application),
           isMainWindowCandidate(mainWindow) {
            primaryWindows[pid] = mainWindow
            return mainWindow
        }

        let candidate = windows(for: pid)
            .filter(isPrimaryCandidate)
            .max { lhs, rhs in
                (frame(of: lhs)?.width ?? 0) * (frame(of: lhs)?.height ?? 0) <
                    (frame(of: rhs)?.width ?? 0) * (frame(of: rhs)?.height ?? 0)
            }
        if let candidate {
            primaryWindows[pid] = candidate
        }
        return candidate
    }

    private func isMainWindowCandidate(_ window: AXUIElement) -> Bool {
        stringAttribute(kAXRoleAttribute, of: window) == kAXWindowRole &&
            boolAttribute(kAXModalAttribute, of: window) != true
    }

    private func isPrimaryCandidate(_ window: AXUIElement) -> Bool {
        guard stringAttribute(kAXSubroleAttribute, of: window) == kAXStandardWindowSubrole else {
            return false
        }
        return boolAttribute(kAXModalAttribute, of: window) != true
    }

    private func observeChanges(of window: AXUIElement, pid: pid_t) {
        guard let observer = observers[pid] else { return }
        for notification in [kAXUIElementDestroyedNotification, kAXWindowResizedNotification] {
            let result = AXObserverAddNotification(
                observer,
                window,
                notification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
            // alreadyRegistered is expected during repeated launch-settling passes.
            guard result == .success || result == .notificationAlreadyRegistered else { continue }
        }
    }

    private func handle(observer: AXObserver, element: AXUIElement, notification: String) {
        guard let pid = observers.first(where: { CFEqual($0.value, observer) })?.key,
              let rule = observedRules[pid] else { return }

        switch notification {
        case kAXWindowCreatedNotification:
            // Once a primary is bound, all later windows are pop-outs for our purposes.
            if let primary = primaryWindows[pid], frame(of: primary) != nil {
                return
            }
            if isPrimaryCandidate(element) {
                primaryWindows[pid] = element
                observeChanges(of: element, pid: pid)
                place(element, using: rule, pid: pid)
            }
        case kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification:
            if let primary = primaryWindows[pid], frame(of: primary) != nil {
                return
            }
            apply(rule, to: pid, reselectPrimary: true)
        case kAXUIElementDestroyedNotification:
            guard let primary = primaryWindows[pid], CFEqual(primary, element) else { return }
            primaryWindows[pid] = nil
            // Electron apps can create their replacement window before destroying the old one.
            // Re-select here because its earlier creation notification was intentionally ignored.
            apply(rule, to: pid, reselectPrimary: true)
        case kAXWindowResizedNotification:
            guard let primary = primaryWindows[pid],
                  CFEqual(primary, element),
                  suppressedResizeTasks[CFHash(element)] == nil,
                  let windowSize = size(of: element) else { return }
            onPrimaryWindowResized?(pid, windowSize)
        default:
            break
        }
    }

    private func windows(for pid: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success, let windows = value as? [AXUIElement] else {
            return []
        }

        return windows.filter { window in
            var roleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String else { return false }
            return role == kAXWindowRole
        }
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func boolAttribute(_ attribute: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func place(_ window: AXUIElement, using rule: WindowRule, pid: pid_t) {
        guard let currentFrame = frame(of: window) else { return }
        let screen = targetScreen(for: currentFrame)
        let target = PlacementGeometry.frame(
            for: rule.placement,
            visibleFrame: screen.visibleFrame,
            centeredSize: rule.restoreSize
                ? CGSize(width: rule.centeredWidth, height: rule.centeredHeight)
                : currentFrame.size
        )

        if rule.restoreSize || rule.placement.usesDisplayRelativeSize {
            suppressResizeEvents(for: window)
            // Resize first so apps with minimum sizes do not offset the final position.
            setSize(target.size, of: window)
        }
        if rule.restorePosition {
            setPosition(appKitToAX(target.origin, height: target.height), of: window)
        }
    }

    private func suppressResizeEvents(for window: AXUIElement) {
        let key = CFHash(window)
        suppressedResizeTasks[key]?.cancel()
        suppressedResizeTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.suppressedResizeTasks[key] = nil
        }
    }

    private func targetScreen(for axFrame: CGRect) -> NSScreen {
        let appKitFrame = axToAppKit(axFrame)
        if let containing = NSScreen.screens.first(where: { $0.frame.intersects(appKitFrame) }) {
            return containing
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let position = position(of: window), let size = size(of: window) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func position(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func size(of window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func setPosition(_ point: CGPoint, of window: AXUIElement) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    private func setSize(_ size: CGSize, of window: AXUIElement) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    private var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private func axToAppKit(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func appKitToAX(_ origin: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: origin.x, y: primaryScreenHeight - origin.y - height)
    }
}
