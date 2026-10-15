import AudioToolbox
import CoreAudio
import Foundation

enum FormatDomain: String, Codable, CaseIterable, Hashable {
    case physical
    case virtual

    var title: String {
        switch self {
        case .physical: return L10n.string("format.physical")
        case .virtual: return L10n.string("format.virtual")
        }
    }
}

enum EnforcementScope: String, Codable, CaseIterable, Hashable {
    case defaultOutput
    case wheneverConnected

    var title: String {
        switch self {
        case .defaultOutput: return L10n.string("scope.default_output")
        case .wheneverConnected: return L10n.string("scope.whenever_connected")
        }
    }
}

struct FormatChoice: Codable, Hashable, Identifiable {
    let streamIndex: Int
    let domain: FormatDomain
    let sampleRate: Double
    let formatID: UInt32
    let formatFlags: UInt32
    let bytesPerPacket: UInt32
    let framesPerPacket: UInt32
    let bytesPerFrame: UInt32
    let channelsPerFrame: UInt32
    let bitsPerChannel: UInt32

    init(streamIndex: Int, domain: FormatDomain, description: AudioStreamBasicDescription) {
        self.streamIndex = streamIndex
        self.domain = domain
        sampleRate = description.mSampleRate
        formatID = description.mFormatID
        formatFlags = description.mFormatFlags
        bytesPerPacket = description.mBytesPerPacket
        framesPerPacket = description.mFramesPerPacket
        bytesPerFrame = description.mBytesPerFrame
        channelsPerFrame = description.mChannelsPerFrame
        bitsPerChannel = description.mBitsPerChannel
    }

    var id: String {
        [
            String(streamIndex), domain.rawValue, String(formatID), String(formatFlags),
            String(bytesPerPacket), String(framesPerPacket), String(bytesPerFrame),
            String(channelsPerFrame), String(bitsPerChannel), String(sampleRate.bitPattern)
        ].joined(separator: ":")
    }

    var isLinearPCM: Bool { formatID == kAudioFormatLinearPCM }

    var numericType: String {
        guard isLinearPCM else { return fourCC(formatID) }
        if formatFlags & kAudioFormatFlagIsFloat != 0 { return L10n.string("format.float") }
        if formatFlags & kAudioFormatFlagIsSignedInteger != 0 { return L10n.string("format.signed_integer") }
        return L10n.string("format.integer")
    }

    var interleaving: String {
        formatFlags & kAudioFormatFlagIsNonInterleaved != 0
            ? L10n.string("format.non_interleaved")
            : L10n.string("format.interleaved")
    }

    var shortDescription: String {
        let rate = Self.formatSampleRate(sampleRate)
        if isLinearPCM {
            return L10n.format(
                "format.linear_pcm",
                channelsPerFrame,
                bitsPerChannel,
                numericType,
                rate
            )
        }
        return L10n.format("format.other", channelsPerFrame, fourCC(formatID), rate)
    }

    var detailedDescription: String {
        isLinearPCM ? "\(shortDescription) · \(interleaving)" : shortDescription
    }

    var compactDescription: String {
        let rate = Self.formatSampleRate(sampleRate)
        if isLinearPCM {
            let compactType = formatFlags & kAudioFormatFlagIsFloat != 0
                ? L10n.string("format.compact_float")
                : L10n.string("format.compact_integer")
            return L10n.format(
                "format.compact_linear_pcm",
                channelsPerFrame,
                bitsPerChannel,
                compactType,
                rate
            )
        }
        return L10n.format("format.compact_other", channelsPerFrame, fourCC(formatID), rate)
    }

    func semanticallyMatches(_ other: FormatChoice) -> Bool {
        streamIndex == other.streamIndex
            && domain == other.domain
            && abs(sampleRate - other.sampleRate) < 0.5
            && formatID == other.formatID
            && formatFlags == other.formatFlags
            && bytesPerPacket == other.bytesPerPacket
            && framesPerPacket == other.framesPerPacket
            && bytesPerFrame == other.bytesPerFrame
            && channelsPerFrame == other.channelsPerFrame
            && bitsPerChannel == other.bitsPerChannel
    }

    func makeASBD() -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: formatID,
            mFormatFlags: formatFlags,
            mBytesPerPacket: bytesPerPacket,
            mFramesPerPacket: framesPerPacket,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channelsPerFrame,
            mBitsPerChannel: bitsPerChannel,
            mReserved: 0
        )
    }

    static func formatSampleRate(_ value: Double) -> String {
        if value >= 1_000 {
            let kHz = value / 1_000
            return kHz.rounded() == kHz
                ? String(format: "%.0f kHz", kHz)
                : String(format: "%.1f kHz", kHz)
        }
        return String(format: "%.0f Hz", value)
    }
}

struct SampleRateRange: Hashable {
    let minimum: Double
    let maximum: Double

    init(_ range: AudioValueRange) {
        minimum = min(range.mMinimum, range.mMaximum)
        maximum = max(range.mMinimum, range.mMaximum)
    }

    func contains(_ value: Double) -> Bool {
        value >= minimum - 0.5 && value <= maximum + 0.5
    }
}

struct AudioStreamSnapshot: Identifiable, Hashable {
    let id: AudioStreamID
    let index: Int
    let startingChannel: UInt32
    let physicalOptions: [FormatChoice]
    let virtualOptions: [FormatChoice]
    let currentPhysical: FormatChoice?
    let currentVirtual: FormatChoice?
    let physicalIsSettable: Bool
    let virtualIsSettable: Bool

    func options(for domain: FormatDomain) -> [FormatChoice] {
        domain == .physical ? physicalOptions : virtualOptions
    }

    func current(for domain: FormatDomain) -> FormatChoice? {
        domain == .physical ? currentPhysical : currentVirtual
    }

    func isSettable(_ domain: FormatDomain) -> Bool {
        domain == .physical ? physicalIsSettable : virtualIsSettable
    }
}

struct AudioDeviceSnapshot: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let manufacturer: String
    let transport: String
    let isDefaultOutput: Bool
    let nominalSampleRate: Double?
    let availableNominalSampleRates: [SampleRateRange]
    let nominalSampleRateIsSettable: Bool
    let outputStreams: [AudioStreamSnapshot]
}

struct StreamFormatTarget: Codable, Hashable, Identifiable {
    let streamIndex: Int
    let domain: FormatDomain
    var choice: FormatChoice

    var id: String { "\(streamIndex):\(domain.rawValue)" }
}

struct DeviceRule: Codable, Hashable, Identifiable {
    let uid: String
    var lastKnownName: String
    var isEnabled: Bool
    var scope: EnforcementScope
    var targets: [StreamFormatTarget]

    var id: String { uid }

    func target(streamIndex: Int, domain: FormatDomain) -> StreamFormatTarget? {
        targets.first { $0.streamIndex == streamIndex && $0.domain == domain }
    }
}

struct RuleDocument: Codable, Equatable {
    var version = 1
    var rules: [DeviceRule]
}

struct ApplyResult: Equatable {
    var changesAttempted = 0
    var issues: [String] = []
}

func fourCC(_ value: UInt32) -> String {
    let bytes = [
        UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
    ]
    if bytes.allSatisfy({ (32...126).contains($0) }) {
        return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", value)
    }
    return String(format: "0x%08X", value)
}
