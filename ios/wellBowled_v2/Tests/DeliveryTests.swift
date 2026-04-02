import XCTest
@testable import wellBowled

final class DeliveryTests: XCTestCase {

    private func makeDelivery(fps: Double = 120, release: Int? = nil, arrival: Int? = nil, distance: Double? = nil) -> Delivery {
        var d = Delivery(
            videoURL: URL(fileURLWithPath: "/tmp/test.mov"),
            fps: fps, duration: 5.0, totalFrames: Int(5.0 * fps)
        )
        d.releaseFrame = release
        d.arrivalFrame = arrival
        if let distance { d.distanceMeters = distance }
        return d
    }

    func test_defaultDistance_matchesTrainingDefault() {
        let d = makeDelivery()
        XCTAssertEqual(d.distanceMeters, 18.90)
    }

    func test_speedKMH_nilWhenNoFrames() {
        XCTAssertNil(makeDelivery().speedKMH)
    }

    func test_speedKMH_nilWhenOnlyRelease() {
        XCTAssertNil(makeDelivery(release: 10).speedKMH)
    }

    func test_speedKMH_nilWhenOnlyArrival() {
        XCTAssertNil(makeDelivery(arrival: 70).speedKMH)
    }

    func test_speedKMH_computesWithDefaultDistance() {
        // 60f at 120fps = 0.5s, 18.90m / 0.5s * 3.6 = 136.08
        let d = makeDelivery(release: 0, arrival: 60)
        XCTAssertEqual(d.speedKMH!, 136.08, accuracy: 0.01)
    }

    func test_speedKMH_customDistance() {
        let d = makeDelivery(release: 0, arrival: 60, distance: 20.12)
        XCTAssertEqual(d.speedKMH!, 144.864, accuracy: 0.01)
    }

    func test_speedKMH_240fps() {
        let d = makeDelivery(fps: 240, release: 0, arrival: 120)
        XCTAssertEqual(d.speedKMH!, 136.08, accuracy: 0.01)
    }

    func test_speedMPH_converts() {
        let d = makeDelivery(release: 0, arrival: 60)
        XCTAssertNotNil(d.speedMPH)
        XCTAssertEqual(d.speedMPH!, 84.57, accuracy: 0.1)
    }

    func test_category_matchesSpeed() {
        let d = makeDelivery(release: 0, arrival: 60) // ~136 km/h = fast
        XCTAssertEqual(d.category, .fast)
    }

    func test_category_express() {
        let d = makeDelivery(release: 0, arrival: 40) // ~190 km/h
        XCTAssertEqual(d.category, .express)
    }

    func test_frameDiff_correct() {
        XCTAssertEqual(makeDelivery(release: 10, arrival: 70).frameDiff, 60)
    }

    func test_frameDiff_nilWhenMissing() {
        XCTAssertNil(makeDelivery(release: 10).frameDiff)
    }

    func test_frameMarkers_setReleaseClearsStaleArrival() {
        var markers = FrameMarkers(releaseFrame: 10, arrivalFrame: 25)
        markers.setRelease(30)
        XCTAssertEqual(markers.releaseFrame, 30)
        XCTAssertNil(markers.arrivalFrame)
    }

    func test_frameMarkers_setArrivalRequiresRelease() {
        var markers = FrameMarkers()
        XCTAssertFalse(markers.setArrival(50))
        XCTAssertNil(markers.arrivalFrame)
    }

    func test_frameMarkers_setArrivalRequiresLaterFrame() {
        var markers = FrameMarkers(releaseFrame: 40, arrivalFrame: nil)
        XCTAssertFalse(markers.setArrival(40))
        XCTAssertFalse(markers.setArrival(39))
        XCTAssertNil(markers.arrivalFrame)
    }

    func test_frameMarkers_clearReleaseClearsArrival() {
        var markers = FrameMarkers(releaseFrame: 20, arrivalFrame: 60)
        markers.clearRelease()
        XCTAssertNil(markers.releaseFrame)
        XCTAssertNil(markers.arrivalFrame)
    }

    func test_frameMarkers_clearArrivalPreservesRelease() {
        var markers = FrameMarkers(releaseFrame: 20, arrivalFrame: 60)
        markers.clearArrival()
        XCTAssertEqual(markers.releaseFrame, 20)
        XCTAssertNil(markers.arrivalFrame)
    }
}
