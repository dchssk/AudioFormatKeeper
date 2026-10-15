import Foundation

final class JSONRuleStore {
    let fileURL: URL

    init(fileURL: URL = JSONRuleStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() throws -> [DeviceRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(RuleDocument.self, from: data).rules
    }

    func save(_ rules: [DeviceRule]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(RuleDocument(rules: rules))
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("AudioFormatKeeper", isDirectory: true)
            .appendingPathComponent("rules.json", isDirectory: false)
    }
}
