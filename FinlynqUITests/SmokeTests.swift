import XCTest

final class SmokeTests: XCTestCase {
    // The first tab's navigation title.
    private let homeTitle = "Home"

    /// A button in the system tab bar, found by its title.
    @MainActor
    private func tab(_ app: XCUIApplication, _ title: String) -> XCUIElement { app.tabBars.buttons[title] }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FINLYNQ_FIXTURES"] = "1"
        app.launch()
        return app
    }

    /// Shows Home. The app restores the last selected tab, so Home may need a tap.
    @MainActor
    private func showHome(_ app: XCUIApplication) {
        let home = tab(app, homeTitle)
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        if !home.isSelected { home.tap() }
    }

    @MainActor
    func testLaunchesInFixtureModeAndShowsHome() {
        let app = launch()
        showHome(app)
        XCTAssertTrue(app.navigationBars[homeTitle].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTabsSwitch() {
        let app = launch()
        XCTAssertTrue(tab(app, homeTitle).waitForExistence(timeout: 5))
        for title in [homeTitle, "Activity", "Plan", "Wealth", "Insights"] {
            let item = tab(app, title)
            if !item.isSelected { item.tap() }
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(title) tab shows its title")
        }
    }

    @MainActor
    func testHomeShowsNetWorth() {
        let app = launch()
        showHome(app)
        // The fixture accounts add up to -168,326.22 in INR.
        let netWorth = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "168,326.22")).firstMatch
        XCTAssertTrue(netWorth.waitForExistence(timeout: 5))
    }

    @MainActor
    func testActivityOpensDetailAndCalendar() {
        let app = launch()
        XCTAssertTrue(tab(app, "Activity").waitForExistence(timeout: 5))
        tab(app, "Activity").tap()
        XCTAssertTrue(app.textFields["activitySearch"].waitForExistence(timeout: 5), "search is always visible")
        XCTAssertTrue(app.staticTexts["To review"].waitForExistence(timeout: 5), "the review bar shows when rows are pending")
        // The first row opens the detail screen, which has the red delete button.
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "$")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Delete transaction"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        // The calendar button swaps the list for the month grid in place.
        app.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["Previous month"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAddExpenseFlow() {
        let app = launch()
        showHome(app)
        // On a cold-booted simulator Home is still loading after the tab appears; wait for its content first.
        let netWorth = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "168,326.22")).firstMatch
        XCTAssertTrue(netWorth.waitForExistence(timeout: 10))
        let add = app.buttons["addButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isHittable)
        add.tap()
        let save = app.buttons["addSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save needs an amount and a category")
        for key in ["1", "2", "Decimal point", "5"] { app.buttons[key].tap() }
        // The first category tile is a button with a category name; "All" is a menu.
        app.buttons.matching(NSPredicate(format: "label == %@", "Dining")).firstMatch.tap()
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "the sheet dismisses after Save")
        XCTAssertTrue(tab(app, homeTitle).exists)
        XCTAssertFalse(app.staticTexts["addError"].exists)
    }

    @MainActor
    func testTabBarStaysBehindKeyboard() {
        let app = launch()
        let activity = tab(app, "Activity")
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        activity.tap()
        let search = app.textFields["activitySearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "activity-search-keyboard"
        shot.lifetime = .keepAlways
        add(shot)
        // The tab bar stays at the bottom, under the keyboard, instead of riding up above it.
        XCTAssertGreaterThan(activity.frame.minY, keyboard.frame.minY)
    }

    /// Skips unless turning this device swaps the tab bar for the sidebar: an iPhone Plus or Pro Max, 926pt tall or
    /// more, is compact in portrait and regular in landscape. A smaller iPhone stays compact and an iPad is regular
    /// both ways. `scripts/check.sh` runs these on `ROTATE_SIM_ID`, a Pro Max.
    @MainActor
    private func skipUnlessTurningSwapsTheShell(_ app: XCUIApplication, tab title: String) throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        guard tab(app, title).waitForExistence(timeout: 5) else { throw XCTSkip("regular width already: no tab bar") }
        guard app.windows.firstMatch.frame.height >= 926 else { throw XCTSkip("this iPhone stays compact in landscape") }
    }

    /// A row on Wealth opens its account page, and the page loads.
    @MainActor
    func testWealthOpensAnAccount() {
        let app = launch()
        let wealth = tab(app, "Wealth")
        XCTAssertTrue(wealth.waitForExistence(timeout: 5))
        if !wealth.isSelected { wealth.tap() }
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Chequing,")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["Chequing"].waitForExistence(timeout: 10), "the account page is pushed")
        XCTAssertTrue(app.buttons["Import statement"].waitForExistence(timeout: 10), "and its content loads")
    }

    /// A width class change keeps the view tree: a pushed page and the search text survive.
    @MainActor
    func testWidthChangeKeepsThePushedPage() throws {
        let app = launch()
        try skipUnlessTurningSwapsTheShell(app, tab: "Activity")
        let activity = tab(app, "Activity")
        activity.tap()
        let search = app.textFields["activitySearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Metro")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Metro")).firstMatch.tap()
        let detail = app.buttons["Delete transaction"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(tab(app, "Activity").waitForNonExistence(timeout: 5), "regular width swaps the tab bar for the sidebar")
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "the pushed transaction survives the change to regular width")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(tab(app, "Activity").waitForExistence(timeout: 5))
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "and the change back to compact width")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(search.value as? String, "Metro", "the search text survives both changes")
    }

    /// A width class change keeps an editor sheet open with its draft.
    @MainActor
    func testWidthChangeKeepsTheEditorDraft() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FINLYNQ_FIXTURES"] = "1"
        app.launchEnvironment["FINLYNQ_ROUTE"] = "goals"
        app.launch()
        try skipUnlessTurningSwapsTheShell(app, tab: "Plan")
        let newGoal = app.buttons["New goal"]
        XCTAssertTrue(newGoal.waitForExistence(timeout: 10))
        newGoal.tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Boat")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(tab(app, "Plan").waitForNonExistence(timeout: 5), "regular width swaps the tab bar for the sidebar")
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Boat", "the sheet and its draft survive the change")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(tab(app, "Plan").waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Boat", "and the change back")
    }

    /// Deleting a goal from its own page closes the editor sheet and then the page, back to the goals list.
    @MainActor
    func testDeletingAGoalReturnsToGoals() {
        let app = XCUIApplication()
        app.launchEnvironment["FINLYNQ_FIXTURES"] = "1"
        // The goals route, not goal:<id>: the test opens the goal from its card, as a tap does.
        app.launchEnvironment["FINLYNQ_ROUTE"] = "goals"
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Emergency fund")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        // The goal's name is the page's large title.
        let page = app.navigationBars["Emergency fund"]
        let edit = page.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let delete = app.buttons["Delete goal"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Delete")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5), "the editor sheet closes")
        XCTAssertTrue(page.waitForNonExistence(timeout: 5), "the goal page pops")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "back on the goals list")
    }
}
