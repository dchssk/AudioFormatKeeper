import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var controller: AppController
    @State private var selectedUID: String?

    private var items: [DeviceSidebarItem] {
        var result = controller.devices.map { device in
            DeviceSidebarItem(
                uid: device.uid,
                name: device.name,
                isConnected: true,
                isDefault: device.isDefaultOutput,
                isEnabled: controller.rule(uid: device.uid)?.isEnabled == true
            )
        }
        for rule in controller.rules where !result.contains(where: { $0.uid == rule.uid }) {
            result.append(DeviceSidebarItem(
                uid: rule.uid,
                name: rule.lastKnownName,
                isConnected: false,
                isDefault: false,
                isEnabled: rule.isEnabled
            ))
        }
        return result.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationSplitView {
            List(items, selection: $selectedUID) { item in
                DeviceSidebarRow(item: item)
                    .tag(item.uid)
            }
            .navigationTitle(L10n.string("settings.output_devices"))
            .frame(minWidth: 220)
        } detail: {
            if let selectedUID,
               let device = controller.device(uid: selectedUID) {
                DeviceSettingsView(controller: controller, device: device)
            } else if let selectedUID,
                      let rule = controller.rule(uid: selectedUID) {
                DisconnectedRuleView(controller: controller, rule: rule)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "speaker.wave.2")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(L10n.string("settings.select_device"))
                        .font(.title3)
                    Text(L10n.string("settings.connected_hint"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 780, idealWidth: 860, minHeight: 520, idealHeight: 620)
        .onAppear { selectFirstDeviceIfNeeded() }
        .onChange(of: items.map(\.uid)) { _ in selectFirstDeviceIfNeeded() }
    }

    private func selectFirstDeviceIfNeeded() {
        guard selectedUID == nil || !items.contains(where: { $0.uid == selectedUID }) else { return }
        selectedUID = items.first?.uid
    }
}

private struct DeviceSidebarItem: Identifiable {
    let uid: String
    let name: String
    let isConnected: Bool
    let isDefault: Bool
    let isEnabled: Bool

    var id: String { uid }
}

private struct DeviceSidebarRow: View {
    let item: DeviceSidebarItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isConnected ? "speaker.wave.2.fill" : "speaker.slash")
                .foregroundStyle(item.isConnected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                HStack(spacing: 5) {
                    if item.isDefault { Text(L10n.string("badge.default")) }
                    if item.isEnabled { Text(L10n.string("badge.locked")) }
                    if !item.isConnected { Text(L10n.string("badge.disconnected")) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DeviceSettingsView: View {
    @ObservedObject var controller: AppController
    let device: AudioDeviceSnapshot

    private var rule: DeviceRule? { controller.rule(uid: device.uid) }

    var body: some View {
        Form {
            Section {
                LabeledContent(L10n.string("field.manufacturer"), value: device.manufacturer)
                LabeledContent(L10n.string("field.connection"), value: device.transport)
                LabeledContent(L10n.string("field.device_uid")) {
                    Text(device.uid)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let rate = device.nominalSampleRate {
                    LabeledContent(
                        L10n.string("field.current_rate"),
                        value: FormatChoice.formatSampleRate(rate)
                    )
                }
            } header: {
                HStack {
                    Text(device.name)
                    if device.isDefaultOutput {
                        Text(L10n.string("badge.system_default"))
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                }
            }

            Section(L10n.string("section.enforcement")) {
                Toggle(L10n.string("setting.enable_rule"), isOn: Binding(
                    get: { rule?.isEnabled ?? false },
                    set: { controller.setEnabled($0, uid: device.uid) }
                ))

                Picker(L10n.string("setting.when_to_enforce"), selection: Binding(
                    get: { rule?.scope ?? .defaultOutput },
                    set: { controller.setScope($0, uid: device.uid) }
                )) {
                    ForEach(EnforcementScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.radioGroup)

                Button(L10n.string("button.save_current_physical")) {
                    controller.captureCurrentPhysicalFormats(uid: device.uid)
                }
                .help(L10n.string("help.save_current_physical"))
            }

            ForEach(device.outputStreams) { stream in
                StreamSettingsSection(
                    controller: controller,
                    device: device,
                    stream: stream,
                    rule: rule
                )
            }

            if !controller.issues.isEmpty {
                Section(L10n.string("section.warnings")) {
                    ForEach(controller.issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Text(L10n.string("settings.format_explanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(device.name)
    }
}

private struct StreamSettingsSection: View {
    @ObservedObject var controller: AppController
    let device: AudioDeviceSnapshot
    let stream: AudioStreamSnapshot
    let rule: DeviceRule?

    var body: some View {
        Section(L10n.format(
            "settings.output_stream",
            stream.index + 1,
            stream.startingChannel
        )) {
            FormatDomainPicker(
                controller: controller,
                device: device,
                stream: stream,
                rule: rule,
                domain: .physical
            )
            FormatDomainPicker(
                controller: controller,
                device: device,
                stream: stream,
                rule: rule,
                domain: .virtual
            )
        }
    }
}

private struct FormatDomainPicker: View {
    @ObservedObject var controller: AppController
    let device: AudioDeviceSnapshot
    let stream: AudioStreamSnapshot
    let rule: DeviceRule?
    let domain: FormatDomain

    private var selectedChoice: FormatChoice? {
        rule?.target(streamIndex: stream.index, domain: domain)?.choice
    }

    private var availableOptions: [FormatChoice] {
        stream.options(for: domain)
    }

    private var savedChoiceIsUnavailable: Bool {
        guard let selectedChoice else { return false }
        return !availableOptions.contains(where: { $0.semanticallyMatches(selectedChoice) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.format("settings.current_format", domain.title))
                Spacer()
                Text(stream.current(for: domain)?.detailedDescription ?? L10n.string("settings.unavailable"))
                    .foregroundStyle(.secondary)
            }

            if stream.isSettable(domain), !availableOptions.isEmpty {
                Picker(L10n.format("settings.saved_format", domain.title), selection: Binding(
                    get: { selectedChoice },
                    set: { controller.setTarget($0, streamIndex: stream.index, domain: domain, uid: device.uid) }
                )) {
                    Text(L10n.string("settings.do_not_enforce")).tag(nil as FormatChoice?)
                    if savedChoiceIsUnavailable, let selectedChoice {
                        Text(L10n.format(
                            "settings.unavailable_saved",
                            selectedChoice.detailedDescription
                        ))
                            .tag(Optional(selectedChoice))
                    }
                    ForEach(availableOptions) { option in
                        Text(option.detailedDescription).tag(Optional(option))
                    }
                }
                .pickerStyle(.menu)
            } else {
                Label(
                    stream.isSettable(domain)
                        ? L10n.string("settings.no_selectable_formats")
                        : L10n.string("settings.read_only"),
                    systemImage: "lock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DisconnectedRuleView: View {
    @ObservedObject var controller: AppController
    let rule: DeviceRule

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(rule.lastKnownName)
                .font(.title2)
            Text(L10n.string("settings.disconnected_rule"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text(rule.uid)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Button(L10n.string("button.remove_rule"), role: .destructive) {
                controller.removeRule(uid: rule.uid)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
