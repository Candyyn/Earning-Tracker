import XCTest

final class LiveTrackerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsPayPeriodNavigationAndCreation() throws {
        let app = launchApp(seedData: true)

        app.buttons["dashboard.settings"].tap()
        XCTAssertTrue(app.navigationBars["Inställningar"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["settings.list"].exists || app.collectionViews["settings.list"].exists)

        let payPeriodRows = app.descendants(matching: .any).matching(identifier: "settings.payPeriodRow")
        XCTAssertEqual(payPeriodRows.count, 1)

        app.buttons["settings.addPayPeriod"].tap()
        XCTAssertEqual(payPeriodRows.count, 2)

        payPeriodRows.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Löneperiod"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Uppskattade nettobelopp"].exists)
        XCTAssertTrue(app.staticTexts["Dag"].exists)
    }

    @MainActor
    func testShiftCreationEditingAndMonthNavigation() throws {
        let app = launchApp(seedData: true)

        app.buttons["dashboard.shifts"].tap()
        XCTAssertTrue(app.navigationBars["Arbetspass"].waitForExistence(timeout: 2))

        let shiftRows = app.descendants(matching: .any).matching(identifier: "shifts.row")
        XCTAssertEqual(shiftRows.count, 1)

        app.buttons["shifts.add"].tap()
        XCTAssertTrue(app.navigationBars["Nytt pass"].waitForExistence(timeout: 2))
        app.buttons["shiftEditor.save"].tap()
        XCTAssertEqual(shiftRows.count, 2)

        shiftRows.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Redigera pass"].waitForExistence(timeout: 2))
        app.buttons["Avbryt"].tap()

        app.buttons["shifts.nextMonth"].tap()
        XCTAssertTrue(app.staticTexts["Inga pass"].waitForExistence(timeout: 2))
        app.buttons["shifts.previousMonth"].tap()
        XCTAssertEqual(shiftRows.count, 2)
    }

    @MainActor
    func testEmptyMonthOffersAddShiftAction() throws {
        let app = launchApp(seedData: false)

        app.buttons["dashboard.shifts"].tap()
        XCTAssertTrue(app.staticTexts["Inga pass"].waitForExistence(timeout: 2))
        app.buttons["shifts.empty.add"].tap()
        XCTAssertTrue(app.navigationBars["Nytt pass"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testTaxRefundIsAccessibleFromDashboard() throws {
        let app = launchApp(seedData: true)

        app.buttons["dashboard.settings"].tap()
        XCTAssertTrue(app.navigationBars["Inställningar"].waitForExistence(timeout: 2))
        app.buttons["settings.taxRefund"].tap()
        XCTAssertTrue(app.navigationBars["Skatteåterbäring"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["taxRefund.list"].exists || app.collectionViews["taxRefund.list"].exists)
    }

    @MainActor
    func testShiftDeletionRequiresConfirmation() throws {
        let app = launchApp(seedData: true)

        app.buttons["dashboard.shifts"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "shifts.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.swipeLeft()
        app.buttons["Ta bort"].tap()
        XCTAssertTrue(app.buttons["Ta bort pass"].waitForExistence(timeout: 2))
        app.buttons["Ta bort pass"].tap()
        XCTAssertTrue(app.staticTexts["Inga pass"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-testing"]
            app.launch()
        }
    }

    @MainActor
    private func launchApp(seedData: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = seedData
            ? ["--ui-testing", "--ui-testing-seeded"]
            : ["--ui-testing"]
        app.launch()
        return app
    }
}
