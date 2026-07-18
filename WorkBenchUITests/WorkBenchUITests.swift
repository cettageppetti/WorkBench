import XCTest

final class WorkBenchUITests: XCTestCase {
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--workbench-ui-testing", "-workbenchUITesting", "YES"]
        app.launchEnvironment["WORKBENCH_UI_TESTING"] = "1"
        app.launch()
        return app
    }

    @MainActor
    func testStarterProjectCanBeRenamedAndSaved() {
        continueAfterFailure = false
        let app = launchApp()
        let starterProject = app.staticTexts["Starter Project"]
        guard starterProject.waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        let nameField = app.textFields["project-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("Renamed Project")

        XCTAssertTrue(app.staticTexts["unsaved-changes-indicator"].waitForExistence(timeout: 2))

        let saveButton = app.buttons["save-project-button"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.click()

        XCTAssertFalse(app.staticTexts["unsaved-changes-indicator"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Renamed Project"].exists)
    }
}
