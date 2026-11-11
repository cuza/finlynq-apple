import XCTest

/// Charts scrub only after a press of a quarter second, so a swipe that starts on a chart still scrolls the page.
final class ChartScrubTests: XCTestCase {
    @MainActor
    func testSwipeStartingOnTheNetWorthChartScrollsThePage() {
        let app = XCUIApplication()
        app.launchEnvironment["FINLYNQ_FIXTURES"] = "1"
        app.launchEnvironment["FINLYNQ_ROUTE"] = "netWorth"
        app.launch()
        let chart = app.otherElements["Net worth over time"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        let header = app.staticTexts["By account group"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let before = header.frame.minY
        // A freshly booted simulator can stall long enough to drop the first swipe, so try up to three times. A chart
        // that scrubs on touch takes every one of them.
        for _ in 0..<3 where header.frame.minY >= before - 50 {
            chart.swipeUp()
        }
        XCTAssertLessThan(header.frame.minY, before - 50, "the chart took the swipe and the page did not scroll")
    }
}
