import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError, Equatable {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        L10n.format("error.operation_failed", operation, statusDescription)
    }

    private var statusDescription: String {
        let raw = UInt32(bitPattern: status)
        let code = fourCC(raw)
        return code.hasPrefix("0x") ? "OSStatus \(status)" : "'\(code)' / \(status)"
    }
}
