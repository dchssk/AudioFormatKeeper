import Combine
import Foundation

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var devices: [AudioDeviceSnapshot] = []
    @Published private(set) var rules: [DeviceRule] = []
    @Published private(set) var statusMessage = L10n.string("status.starting")
    @Published private(set) var issues: [String] = []
    @Published var isPaused: Bool {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: Self.pauseDefaultsKey)
            if !isPaused { refreshAndEnforce(reason: "Enforcement resumed") }
        }
    }

    private static let pauseDefaultsKey = "enforcementPaused"
    private let audioClient: CoreAudioClient
    private let monitor: CoreAudioMonitor
    private let ruleStore: JSONRuleStore
    private var refreshTask: Task<Void, Never>?

    init(
        audioClient: CoreAudioClient = CoreAudioClient(),
        monitor: CoreAudioMonitor = CoreAudioMonitor(),
        ruleStore: JSONRuleStore = JSONRuleStore()
    ) {
        self.audioClient = audioClient
        self.monitor = monitor
        self.ruleStore = ruleStore
        isPaused = UserDefaults.standard.bool(forKey: Self.pauseDefaultsKey)

        do {
            rules = try ruleStore.load().sorted { $0.lastKnownName < $1.lastKnownName }
        } catch {
            statusMessage = L10n.string("status.load_failed")
            issues = [error.localizedDescription]
        }
        refreshAndEnforce(reason: "Started")
    }

    deinit {
        refreshTask?.cancel()
        monitor.stop()
    }

    var defaultOutputDevice: AudioDeviceSnapshot? {
        devices.first(where: \.isDefaultOutput)
    }

    var enabledRuleCount: Int {
        rules.filter { $0.isEnabled && !$0.targets.isEmpty }.count
    }

    func device(uid: String) -> AudioDeviceSnapshot? {
        devices.first { $0.uid == uid }
    }

    func rule(uid: String) -> DeviceRule? {
        rules.first { $0.uid == uid }
    }

    func setEnabled(_ enabled: Bool, uid: String) {
        mutateRule(uid: uid) { $0.isEnabled = enabled }
    }

    func setScope(_ scope: EnforcementScope, uid: String) {
        mutateRule(uid: uid) { $0.scope = scope }
    }

    func setTarget(_ choice: FormatChoice?, streamIndex: Int, domain: FormatDomain, uid: String) {
        mutateRule(uid: uid) { rule in
            rule.targets.removeAll { $0.streamIndex == streamIndex && $0.domain == domain }
            if let choice {
                rule.targets.append(StreamFormatTarget(
                    streamIndex: streamIndex,
                    domain: domain,
                    choice: choice
                ))
                rule.isEnabled = true
            }
            rule.targets.sort {
                if $0.streamIndex != $1.streamIndex { return $0.streamIndex < $1.streamIndex }
                return $0.domain.rawValue < $1.domain.rawValue
            }
        }
    }

    func captureCurrentPhysicalFormats(uid: String) {
        guard let device = device(uid: uid) else { return }
        mutateRule(uid: uid) { rule in
            rule.targets.removeAll { $0.domain == .physical }
            for stream in device.outputStreams where stream.physicalIsSettable {
                guard let current = stream.currentPhysical,
                      let advertised = stream.physicalOptions.first(where: {
                          $0.semanticallyMatches(current)
                      }) else { continue }
                rule.targets.append(StreamFormatTarget(
                    streamIndex: stream.index,
                    domain: .physical,
                    choice: advertised
                ))
            }
            rule.isEnabled = !rule.targets.isEmpty
        }
    }

    func removeRule(uid: String) {
        rules.removeAll { $0.uid == uid }
        persistAndRefresh(reason: "Rule removed")
    }

    func enforceNow() {
        refreshAndEnforce(reason: "Manual check")
    }

    func scheduleRefresh(reason: String) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            self?.refreshAndEnforce(reason: reason)
        }
    }

    private func mutateRule(uid: String, mutation: (inout DeviceRule) -> Void) {
        let connectedDevice = device(uid: uid)
        if let index = rules.firstIndex(where: { $0.uid == uid }) {
            mutation(&rules[index])
            if let connectedDevice { rules[index].lastKnownName = connectedDevice.name }
        } else {
            var newRule = DeviceRule(
                uid: uid,
                lastKnownName: connectedDevice?.name ?? uid,
                isEnabled: false,
                scope: .defaultOutput,
                targets: []
            )
            mutation(&newRule)
            rules.append(newRule)
        }
        rules.sort { $0.lastKnownName.localizedStandardCompare($1.lastKnownName) == .orderedAscending }
        persistAndRefresh(reason: "Rule updated")
    }

    private func persistAndRefresh(reason: String) {
        do {
            try ruleStore.save(rules)
            refreshAndEnforce(reason: reason)
        } catch {
            statusMessage = L10n.string("status.save_failed")
            issues = [error.localizedDescription]
        }
    }

    private func refreshAndEnforce(reason: String) {
        do {
            let currentDevices = try audioClient.outputDevices()
            devices = currentDevices
            monitor.rebind(devices: currentDevices) { [weak self] in
                Task { @MainActor in
                    self?.scheduleRefresh(reason: "CoreAudio changed")
                }
            }

            guard !isPaused else {
                statusMessage = L10n.format("status.paused", currentDevices.count)
                issues = []
                return
            }

            var aggregate = ApplyResult()
            for rule in rules where rule.isEnabled && !rule.targets.isEmpty {
                guard let device = currentDevices.first(where: { $0.uid == rule.uid }) else { continue }
                guard rule.scope == .wheneverConnected || device.isDefaultOutput else { continue }
                let result = audioClient.apply(rule: rule, to: device)
                aggregate.changesAttempted += result.changesAttempted
                aggregate.issues.append(contentsOf: result.issues)
            }

            issues = aggregate.issues
            if aggregate.changesAttempted > 0 {
                statusMessage = L10n.format("status.restored", aggregate.changesAttempted)
            } else if aggregate.issues.isEmpty {
                statusMessage = L10n.string("status.watching")
            } else {
                statusMessage = L10n.format("status.watching_warnings", aggregate.issues.count)
            }
        } catch {
            statusMessage = L10n.string("status.refresh_failed")
            issues = [error.localizedDescription]
        }
    }
}
