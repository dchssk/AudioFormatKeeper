import AudioToolbox
import CoreAudio
import XCTest
@testable import AudioFormatKeeper

final class FormatCandidateBuilderTests: XCTestCase {
    func testCandidatesStayInsideBothStreamAndNominalRanges() {
        let description = rangedDescription(minimum: 44_100, maximum: 192_000)
        let nominal = [SampleRateRange(AudioValueRange(mMinimum: 48_000, mMaximum: 96_000))]

        let choices = FormatCandidateBuilder.choices(
            streamIndex: 0,
            domain: .physical,
            descriptions: [description],
            nominalRanges: nominal,
            currentSampleRate: 88_200
        )

        XCTAssertEqual(choices.map(\.sampleRate), [48_000, 64_000, 88_200, 96_000])
        XCTAssertTrue(choices.allSatisfy { $0.channelsPerFrame == 2 && $0.bitsPerChannel == 32 })
    }

    func testExactAdvertisedRateIsPreservedAndDuplicatesAreRemoved() {
        let description = rangedDescription(minimum: 192_000, maximum: 192_000)
        let nominal = [SampleRateRange(AudioValueRange(mMinimum: 192_000, mMaximum: 192_000))]

        let choices = FormatCandidateBuilder.choices(
            streamIndex: 2,
            domain: .virtual,
            descriptions: [description, description],
            nominalRanges: nominal,
            currentSampleRate: 192_000
        )

        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(choices[0].sampleRate, 192_000)
        XCTAssertEqual(choices[0].streamIndex, 2)
        XCTAssertEqual(choices[0].domain, .virtual)
    }

    func testSemanticMatchRejectsDifferentRepresentation() {
        let signed = FormatChoice(
            streamIndex: 0,
            domain: .physical,
            description: pcmDescription(sampleRate: 192_000, flags: kAudioFormatFlagIsSignedInteger)
        )
        let floating = FormatChoice(
            streamIndex: 0,
            domain: .physical,
            description: pcmDescription(sampleRate: 192_000, flags: kAudioFormatFlagIsFloat)
        )

        XCTAssertFalse(signed.semanticallyMatches(floating))
    }

    private func rangedDescription(minimum: Double, maximum: Double) -> AudioStreamRangedDescription {
        AudioStreamRangedDescription(
            mFormat: pcmDescription(sampleRate: minimum, flags: kAudioFormatFlagIsSignedInteger),
            mSampleRateRange: AudioValueRange(mMinimum: minimum, mMaximum: maximum)
        )
    }

    private func pcmDescription(sampleRate: Double, flags: UInt32) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: flags | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }
}
