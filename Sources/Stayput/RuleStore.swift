import AppKit
import Combine
import ServiceManagement
import StayputCore

@MainActor
final class RuleStore: ObservableObject {
    @Published var rules: [WindowRule] = [] {
        didSet {
            save()
            manager.syncObservers(for: rules)
        }
    }
    @Published var runningApplications: [RunningApplication] = []
    @Published var permissionGranted = false
    @Published var launchAtLogin = false
    @Published var statusMessage: String?

    private let manager = AccessibilityWindowManager()
    private let defaultsKey = "windowRules"
    private var reapplyTask: Task<Void, Never>?
    private var launchTasks: [pid_t: Task<Void, Never>] = [:]
    private var resizeCaptureTasks: [pid_t: Task<Void, Never>] = [:]
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var applicationIconCache: [String: NSImage] = [:]

    init() {
        load()
        permissionGranted = manager.isTrusted
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshApplications()
        installObservers()
        startPermissionPolling()
        manager.syncObservers(for: rules)
        manager.onPrimaryWindowResized = { [weak self] pid, size in
            self?.primaryWindowDidResize(pid: pid, size: size)
        }
        scheduleReapply(after: .seconds(1))
    }

    func requestPermission() {
        manager.requestPermission()
        statusMessage = "Grant Stay Put access in System Settings, then return here."
    }

    func refreshApplications() {
        runningApplications = manager.runningApplications()
        for application in runningApplications {
            if let icon = application.icon {
                applicationIconCache[application.bundleIdentifier] = icon
            }
        }
    }

    func applicationIcon(for bundleIdentifier: String) -> NSImage? {
        if let cached = applicationIconCache[bundleIdentifier] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage else {
            return nil
        }
        applicationIconCache[bundleIdentifier] = icon
        return icon
    }

    func addRule(for application: RunningApplication) {
        guard !rules.contains(where: { $0.bundleIdentifier == application.bundleIdentifier }) else {
            return
        }
        let size = manager.frontWindowSize(for: application.bundleIdentifier) ?? CGSize(width: 900, height: 650)
        rules.append(WindowRule(
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.name,
            placement: .center,
            centeredWidth: size.width,
            centeredHeight: size.height
        ))
        applyNow()
    }

    func removeRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
    }

    func captureSize(for ruleID: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }),
              let size = manager.frontWindowSize(for: rules[index].bundleIdentifier) else {
            statusMessage = "Open a window for that app before capturing its size."
            return
        }
        rules[index].centeredWidth = size.width
        rules[index].centeredHeight = size.height
        statusMessage = "Captured \(Int(size.width)) × \(Int(size.height))."
    }

    func applyNow() {
        permissionGranted = manager.isTrusted
        guard permissionGranted else {
            requestPermission()
            return
        }
        manager.apply(rules)
        statusMessage = rules.isEmpty ? "Add an app rule first." : "Applied \(rules.count) rule\(rules.count == 1 ? "" : "s")."
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            statusMessage = "Could not update login item: \(error.localizedDescription)"
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([WindowRule].self, from: data) else { return }
        rules = stored
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleReapply(after: .seconds(2)) }
        })

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleReapply(after: .seconds(1)) }
        })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            Task { @MainActor in self?.applicationDidLaunch(application) }
        })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            Task { @MainActor in
                self?.launchTasks[application.processIdentifier]?.cancel()
                self?.launchTasks[application.processIdentifier] = nil
                self?.resizeCaptureTasks[application.processIdentifier]?.cancel()
                self?.resizeCaptureTasks[application.processIdentifier] = nil
                self?.manager.stopObserving(pid: application.processIdentifier)
                self?.refreshApplications()
            }
        })
    }

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let trusted = self.manager.isTrusted
                if trusted && !self.permissionGranted {
                    self.permissionGranted = true
                    self.statusMessage = "Accessibility access granted."
                    self.manager.syncObservers(for: self.rules)
                    self.applyNow()
                } else {
                    self.permissionGranted = trusted
                }
            }
        }
    }

    private func scheduleReapply(after delay: Duration) {
        reapplyTask?.cancel()
        reapplyTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.applySilently()
        }
    }

    private func applicationDidLaunch(_ application: NSRunningApplication) {
        refreshApplications()
        guard let bundleIdentifier = application.bundleIdentifier,
              let rule = rules.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return
        }

        let pid = application.processIdentifier
        manager.startObserving(rule, pid: pid)
        launchTasks[pid]?.cancel()
        launchTasks[pid] = Task { [weak self] in
            // Window creation and state restoration happen after didLaunchApplication.
            // Reapply through that settling period so slow-starting apps are covered too.
            for delay in [0.2, 0.6, 1.2, 2.5, 5.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.manager.apply(rule, to: pid, reselectPrimary: true)
            }
            self?.launchTasks[pid] = nil
        }
    }

    private func primaryWindowDidResize(pid: pid_t, size: CGSize) {
        resizeCaptureTasks[pid]?.cancel()
        resizeCaptureTasks[pid] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self,
                  let application = NSRunningApplication(processIdentifier: pid),
                  let bundleIdentifier = application.bundleIdentifier,
                  let index = self.rules.firstIndex(where: {
                      $0.bundleIdentifier == bundleIdentifier
                  }) else { return }
            self.rules[index].centeredWidth = size.width
            self.rules[index].centeredHeight = size.height
            self.statusMessage = "Remembered \(self.rules[index].applicationName) at \(Int(size.width)) × \(Int(size.height))."
            self.resizeCaptureTasks[pid] = nil
        }
    }

    private func applySilently() {
        permissionGranted = manager.isTrusted
        guard permissionGranted else { return }
        manager.apply(rules)
    }

}
