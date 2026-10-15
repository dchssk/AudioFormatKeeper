import AudioToolbox
import CoreAudio
import Foundation

enum FormatCandidateBuilder {
    static let standardSampleRates: [Double] = [
        8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000,
        44_100, 48_000, 64_000, 88_200, 96_000, 128_000, 176_400,
        192_000, 352_800, 384_000, 705_600, 768_000
    ]

    static func choices(
        streamIndex: Int,
        domain: FormatDomain,
        descriptions: [AudioStreamRangedDescription],
        nominalRanges: [SampleRateRange],
        currentSampleRate: Double?
    ) -> [FormatChoice] {
        var choicesByID: [String: FormatChoice] = [:]

        for rangedDescription in descriptions {
            let streamRange = SampleRateRange(rangedDescription.mSampleRateRange)
            let rates = candidateRates(
                streamRange: streamRange,
                formatSampleRate: rangedDescription.mFormat.mSampleRate,
                nominalRanges: nominalRanges,
                currentSampleRate: currentSampleRate
            )

            for rate in rates {
                var format = rangedDescription.mFormat
                format.mSampleRate = rate
                let choice = FormatChoice(streamIndex: streamIndex, domain: domain, description: format)
                choicesByID[choice.id] = choice
            }
        }

        return choicesByID.values.sorted(by: sortChoices)
    }

    static func candidateRates(
        streamRange: SampleRateRange,
        formatSampleRate: Double,
        nominalRanges: [SampleRateRange],
        currentSampleRate: Double?
    ) -> [Double] {
        let effectiveNominalRanges = nominalRanges.isEmpty ? [streamRange] : nominalRanges
        var rates = Set<Double>()

        func addIfAdvertised(_ rate: Double) {
            guard rate > 0, streamRange.contains(rate) else { return }
            guard effectiveNominalRanges.contains(where: { $0.contains(rate) }) else { return }
            rates.insert(rate)
        }

        addIfAdvertised(formatSampleRate)
        if let currentSampleRate { addIfAdvertised(currentSampleRate) }
        standardSampleRates.forEach(addIfAdvertised)

        for range in effectiveNominalRanges {
            let lower = max(streamRange.minimum, range.minimum)
            let upper = min(streamRange.maximum, range.maximum)
            guard lower <= upper else { continue }
            addIfAdvertised(lower)
            addIfAdvertised(upper)
        }

        return rates.sorted()
    }

    private static func sortChoices(_ lhs: FormatChoice, _ rhs: FormatChoice) -> Bool {
        if lhs.sampleRate != rhs.sampleRate { return lhs.sampleRate < rhs.sampleRate }
        if lhs.channelsPerFrame != rhs.channelsPerFrame { return lhs.channelsPerFrame < rhs.channelsPerFrame }
        if lhs.bitsPerChannel != rhs.bitsPerChannel { return lhs.bitsPerChannel < rhs.bitsPerChannel }
        if lhs.formatID != rhs.formatID { return lhs.formatID < rhs.formatID }
        return lhs.formatFlags < rhs.formatFlags
    }
}
