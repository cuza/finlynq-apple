import XCTest

final class SettingsTests: XCTestCase {
    /// On iPhone, Settings is a sheet. A refused category delete offers Show transactions, which opens Activity
    /// inside that sheet, and Activity's Import must still open its sheet on top.
    @MainActor
    func testImportOpensFromActivityInsideTheSettingsSheet() {
        let app = XCUIApplication()
        app.launchEnvironment["FINLYNQ_FIXTURES"] = "1"
        app.launch()
        let home = app.tabBars.buttons["Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        if !home.isSelected { home.tap() }
        app.buttons["Settings"].firstMatch.tap()

        let categories = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Categories")).firstMatch
        XCTAssertTrue(categories.waitForExistence(timeout: 5))
        categories.tap()
        let groceries = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Groceries")).firstMatch
        XCTAssertTrue(groceries.waitForExistence(timeout: 5))
        groceries.tap()

        // The fixtures refuse every category delete, as the server does for a category in use.
        let delete = app.buttons["Delete category"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons.matching(identifier: "Delete category").element(boundBy: 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let show = app.buttons["Show transactions"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()

        let importButton = app.buttons["Import a statement"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 30), "Activity didn't open")
        importButton.tap()
        XCTAssertTrue(app.staticTexts["Import statement"].waitForExistence(timeout: 15), "the Import sheet didn't open")
    }
}
