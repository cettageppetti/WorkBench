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

    @MainActor
    func testSwitchingProjectsCanCancelDiscardAndSaveUnsavedChanges() {
        continueAfterFailure = false
        let app = launchApp()
        let starterProject = app.staticTexts["Starter Project"]
        let secondProject = app.staticTexts["Second Project"]
        guard starterProject.waitForExistence(timeout: 5),
              secondProject.waitForExistence(timeout: 2) else {
            XCTFail("UI-test Projects were not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        renameSelectedProject(to: "Cancelled Rename", in: app)
        secondProject.click()
        chooseUnsavedChanges("Cancel", in: app)

        secondProject.click()
        chooseUnsavedChanges("Discard Changes", in: app)
        XCTAssertEqual(app.textFields["project-name-field"].value as? String, "Second Project")

        renameSelectedProject(to: "Saved Second Project", in: app)
        starterProject.click()
        chooseUnsavedChanges("Save", in: app)
        XCTAssertTrue(app.staticTexts["Starter Project"].exists)
        XCTAssertTrue(app.staticTexts["Saved Second Project"].exists)
        XCTAssertFalse(app.staticTexts["Second Project"].exists)
    }

    @MainActor
    func testTerminalResourceCanBeSelectedEditedAndSaved() {
        continueAfterFailure = false
        let app = launchApp()
        let terminalResource = app.staticTexts["Home Terminal"]
        guard app.staticTexts["Starter Project"].waitForExistence(timeout: 5),
              terminalResource.waitForExistence(timeout: 2) else {
            XCTFail("Starter Project resources were not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        terminalResource.click()
        replaceText(in: app.textFields["resource-name-field"], with: "Development Terminal")
        replaceText(
            in: app.textFields["terminal-working-directory-field"],
            with: "~/Projects"
        )

        let saveButton = app.buttons["save-project-button"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.click()

        XCTAssertFalse(saveButton.isEnabled)
        XCTAssertTrue(app.staticTexts["Development Terminal"].exists)
        XCTAssertEqual(
            app.textFields["terminal-working-directory-field"].value as? String,
            "~/Projects"
        )
    }

    @MainActor
    func testResourcesCanBeReorderedAndSaved() {
        continueAfterFailure = false
        let app = launchApp()
        let browserResource = app.staticTexts["Web"]
        let finderResource = app.staticTexts["Home Folder"]
        guard app.staticTexts["Starter Project"].waitForExistence(timeout: 5),
              browserResource.waitForExistence(timeout: 2),
              finderResource.waitForExistence(timeout: 2) else {
            XCTFail("Starter Project resources were not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        finderResource.click(forDuration: 0.5, thenDragTo: browserResource)
        XCTAssertGreaterThan(finderResource.frame.minY, browserResource.frame.minY)

        let saveButton = app.buttons["save-project-button"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.click()

        XCTAssertFalse(saveButton.isEnabled)
        XCTAssertGreaterThan(finderResource.frame.minY, browserResource.frame.minY)
    }

    @MainActor
    func testProjectDeletionCanBeCancelledAndConfirmed() {
        continueAfterFailure = false
        let app = launchApp()
        let starterProject = app.staticTexts["Starter Project"]
        let secondProject = app.staticTexts["Second Project"]
        guard starterProject.waitForExistence(timeout: 5),
              secondProject.waitForExistence(timeout: 2) else {
            XCTFail("UI-test Projects were not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        secondProject.click()
        let deleteButton = app.buttons["delete-project-button"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        deleteButton.click()

        var alert = app.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(alert.staticTexts["Delete Project?"].exists)
        XCTAssertTrue(alert.staticTexts["\"Second Project\" and its JSON configuration file will be deleted."].exists)
        alert.buttons["Cancel"].click()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
        XCTAssertTrue(secondProject.exists)

        deleteButton.click()
        alert = app.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(alert.staticTexts["Delete Project?"].exists)
        alert.buttons["Delete"].click()

        XCTAssertFalse(secondProject.waitForExistence(timeout: 1))
        XCTAssertTrue(starterProject.exists)
    }

    @MainActor
    private func renameSelectedProject(to name: String, in app: XCUIApplication) {
        let nameField = app.textFields["project-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        replaceText(in: nameField, with: name)
        XCTAssertTrue(app.staticTexts["unsaved-changes-indicator"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
    }

    @MainActor
    private func chooseUnsavedChanges(_ choice: String, in app: XCUIApplication) {
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 2))
        XCTAssertTrue(sheet.staticTexts["Save changes before continuing?"].exists)
        let button = sheet.buttons[choice]
        XCTAssertTrue(button.exists)
        button.click()
        XCTAssertFalse(sheet.waitForExistence(timeout: 1))
    }
}
