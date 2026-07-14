import AppKit
import SwiftUI
import StayputCore
import UniformTypeIdentifiers

private enum SettingsTab: String, CaseIterable, Identifiable {
    case windows
    case general
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .windows: "Windows"
        case .general: "General"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .windows: "macwindow.on.rectangle"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @AppStorage("selectedSettingsTab") private var selectedTab = SettingsTab.windows.rawValue

    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { SettingsTab(rawValue: selectedTab) ?? .windows },
            set: { selectedTab = ($0 ?? .windows).rawValue }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, selection: selection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(SidebarVisualEffect())
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .toolbar(removing: .sidebarToggle)
            .scrollEdgeEffectStyleSoftIfAvailable()
        } detail: {
            SettingsDetailView(tab: SettingsTab(rawValue: selectedTab) ?? .windows)
        }
        .navigationTitle("Settings")
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 500)
    }
}

private struct SettingsDetailView: View {
    let tab: SettingsTab

    var body: some View {
        Group {
            switch tab {
            case .windows: WindowRulesPane()
            case .general: GeneralSettingsPane()
            case .about: AboutPane()
            }
        }
        .navigationTitle(tab.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct WindowRulesPane: View {
    @EnvironmentObject private var store: RuleStore
    @Environment(\.undoManager) private var undoManager
    @State private var selectedApplicationID: RunningApplication.ID?
    @State private var selectedRuleIDs: Set<WindowRule.ID> = []

    private var selectedApplication: RunningApplication? {
        store.runningApplications.first { $0.id == selectedApplicationID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.permissionGranted {
                permissionBanner
            }

            rulesList
            addRuleControls

            HStack {
                if let status = store.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Apply Now") { store.applyNow() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
        .padding(20)
        .onDeleteCommand(perform: removeSelectedRules)
        .focusedValue(\.selectedRuleCommands, SelectedRuleCommands(
            canAct: !selectedRuleIDs.isEmpty,
            copy: copySelectedRules,
            remove: removeSelectedRules
        ))
    }

    private var permissionBanner: some View {
        HStack {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            Text("Accessibility access is required to move and resize windows.")
            Spacer()
            Button("Grant Access") { store.requestPermission() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var rulesList: some View {
        Group {
            if store.rules.isEmpty {
                ContentUnavailableView(
                    "No Window Rules",
                    systemImage: "macwindow.badge.plus",
                    description: Text("Choose a running app below to create one.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                List(selection: $selectedRuleIDs) {
                    ForEach($store.rules) { $rule in
                        RuleRow(
                            rule: $rule,
                            icon: store.applicationIcon(for: rule.bundleIdentifier)
                        ) {
                            store.captureSize(for: rule.id)
                        }
                        .tag(rule.id)
                        .contextMenu {
                            Button("Capture Current Size") {
                                store.captureSize(for: rule.id)
                            }
                            Divider()
                            Button("Copy Rule") {
                                copyRules(withIDs: selectedRuleIDs.contains(rule.id)
                                    ? selectedRuleIDs
                                    : [rule.id])
                            }
                            Button("Remove Rule", role: .destructive) {
                                removeRules(withIDs: selectedRuleIDs.contains(rule.id)
                                    ? selectedRuleIDs
                                    : [rule.id])
                            }
                        }
                    }
                    .onDelete { offsets in
                        removeRules(withIDs: Set(offsets.map { store.rules[$0].id }))
                    }
                }
                .listStyle(.inset)
                .dropDestination(for: URL.self) { urls, _ in
                    addApplications(at: urls)
                }
            }
        }
    }

    private var addRuleControls: some View {
        HStack {
            Picker("Running app", selection: $selectedApplicationID) {
                Text("Choose a running app…").tag(nil as RunningApplication.ID?)
                ForEach(store.runningApplications) { application in
                    HStack {
                        if let icon = application.icon {
                            Image(nsImage: icon)
                                .frame(width: 16, height: 16)
                        }
                        Text(application.name)
                    }
                    .tag(application.id as RunningApplication.ID?)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 300)

            Button("Add Rule") {
                guard let selectedApplication else { return }
                store.addRule(for: selectedApplication)
                selectedApplicationID = nil
            }
            .disabled(selectedApplication == nil)

            Button("Choose Application…", action: chooseApplications)

            Button {
                store.refreshApplications()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh running apps")
            .accessibilityLabel("Refresh running apps")
            Spacer()
        }
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = "Choose Applications"
        panel.prompt = "Add"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        _ = addApplications(at: panel.urls)
    }

    @discardableResult
    private func addApplications(at urls: [URL]) -> Bool {
        urls.reduce(false) { added, url in
            store.addRule(forApplicationAt: url) || added
        }
    }

    private func copySelectedRules() {
        copyRules(withIDs: selectedRuleIDs)
    }

    private func copyRules(withIDs ids: Set<WindowRule.ID>) {
        let text = store.rules
            .filter { ids.contains($0.id) }
            .map { "\($0.applicationName)\t\($0.bundleIdentifier)\t\($0.placement.label)" }
            .joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func removeSelectedRules() {
        removeRules(withIDs: selectedRuleIDs)
    }

    private func removeRules(withIDs ids: Set<WindowRule.ID>) {
        store.removeRules(withIDs: ids, undoManager: undoManager)
        selectedRuleIDs.subtract(ids)
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var store: RuleStore

    var body: some View {
        Form {
            Section("System") {
                Toggle(isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                        Text("Keep window rules active after signing in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        Label(
                            store.permissionGranted ? "Allowed" : "Required",
                            systemImage: store.permissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(store.permissionGranted ? .green : .orange)

                        if !store.permissionGranted {
                            Button("Grant Access") { store.requestPermission() }
                                .controlSize(.small)
                        }
                    }
                }
            }

            Section("Automatic Triggers") {
                Text("Rules are applied after display changes, wake, login, and configured app launches. Primary-window resizes are remembered automatically for Center rules.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

private struct AboutPane: View {
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Stay Put")
                            .font(.largeTitle.bold())
                        Text(versionText)
                            .foregroundStyle(.secondary)
                        Text("Put app windows back where they belong.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Window Management") {
                Text("Stay Put uses macOS Accessibility APIs to remember and restore the primary windows of apps you choose.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

private struct RuleRow: View {
    @Binding var rule: WindowRule
    let icon: NSImage?
    let captureSize: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .padding(3)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.applicationName)
                    .fontWeight(.medium)
                Text(rule.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Placement", selection: $rule.placement) {
                ForEach(WindowPlacement.allCases) { placement in
                    Text(placement.label).tag(placement)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Toggle("Size", isOn: $rule.restoreSize)
                .fixedSize()
                .disabled(rule.placement.usesDisplayRelativeSize)
                .help(rule.placement.usesDisplayRelativeSize
                    ? "Half-screen placements use the current display size"
                    : "Restore the remembered window size")
            Toggle("Position", isOn: $rule.restorePosition)
                .fixedSize()
                .help("Restore the configured window position")

            Text("\(Int(rule.centeredWidth)) × \(Int(rule.centeredHeight))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 95, alignment: .trailing)
            Button("Capture", action: captureSize)
                .help("Use the tracked primary window's current size")
        }
        .padding(.vertical, 5)
    }
}

private extension View {
    @ViewBuilder
    func scrollEdgeEffectStyleSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}
