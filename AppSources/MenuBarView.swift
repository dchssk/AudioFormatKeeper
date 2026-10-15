import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: controller.isPaused ? "pause.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(controller.isPaused ? Color.secondary : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("app.name"))
                        .font(.headline)
                    Text(controller.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if let device = controller.defaultOutputDevice {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("menu.current_output"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Label(device.name, systemImage: "speaker.wave.2")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if let rate = device.nominalSampleRate {
                        Text(L10n.format(
                            "menu.current_rate",
                            FormatChoice.formatSampleRate(rate)
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.string("menu.system_default"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                FixedFormatSummary(
                    device: device,
                    rule: controller.rule(uid: device.uid)
                )
            } else {
                Text(L10n.string("menu.no_default"))
                    .foregroundStyle(.secondary)
            }

            if let issue = controller.issues.first {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button(controller.isPaused ? L10n.string("menu.resume") : L10n.string("menu.pause")) {
                    controller.isPaused.toggle()
                }
                Button(L10n.string("menu.check_now")) {
                    controller.enforceNow()
                }
                .disabled(controller.isPaused)
            }

            HStack {
                Button(L10n.string("menu.settings")) {
                    SettingsWindowOpener.open()
                }
                Spacer()
                Button(L10n.string("menu.quit")) {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 370)
    }
}

private struct FixedFormatSummary: View {
    let device: AudioDeviceSnapshot
    let rule: DeviceRule?

    private var targets: [StreamFormatTarget] {
        Array((rule?.targets ?? []).prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.string("menu.fixed_format"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if let rule, !rule.targets.isEmpty {
                if !rule.isEnabled {
                    Label(L10n.string("menu.rule_disabled"), systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                ForEach(targets) { target in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: targetIsSatisfied(target) ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath.circle")
                            .foregroundStyle(targetIsSatisfied(target) ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n.format(
                                "menu.target",
                                target.streamIndex + 1,
                                target.domain.title
                            ))
                            .font(.caption.weight(.semibold))
                            Text(target.choice.detailedDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if rule.targets.count > targets.count {
                    Text(L10n.format("menu.more_targets", rule.targets.count - targets.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(L10n.format("menu.scope", rule.scope.title))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.string("menu.no_fixed_for_device"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func targetIsSatisfied(_ target: StreamFormatTarget) -> Bool {
        guard let stream = device.outputStreams.first(where: { $0.index == target.streamIndex }),
              let current = stream.current(for: target.domain) else { return false }
        return current.semanticallyMatches(target.choice)
    }
}

enum SettingsWindowOpener {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        let shown = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        if !shown {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
