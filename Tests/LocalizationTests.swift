import Foundation
import XCTest
@testable import AudioFormatKeeper

final class LocalizationTests: XCTestCase {
    func testJapaneseTranslationIsAvailable() {
        XCTAssertEqual(L10n.string("menu.current_output", language: "ja"), "現在の出力デバイス")
        XCTAssertEqual(L10n.string("menu.fixed_format", language: "ja"), "固定内容")
        XCTAssertEqual(
            L10n.format("menu.target", language: "ja", 1, "物理"),
            "出力1・物理"
        )
        XCTAssertEqual(
            L10n.format("format.linear_pcm", language: "ja", UInt32(2), UInt32(32), "符号付き整数", "192 kHz"),
            "2 ch・32ビット符号付き整数・192 kHz"
        )
    }

    func testEnglishAndJapaneseContainTheSameKeys() throws {
        let english = try localizationDictionary(language: "en")
        let japanese = try localizationDictionary(language: "ja")

        XCTAssertEqual(Set(english.keys), Set(japanese.keys))
        XCTAssertGreaterThan(english.count, 50)
    }

    private func localizationDictionary(language: String) throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: language
            )
        )
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(propertyList as? [String: String])
    }
}
