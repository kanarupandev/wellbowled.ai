import XCTest
@testable import wellBowled

final class TTSSpeedAnnouncementTests: XCTestCase {

    // MARK: - Speed Text Formatting

    func testSpeedTextFormatBelow100() {
        // Below 100: just the number → "96" spoken as "ninety-six"
        XCTAssertEqual(TTSService.speedText(for: 96.2), "96")
        XCTAssertEqual(TTSService.speedText(for: 85.7), "86")
        XCTAssertEqual(TTSService.speedText(for: 79.4), "79")
    }

    func testSpeedTextFormatAbove100WithZeroTens() {
        // 103 → "1 oh 3" → spoken as "one-oh-three"
        XCTAssertEqual(TTSService.speedText(for: 103.2), "1 oh 3")
        XCTAssertEqual(TTSService.speedText(for: 107.8), "1 oh 8")
        XCTAssertEqual(TTSService.speedText(for: 100.4), "1 oh 0")
    }

    func testSpeedTextFormatAbove100WithNonZeroTens() {
        // 112 → "1 12" → spoken as "one twelve"
        XCTAssertEqual(TTSService.speedText(for: 112.3), "1 12")
        XCTAssertEqual(TTSService.speedText(for: 135.6), "1 36")
        XCTAssertEqual(TTSService.speedText(for: 150.1), "1 50")
    }

    func testSpeedTextRoundsCorrectly() {
        // 99.5 rounds to 100 → "1 oh 0"
        XCTAssertEqual(TTSService.speedText(for: 99.5), "1 oh 0")
    }

    func testSpeedTextEdgeCaseAt100() {
        XCTAssertEqual(TTSService.speedText(for: 100.0), "1 oh 0")
    }

    func testSpeedTextAt99Point4() {
        // 99.4 rounds to 99 → below 100 → "99"
        XCTAssertEqual(TTSService.speedText(for: 99.4), "99")
    }
}
