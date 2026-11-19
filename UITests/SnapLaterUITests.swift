import XCTest

@MainActor final class SnapLaterUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testManualTaskAndCompletion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let input = app.textFields["newTaskTitle"]
        XCTAssertTrue(input.waitForExistence(timeout: 60))
        input.click(); input.typeText("Explore native apps")
        app.buttons["addTask"].click()
        app.buttons["Open Explore native apps"].click()
        let title = app.textFields["detailTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Explore native apps")
        XCTAssertFalse(app.buttons["toggleTodo"].exists)
        XCTAssertFalse(app.buttons["toggleProgress"].exists)
        app.buttons["detailComplete"].click()
        XCTAssertTrue(app.buttons["detailComplete"].exists)
        XCTAssertEqual(app.buttons["detailComplete"].label, "Reopen")
        app.terminate()
    }

    func testSettingsAndAnalyticsStayInsideLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 60))
        app.buttons["Settings"].click()
        app.buttons["AI summaries"].click()
        XCTAssertTrue(app.buttons["aiSummaries"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)
        app.buttons["Back"].click()
        app.buttons["Analytics"].click()
        XCTAssertTrue(app.staticTexts["Your momentum"].waitForExistence(timeout: 5))
        app.terminate()
    }
}
