import CoreGraphics
import XCTest
@testable import wellBowled

final class SpeedEstimationServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Allocate a contiguous UInt8 buffer and return both the Data backing and a typed pointer.
    /// The caller must keep `Data` alive for the pointer to remain valid.
    private func makeBuffer(width: Int, height: Int, fill: UInt8 = 0) -> (Data, UnsafeBufferPointer<UInt8>) {
        var data = Data(repeating: fill, count: width * height)
        let pointer = data.withUnsafeBytes { raw in
            raw.bindMemory(to: UInt8.self)
        }
        return (data, UnsafeBufferPointer(start: pointer.baseAddress, count: pointer.count))
    }

    /// Paint a rectangular region of a buffer with a given value.
    private func paint(
        data: inout Data,
        width: Int,
        rect: CGRect,
        value: UInt8
    ) {
        let minX = max(Int(rect.minX), 0)
        let maxX = min(Int(rect.maxX), width)
        let minY = max(Int(rect.minY), 0)
        let maxY = min(Int(rect.maxY), data.count / width)
        for y in minY..<maxY {
            for x in minX..<maxX {
                data[y * width + x] = value
            }
        }
    }

    /// Create a typed pointer from a Data instance. Caller keeps Data alive.
    private func pointer(from data: Data) -> UnsafeBufferPointer<UInt8> {
        data.withUnsafeBytes { raw in
            let typed = raw.bindMemory(to: UInt8.self)
            return UnsafeBufferPointer(start: typed.baseAddress, count: typed.count)
        }
    }

    private func makeCalibration(
        bowlerCenter: CGPoint = CGPoint(x: 0.5, y: 0.15),
        strikerCenter: CGPoint = CGPoint(x: 0.5, y: 0.85),
        frameWidth: Int = 1920,
        frameHeight: Int = 1080,
        fps: Int = 120
    ) -> StumpCalibration {
        StumpCalibration(
            bowlerStumpCenter: bowlerCenter,
            strikerStumpCenter: strikerCenter,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            recordingFPS: fps,
            calibratedAt: Date(),
            isManualPlacement: false
        )
    }

    // MARK: - computeMotionEnergy

    func testComputeMotionEnergyDetectsChange() {
        let width = 100
        let height = 100
        let roi = CGRect(x: 20, y: 20, width: 60, height: 60)

        // Previous frame: all zeros
        let prevData = Data(repeating: 0, count: width * height)
        let prevPtr = pointer(from: prevData)

        // Current frame: bright patch (value 200) inside the ROI
        var currData = Data(repeating: 0, count: width * height)
        paint(data: &currData, width: width, rect: CGRect(x: 30, y: 30, width: 40, height: 40), value: 200)
        let currPtr = pointer(from: currData)

        let energy = SpeedEstimationService.computeMotionEnergy(
            prev: prevPtr, curr: currPtr,
            width: width, height: height,
            roi: roi,
            threshold: 30.0
        )

        // 40x40 = 1600 pixels above threshold, out of 60x60 = 3600 ROI pixels
        let expectedEnergy = 1600.0 / 3600.0
        XCTAssertGreaterThan(energy, 0.0, "Energy should be positive when motion is present in ROI")
        XCTAssertEqual(energy, expectedEnergy, accuracy: 0.01)
    }

    func testComputeMotionEnergyIgnoresOutsideROI() {
        let width = 100
        let height = 100
        // ROI is top-left corner
        let roi = CGRect(x: 0, y: 0, width: 20, height: 20)

        // Previous frame: all zeros
        let prevData = Data(repeating: 0, count: width * height)
        let prevPtr = pointer(from: prevData)

        // Current frame: bright patch OUTSIDE the ROI (bottom-right corner)
        var currData = Data(repeating: 0, count: width * height)
        paint(data: &currData, width: width, rect: CGRect(x: 70, y: 70, width: 30, height: 30), value: 200)
        let currPtr = pointer(from: currData)

        let energy = SpeedEstimationService.computeMotionEnergy(
            prev: prevPtr, curr: currPtr,
            width: width, height: height,
            roi: roi,
            threshold: 30.0
        )

        XCTAssertEqual(energy, 0.0, accuracy: 1e-9, "Energy should be zero when motion is outside ROI")
    }

    func testComputeMotionEnergyAllSameReturnsZero() {
        let width = 100
        let height = 100
        let roi = CGRect(x: 0, y: 0, width: 100, height: 100)

        let frameData = Data(repeating: 128, count: width * height)
        let framePtr = pointer(from: frameData)

        let energy = SpeedEstimationService.computeMotionEnergy(
            prev: framePtr, curr: framePtr,
            width: width, height: height,
            roi: roi,
            threshold: 30.0
        )

        XCTAssertEqual(energy, 0.0, accuracy: 1e-9, "Energy should be zero for identical frames")
    }

    // MARK: - findMotionSpike

    func testFindMotionSpikeDetectsSpike() {
        // Low baseline energies with a clear spike at index 5
        let energies = [0.01, 0.02, 0.01, 0.015, 0.02, 0.25, 0.01, 0.02]
        let noise = SpeedEstimationService.noiseFloor(from: energies)

        let spikeIndex = SpeedEstimationService.findMotionSpike(
            energies: energies,
            noiseFloor: noise,
            spikeMultiplier: 3.0
        )

        XCTAssertNotNil(spikeIndex)
        XCTAssertEqual(spikeIndex, 5, "Spike should be detected at index 5")
    }

    func testFindMotionSpikeReturnsNilWhenNoSpike() {
        let energies = [0.01, 0.02, 0.015, 0.018, 0.02, 0.022, 0.019]
        let noise = SpeedEstimationService.noiseFloor(from: energies)

        let spikeIndex = SpeedEstimationService.findMotionSpike(
            energies: energies,
            noiseFloor: noise,
            spikeMultiplier: 3.0
        )

        XCTAssertNil(spikeIndex, "No spike should be found in uniformly low energy values")
    }

    // MARK: - noiseFloor

    func testNoiseFloorComputesMedian() {
        // Odd count: [1, 2, 3, 4, 5] → median = 3
        let oddValues = [5.0, 1.0, 3.0, 4.0, 2.0]
        XCTAssertEqual(SpeedEstimationService.noiseFloor(from: oddValues), 3.0, accuracy: 1e-9)

        // Even count: [1, 2, 3, 4] → median = (2+3)/2 = 2.5
        let evenValues = [4.0, 1.0, 3.0, 2.0]
        XCTAssertEqual(SpeedEstimationService.noiseFloor(from: evenValues), 2.5, accuracy: 1e-9)

        // Single value
        XCTAssertEqual(SpeedEstimationService.noiseFloor(from: [42.0]), 42.0, accuracy: 1e-9)
    }

    func testNoiseFloorHandlesEmptyArray() {
        XCTAssertEqual(SpeedEstimationService.noiseFloor(from: []), 0.0, accuracy: 1e-9)
    }

    // MARK: - Speed Formula Consistency

    func testSpeedFormulaConsistency() {
        let cal = makeCalibration()

        // Target: 130 kph → m/s = 130 / 3.6 ≈ 36.111
        // Transit time = pitchLength / speed_m_s = 20.12 / 36.111 ≈ 0.557s
        let targetKph = 130.0
        let speedMS = targetKph / 3.6
        let transitTime = StumpCalibration.pitchLengthMetres / speedMS

        let computedKph = cal.speedKph(transitTimeSeconds: transitTime)
        XCTAssertNotNil(computedKph)
        XCTAssertEqual(computedKph!, targetKph, accuracy: 0.1,
                       "speedKph should return ~130 kph for the computed transit time")
    }

    // MARK: - Edge Cases

    func testComputeMotionEnergyWithEmptyROI() {
        let width = 100
        let height = 100
        let roi = CGRect(x: 50, y: 50, width: 0, height: 0)

        let data = Data(repeating: 0, count: width * height)
        let ptr = pointer(from: data)

        let energy = SpeedEstimationService.computeMotionEnergy(
            prev: ptr, curr: ptr,
            width: width, height: height,
            roi: roi,
            threshold: 30.0
        )

        XCTAssertEqual(energy, 0.0, accuracy: 1e-9, "Empty ROI should yield zero energy")
    }

    func testPixelRectConversion() {
        let normalised = CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)
        let pixel = SpeedEstimationService.pixelRect(from: normalised, frameWidth: 1920, frameHeight: 1080)

        XCTAssertEqual(pixel.origin.x, 480.0, accuracy: 0.1)
        XCTAssertEqual(pixel.origin.y, 108.0, accuracy: 0.1)
        XCTAssertEqual(pixel.width, 960.0, accuracy: 0.1)
        XCTAssertEqual(pixel.height, 864.0, accuracy: 0.1)
    }
}
