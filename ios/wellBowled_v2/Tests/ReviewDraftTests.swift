import XCTest
@testable import wellBowled

final class ReviewDraftTests: XCTestCase {

    func test_initialDraft_defaultsToReleaseSelection() {
        let draft = ReviewDraft()
        XCTAssertEqual(draft.activeField, .release)
        XCTAssertNil(draft.releaseFrame)
        XCTAssertNil(draft.arrivalFrame)
        XCTAssertFalse(draft.isComplete)
    }

    func test_selectingArrivalBeforeReleaseFallsBackToRelease() {
        var draft = ReviewDraft()
        draft.select(.arrival)
        XCTAssertEqual(draft.activeField, .release)
    }

    func test_settingReleaseAdvancesToArrivalOnFirstPass() {
        var draft = ReviewDraft()
        let invalidated = draft.setRelease(42)
        XCTAssertFalse(invalidated)
        XCTAssertEqual(draft.releaseFrame, 42)
        XCTAssertEqual(draft.activeField, .arrival)
    }

    func test_releaseCanBeAdjustedBeforeArrivalExists() {
        var draft = ReviewDraft()
        _ = draft.setRelease(42)
        draft.select(.release)
        _ = draft.setRelease(40)
        XCTAssertEqual(draft.releaseFrame, 40)
        XCTAssertNil(draft.arrivalFrame)
        XCTAssertEqual(draft.activeField, .arrival)
    }

    func test_arrivalCannotBeSetWithoutRelease() {
        var draft = ReviewDraft()
        XCTAssertFalse(draft.setArrival(68))
        XCTAssertNil(draft.arrivalFrame)
        XCTAssertEqual(draft.activeField, .release)
    }

    func test_arrivalMustBeAfterRelease() {
        var draft = ReviewDraft()
        _ = draft.setRelease(42)
        XCTAssertFalse(draft.setArrival(42))
        XCTAssertFalse(draft.setArrival(41))
        XCTAssertNil(draft.arrivalFrame)
        XCTAssertEqual(draft.activeField, .arrival)
    }

    func test_settingArrivalCompletesDraftAndSelectsDistance() {
        var draft = ReviewDraft()
        _ = draft.setRelease(42)
        XCTAssertTrue(draft.setArrival(68))
        XCTAssertTrue(draft.isComplete)
        XCTAssertEqual(draft.activeField, .distance)
    }

    func test_movingReleasePastArrivalClearsArrivalAndReturnsToArrival() {
        var draft = ReviewDraft(releaseFrame: 42, arrivalFrame: 68)
        let invalidated = draft.setRelease(70)
        XCTAssertTrue(invalidated)
        XCTAssertEqual(draft.releaseFrame, 70)
        XCTAssertNil(draft.arrivalFrame)
        XCTAssertEqual(draft.activeField, .arrival)
    }

    func test_clearingArrivalPreservesRelease() {
        var draft = ReviewDraft(releaseFrame: 42, arrivalFrame: 68)
        draft.clearArrival()
        XCTAssertEqual(draft.releaseFrame, 42)
        XCTAssertNil(draft.arrivalFrame)
        XCTAssertEqual(draft.activeField, .arrival)
    }

    func test_clearingReleaseClearsBothMarkers() {
        var draft = ReviewDraft(releaseFrame: 42, arrivalFrame: 68)
        draft.clearRelease()
        XCTAssertNil(draft.releaseFrame)
        XCTAssertNil(draft.arrivalFrame)
        XCTAssertEqual(draft.activeField, .release)
    }

    func test_distanceCanBeChangedIndependentlyAfterCompletion() {
        var draft = ReviewDraft(releaseFrame: 42, arrivalFrame: 68, distanceMeters: 18.90)
        draft.select(.distance)
        draft.setDistance(20.12)
        XCTAssertEqual(draft.distanceMeters, 20.12, accuracy: 0.001)
        XCTAssertEqual(draft.activeField, .distance)
        XCTAssertEqual(draft.releaseFrame, 42)
        XCTAssertEqual(draft.arrivalFrame, 68)
    }

    func test_distanceInput_acceptsFourDigitsInOrder() {
        var input = DistanceInput()
        XCTAssertTrue(input.append("1"))
        XCTAssertTrue(input.append("8"))
        XCTAssertTrue(input.append("9"))
        XCTAssertTrue(input.append("0"))
        XCTAssertEqual(input.text, "18.90")
        XCTAssertEqual(input.value, 18.90, accuracy: 0.001)
    }

    func test_distanceInput_rejectsFifthDigit() {
        var input = DistanceInput(digits: "1890")
        XCTAssertFalse(input.append("1"))
        XCTAssertEqual(input.text, "18.90")
    }

    func test_distanceInput_backspaceRemovesLastDigit() {
        var input = DistanceInput(digits: "1890")
        input.backspace()
        XCTAssertEqual(input.text, "01.89")
    }
}
