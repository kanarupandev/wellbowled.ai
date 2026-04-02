import XCTest
@testable import wellBowled

final class SpeedCategoryTests: XCTestCase {

    func test_express_145() {
        XCTAssertEqual(SpeedCategory.from(kmh: 145.0), .express)
    }

    func test_express_160() {
        XCTAssertEqual(SpeedCategory.from(kmh: 160.0), .express)
    }

    func test_fast_135() {
        XCTAssertEqual(SpeedCategory.from(kmh: 135.0), .fast)
    }

    func test_fast_144_9() {
        XCTAssertEqual(SpeedCategory.from(kmh: 144.9), .fast)
    }

    func test_fastMedium_125() {
        XCTAssertEqual(SpeedCategory.from(kmh: 125.0), .fastMedium)
    }

    func test_fastMedium_134_9() {
        XCTAssertEqual(SpeedCategory.from(kmh: 134.9), .fastMedium)
    }

    func test_medium_115() {
        XCTAssertEqual(SpeedCategory.from(kmh: 115.0), .medium)
    }

    func test_mediumSlow_100() {
        XCTAssertEqual(SpeedCategory.from(kmh: 100.0), .mediumSlow)
    }

    func test_slow_99() {
        XCTAssertEqual(SpeedCategory.from(kmh: 99.9), .slow)
    }

    func test_slow_zero() {
        XCTAssertEqual(SpeedCategory.from(kmh: 0.0), .slow)
    }

    func test_slow_negative() {
        XCTAssertEqual(SpeedCategory.from(kmh: -10.0), .slow)
    }
}
