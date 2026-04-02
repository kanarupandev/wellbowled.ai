import XCTest
@testable import wellBowled

final class DeliveryTests: XCTestCase {

    private func makeDelivery(fps: Double = 120, release: Int? = nil, arrival: Int? = nil) -> Delivery {
        var d = Delivery(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            fps: fps, duration: 5.0, totalFrames: Int(5.0 * fps)
        )
        d.releaseFrame = release
        d.arrivalFrame = arrival
        return d
    }

    func test_speedKMH_nilWhenNoFrames() {
        let d = makeDelivery()
        XCTAssertNil(d.speedKMH)
    }

    func test_speedKMH_nilWhenOnlyRelease() {
        let d = makeDelivery(release: 10)
        XCTAssertNil(d.speedKMH)
    }

    func test_speedKMH_nilWhenOnlyArrival() {
        let d = makeDelivery(arrival: 70)
        XCTAssertNil(d.speedKMH)
    }

    func test_speedKMH_computesWhenBothSet() {
        let d = makeDelivery(release: 0, arrival: 60)
        XCTAssertNotNil(d.speedKMH)
        XCTAssertEqual(d.speedKMH!, 144.864, accuracy: 0.01)
    }

    func test_speedKMH_240fps() {
        let d = makeDelivery(fps: 240, release: 0, arrival: 120)
        XCTAssertEqual(d.speedKMH!, 144.864, accuracy: 0.01)
    }

    func test_speedMPH_converts() {
        let d = makeDelivery(release: 0, arrival: 60)
        XCTAssertNotNil(d.speedMPH)
        XCTAssertEqual(d.speedMPH!, 90.03, accuracy: 0.1)
    }

    func test_category_matchesSpeed() {
        let d = makeDelivery(release: 0, arrival: 60) // ~144.86 km/h = fast
        XCTAssertEqual(d.category, .fast)
    }

    func test_category_express() {
        let d = makeDelivery(release: 0, arrival: 50) // ~173.8 km/h
        XCTAssertEqual(d.category, .express)
    }

    func test_frameDiff_correct() {
        let d = makeDelivery(release: 10, arrival: 70)
        XCTAssertEqual(d.frameDiff, 60)
    }

    func test_frameDiff_nilWhenMissing() {
        let d = makeDelivery(release: 10)
        XCTAssertNil(d.frameDiff)
    }
}
