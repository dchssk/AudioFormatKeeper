import AudioToolbox
import Foundation
import XCTest
@testable import AudioFormatKeeper

final class RuleStoreTests: XCTestCase {
    func testRoundTripPersistsRuleByDeviceUID() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = JSONRuleStore(fileURL: temporaryDirectory.appendingPathComponent("rules.json"))
        let format = AudioStreamBasicDescription(
            mSampleRate: 192_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let choice = FormatChoice(streamIndex: 0, domain: .physical, description: format)
        let expected = DeviceRule(
            uid: "example-device-uid",
            lastKnownName: "Example USB DAC",
            isEnabled: true,
            scope: .defaultOutput,
            targets: [StreamFormatTarget(streamIndex: 0, domain: .physical, choice: choice)]
        )

        try store.save([expected])
        let loaded = try store.load()

        XCTAssertEqual(loaded, [expected])
    }

    func testMissingFileLoadsAsEmptyRules() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("rules.json")
        let store = JSONRuleStore(fileURL: fileURL)

        XCTAssertEqual(try store.load(), [])
    }
}
