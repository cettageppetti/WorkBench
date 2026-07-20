import XCTest

final class WorkBenchUITests: XCTestCase {
    @MainActor
    private func launchApp(needsMigration: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--workbench-ui-testing", "-workbenchUITesting", "YES"]
        app.launchEnvironment["WORKBENCH_UI_TESTING"] = "1"
        if needsMigration {
            app.launchEnvironment["WORKBENCH_UI_TEST_NEEDS_MIGRATION"] = "1"
        }
        app.launch()
        return app
    }

    @MainActor
    func testLegacyProjectMigrationIsPresented() {
        continueAfterFailure = false
        let app = launchApp(needsMigration: true)

        XCTAssertTrue(app.staticTexts["Import Existing Projects"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["import-existing-projects-button"].isEnabled)
        XCTAssertTrue(app.buttons["start-empty-library-button"].isEnabled)
        XCTAssertFalse(app.outlines["projects-list"].exists)
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

        app.typeKey("s", modifierFlags: .command)

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
    func testReloadCanCancelDiscardAndSaveUnsavedChanges() {
        continueAfterFailure = false
        let app = launchApp()
        guard app.staticTexts["Starter Project"].waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        renameSelectedProject(to: "Cancelled Reload", in: app)
        reloadConfigurations(in: app)
        chooseUnsavedChanges("Cancel", in: app)
        XCTAssertTrue(app.windows["Cancelled Reload"].waitForExistence(timeout: 2))

        reloadConfigurations(in: app)
        chooseUnsavedChanges("Discard Changes", in: app)
        XCTAssertTrue(app.windows["Starter Project"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["unsaved-changes-indicator"].exists)
        app.terminate()

        let saveApp = launchApp()
        guard saveApp.staticTexts["Starter Project"].waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible after relaunch. Accessibility hierarchy:\n\(saveApp.debugDescription)")
            return
        }
        renameSelectedProject(to: "Saved Reload", in: saveApp)
        reloadConfigurations(in: saveApp)
        chooseUnsavedChanges("Save", in: saveApp)
        XCTAssertTrue(saveApp.windows["Saved Reload"].waitForExistence(timeout: 2))
        let projectsList = saveApp.outlines["projects-list"]
        XCTAssertTrue(projectsList.staticTexts["Saved Reload"].exists)
        XCTAssertFalse(projectsList.staticTexts["Starter Project"].exists)
        XCTAssertFalse(saveApp.staticTexts["unsaved-changes-indicator"].exists)
    }

    @MainActor
    func testWindowCloseCanCancelDiscardAndSaveUnsavedChanges() {
        continueAfterFailure = false
        let app = launchApp()
        guard app.staticTexts["Starter Project"].waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        renameSelectedProject(to: "Cancelled Close", in: app)
        closeWindow(in: app)
        chooseLifecycleUnsavedChanges("Cancel", in: app)
        XCTAssertTrue(app.windows["Cancelled Close"].exists)

        closeWindow(in: app)
        chooseLifecycleUnsavedChanges("Discard Changes", in: app)
        XCTAssertFalse(app.windows["Cancelled Close"].waitForExistence(timeout: 1))
        app.terminate()

        let saveApp = launchApp()
        guard saveApp.staticTexts["Starter Project"].waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible after relaunch. Accessibility hierarchy:\n\(saveApp.debugDescription)")
            return
        }
        renameSelectedProject(to: "Saved Close", in: saveApp)
        closeWindow(in: saveApp)
        chooseLifecycleUnsavedChanges("Save", in: saveApp)
        XCTAssertFalse(saveApp.windows["Saved Close"].waitForExistence(timeout: 1))
    }

    @MainActor
    func testQuitCanCancelDiscardAndSaveUnsavedChanges() {
        continueAfterFailure = false
        let app = launchApp()
        guard app.staticTexts["Starter Project"].waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        renameSelectedProject(to: "Cancelled Quit", in: app)
        quitApplication(app)
        chooseLifecycleUnsavedChanges("Cancel", in: app)
        app.activate()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.windows["Cancelled Quit"].exists)

        quitApplication(app)
        chooseLifecycleUnsavedChanges("Discard Changes", in: app)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 2))

        let saveApp = launchApp()
        guard saveApp.staticTexts["Starter Project"].waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible after relaunch. Accessibility hierarchy:\n\(saveApp.debugDescription)")
            return
        }
        renameSelectedProject(to: "Saved Quit", in: saveApp)
        quitApplication(saveApp)
        chooseLifecycleUnsavedChanges("Save", in: saveApp)
        XCTAssertTrue(saveApp.wait(for: .notRunning, timeout: 2))
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

        app.typeKey("s", modifierFlags: .command)

        XCTAssertFalse(app.staticTexts["unsaved-changes-indicator"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Development Terminal"].exists)
        XCTAssertEqual(
            app.textFields["terminal-working-directory-field"].value as? String,
            "~/Projects"
        )
    }

    @MainActor
    func testChromeWindowCanBeAddedEditedAndSaved() {
        continueAfterFailure = false
        let app = launchApp()
        guard app.staticTexts["Starter Project"].waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        let addResource = app.descendants(matching: .any)["Add Resource"]
        XCTAssertTrue(addResource.waitForExistence(timeout: 2))
        addResource.click()
        XCTAssertTrue(app.menuItems["Application…"].waitForExistence(timeout: 2))
        let chromeMenuItem = app.menuItems["Chrome Window"]
        XCTAssertTrue(chromeMenuItem.waitForExistence(timeout: 2))
        chromeMenuItem.click()

        XCTAssertTrue(app.staticTexts["Chrome Window"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Chrome Tabs"].exists)
        replaceText(
            in: app.textFields["browser-tab-0-field"],
            with: "https://chromium.org"
        )
        app.buttons["Add Tab"].click()
        replaceText(
            in: app.textFields["browser-tab-1-field"],
            with: "https://example.com"
        )
        app.buttons["move-browser-url-up-1"].click()

        app.typeKey("s", modifierFlags: .command)
        XCTAssertFalse(app.staticTexts["unsaved-changes-indicator"].waitForExistence(timeout: 1))
        XCTAssertEqual(
            app.textFields["browser-tab-0-field"].value as? String,
            "https://example.com"
        )
        XCTAssertEqual(
            app.textFields["browser-tab-1-field"].value as? String,
            "https://chromium.org"
        )
    }

    @MainActor
    func testApplicationCanBeConfiguredAsWebBrowserAndSaved() {
        continueAfterFailure = false
        let app = launchApp()
        let project = app.staticTexts["Application Project"]
        guard project.waitForExistence(timeout: 5) else {
            XCTFail("Application Project was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }
        project.click()

        let resource = app.staticTexts["Brave Browser"]
        XCTAssertTrue(resource.waitForExistence(timeout: 2))
        resource.click()

        let browserRole = app.switches["web-browser-role-toggle"]
        XCTAssertTrue(browserRole.waitForExistence(timeout: 2))
        browserRole.click()

        XCTAssertTrue(app.staticTexts["Web Browser URLs"].waitForExistence(timeout: 2))
        replaceText(in: app.textFields["browser-tab-0-field"], with: "https://brave.com")
        app.buttons["Add Tab"].click()
        replaceText(in: app.textFields["browser-tab-1-field"], with: "https://example.com")
        app.buttons["move-browser-url-up-1"].click()

        app.typeKey("s", modifierFlags: .command)

        XCTAssertFalse(app.staticTexts["unsaved-changes-indicator"].waitForExistence(timeout: 1))
        XCTAssertEqual(app.textFields["browser-tab-0-field"].value as? String, "https://example.com")
        XCTAssertEqual(app.textFields["browser-tab-1-field"].value as? String, "https://brave.com")
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

        app.typeKey("s", modifierFlags: .command)

        XCTAssertFalse(app.staticTexts["unsaved-changes-indicator"].waitForExistence(timeout: 1))
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
        chooseFileCommand("Delete Project", in: app)

        var alert = app.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(alert.staticTexts["Delete Project?"].exists)
        XCTAssertTrue(alert.staticTexts[
            "\"Second Project\" will be deleted from the WorkBench Project library."
        ].exists)
        alert.buttons["Cancel"].click()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
        XCTAssertTrue(secondProject.exists)

        chooseFileCommand("Delete Project", in: app)
        alert = app.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(alert.staticTexts["Delete Project?"].exists)
        alert.buttons["Delete"].click()

        XCTAssertFalse(secondProject.waitForExistence(timeout: 1))
        XCTAssertTrue(starterProject.exists)
    }

    @MainActor
    func testProjectsCanBeCreatedAndDuplicated() {
        continueAfterFailure = false
        let app = launchApp()
        guard app.staticTexts["Starter Project"].waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }
        let projectsList = app.outlines["projects-list"]
        XCTAssertTrue(projectsList.exists)

        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        for command in ["New Project", "Open Project", "Save", "Duplicate Project", "Delete Project"] {
            XCTAssertTrue(app.menuItems[command].exists)
        }
        app.menuItems["New Project"].click()

        let nameField = app.textFields["project-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertEqual(nameField.value as? String, "Untitled Project")
        XCTAssertFalse(projectsList.staticTexts["Untitled Project"].exists)

        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(projectsList.staticTexts["Untitled Project"].exists)

        chooseFileCommand("Duplicate Project", in: app)
        XCTAssertEqual(nameField.value as? String, "Untitled Project Copy")
        XCTAssertFalse(projectsList.staticTexts["Untitled Project Copy"].exists)

        app.typeKey("s", modifierFlags: .command)
        XCTAssertFalse(app.staticTexts["unsaved-changes-indicator"].waitForExistence(timeout: 1))
        XCTAssertTrue(projectsList.staticTexts["Untitled Project"].exists)
        XCTAssertTrue(projectsList.staticTexts["Untitled Project Copy"].exists)
    }

    @MainActor
    func testInvalidProjectPresentsLaunchReport() {
        continueAfterFailure = false
        let app = launchApp()
        let terminalResource = app.staticTexts["Home Terminal"]
        guard app.staticTexts["Starter Project"].waitForExistence(timeout: 5),
              terminalResource.waitForExistence(timeout: 2) else {
            XCTFail("Starter Project resources were not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        terminalResource.click()
        replaceText(
            in: app.textFields["terminal-working-directory-field"],
            with: "Projects"
        )

        app.typeKey("o", modifierFlags: .command)

        let report = app.sheets.firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 2))
        XCTAssertTrue(report.staticTexts["Couldn’t Fully Open Starter Project"].exists)
        XCTAssertTrue(report.staticTexts[
            "resources[1].workingDirectory: Use an absolute path or a home-relative path beginning with ~/."
        ].exists)

        report.buttons["dismiss-launch-report-button"].click()
        XCTAssertFalse(report.waitForExistence(timeout: 1))
    }

    @MainActor
    func testPlacementFailureCanBeCancelledOrOpenedWithoutPlacement() {
        continueAfterFailure = false
        let app = launchApp()
        let placedProject = app.staticTexts["Placed Project"]
        guard placedProject.waitForExistence(timeout: 5) else {
            XCTFail("Placed Project was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }
        placedProject.click()

        app.typeKey("o", modifierFlags: .command)

        let alert = app.sheets.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(alert.staticTexts["Couldn’t Open Project in Its Workspace"].exists)
        XCTAssertTrue(alert.staticTexts["AeroSpace integration is disabled in Settings."].exists)
        alert.buttons["Cancel"].click()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))

        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        let openWithoutPlacement = alert.buttons["Open Without Placement"]
        XCTAssertTrue(openWithoutPlacement.exists)
        openWithoutPlacement.click()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
    }

    @MainActor
    func testProjectLaunchDestinationCanBeEditedAndSaved() {
        continueAfterFailure = false
        let app = launchApp()
        guard app.staticTexts["Starter Project"].waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        let resource = app.staticTexts["Web"]
        XCTAssertTrue(resource.waitForExistence(timeout: 2))
        resource.click()
        XCTAssertTrue(app.textFields["resource-name-field"].waitForExistence(timeout: 2))

        let projectSettings = app.buttons["project-settings-row"]
        XCTAssertTrue(projectSettings.waitForExistence(timeout: 2))
        projectSettings.click()

        let placement = app.popUpButtons["launch-destination-picker"]
        XCTAssertTrue(placement.waitForExistence(timeout: 2))
        placement.click()
        app.menuItems["AeroSpace Workspace"].click()
        app.typeKey(.escape, modifierFlags: [])

        let workspace = app.textFields["aerospace-workspace-field"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 2))
        workspace.click()
        workspace.typeText("N")
        XCTAssertTrue(app.staticTexts["unsaved-changes-indicator"].exists)

        app.typeKey("s", modifierFlags: .command)

        XCTAssertFalse(app.staticTexts["unsaved-changes-indicator"].waitForExistence(timeout: 1))
        XCTAssertEqual(workspace.value as? String, "N")
    }

    @MainActor
    func testAeroSpaceSettingsCanBeEnabledAndConnectionChecked() {
        continueAfterFailure = false
        let app = launchApp()
        guard app.staticTexts["Starter Project"].waitForExistence(timeout: 5) else {
            XCTFail("Starter Project was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        app.typeKey(",", modifierFlags: .command)

        let toggle = app.switches["enable-aerospace-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.click()

        let checkConnection = app.buttons["Check Connection"]
        XCTAssertTrue(checkConnection.waitForExistence(timeout: 2))
        checkConnection.click()
        XCTAssertTrue(app.staticTexts["1, 2"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testInvalidFileAndUnsupportedResourceRemainVisible() {
        continueAfterFailure = false
        let app = launchApp()
        guard app.staticTexts["broken.json"].waitForExistence(timeout: 5) else {
            XCTFail("Configuration issue was not visible. Accessibility hierarchy:\n\(app.debugDescription)")
            return
        }

        XCTAssertTrue(app.staticTexts["The file could not be decoded."].exists)

        let futureProject = app.staticTexts["Future Project"]
        XCTAssertTrue(futureProject.waitForExistence(timeout: 2))
        futureProject.click()

        let futureResource = app.staticTexts["Future Resource"]
        XCTAssertTrue(futureResource.waitForExistence(timeout: 2))
        futureResource.click()

        XCTAssertTrue(app.staticTexts["future-resource"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts[
            "This Resource type is unsupported. Its JSON will be preserved."
        ].exists)
        let fileMenu = app.menuBars.menuBarItems["File"]
        fileMenu.click()
        XCTAssertTrue(app.menuItems["Open Project"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
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

    @MainActor
    private func reloadConfigurations(in app: XCUIApplication) {
        app.typeKey("r", modifierFlags: [.command, .shift])
    }

    @MainActor
    private func chooseFileCommand(_ command: String, in app: XCUIApplication) {
        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 2))
        fileMenu.click()
        let item = app.menuItems[command]
        XCTAssertTrue(item.waitForExistence(timeout: 2))
        item.click()
    }

    @MainActor
    private func closeWindow(in app: XCUIApplication) {
        let closeButton = app.buttons["_XCUI:CloseWindow"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
        closeButton.click()
    }

    @MainActor
    private func quitApplication(_ app: XCUIApplication) {
        let applicationMenu = app.menuBars.menuBarItems["WorkBench"]
        XCTAssertTrue(applicationMenu.waitForExistence(timeout: 2))
        applicationMenu.click()
        let quitItem = applicationMenu.menus.menuItems["Quit WorkBench"]
        XCTAssertTrue(quitItem.waitForExistence(timeout: 2))
        quitItem.click()
    }

    @MainActor
    private func chooseLifecycleUnsavedChanges(_ choice: String, in app: XCUIApplication) {
        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 2))
        XCTAssertTrue(dialog.staticTexts["Your changes will be lost if you don’t save them."].exists)
        let button = dialog.buttons[choice]
        XCTAssertTrue(button.exists)
        button.click()
        XCTAssertFalse(dialog.waitForExistence(timeout: 1))
    }
}
