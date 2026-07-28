import XCTest

final class OpenEQUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsMainControls() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows["OpenEQ"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["System Audio"].exists)
        XCTAssertTrue(app.buttons["folder.badge.plus"].exists)
    }

    @MainActor
    func testSystemAudioPanelCanBeOpened() throws {
        let app = XCUIApplication()
        app.launch()

        let systemAudioButton = app.buttons["System Audio"]
        XCTAssertTrue(systemAudioButton.waitForExistence(timeout: 8))
        systemAudioButton.click()

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["System Audio"].exists)

        let systemWideMode = app.radioButtons["System-Wide EQ"]
        XCTAssertTrue(systemWideMode.waitForExistence(timeout: 3))
        systemWideMode.click()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 3))
    }
}
