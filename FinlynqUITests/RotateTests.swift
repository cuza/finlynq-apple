import XCTest

/// Used by `scripts/screens.sh`: turns the simulator to landscape so iPad screenshots match the designs.
/// `simctl` can't rotate a device and there is no Simulator app to do it, so a UI test sets the orientation.
/// Skipped unless the runner sets FINLYNQ_ROTATE (`TEST_RUNNER_FINLYNQ_ROTATE=1` on the xcodebuild command line).
final class RotateTests: XCTestCase {
    @MainActor
    func testRotateToLandscape() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FINLYNQ_ROTATE"] == "1", "only for scripts/screens.sh")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCUIDevice.shared.orientation, .landscapeLeft)
    }
}
