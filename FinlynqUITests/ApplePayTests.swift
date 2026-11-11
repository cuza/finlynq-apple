import XCTest

final class ApplePayTests: XCTestCase {
    /// Settings has the Apple Pay row, and it opens the setup screen with its steps, cards, Add shortcut and
    /// Open Shortcuts.
    @MainActor
    func testSettingsOpensApplePaySetup() {
        let app = XCUIApplication()
        app.launchEnvironment["FINLYNQ_FIXTURES"] = "1"
        app.launch()
        let home = app.tabBars.buttons["Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        if !home.isSelected { home.tap() }
        app.buttons["Settings"].firstMatch.tap()
        let row = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Apple Pay purchases")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        if !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.buttons["Open Shortcuts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add shortcut"].exists, "the bundled shortcut is missing")
        XCTAssertTrue(app.staticTexts["Not set up yet. Takes about a minute in the Shortcuts app."].exists)
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Visa Rewards")).firstMatch.exists)
    }
}
