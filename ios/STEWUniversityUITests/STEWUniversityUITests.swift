import XCTest

@MainActor
final class STEWUniversityUITests: XCTestCase {
    func testLaunchAndAdaptiveNavigation() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-reset-ear-training")
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["What can I help\nyou write?"].waitForExistence(timeout: 3))
        let compactHeading = app.descendants(matching: .any)["compact-screen-heading"]
        let compactMenu = app.buttons["Open navigation menu"]
        if compactMenu.waitForExistence(timeout: 1) {
            XCTAssertTrue(compactHeading.exists)
            compactMenu.tap()
            let headingHidden = expectation(
                for: NSPredicate(format: "exists == false"),
                evaluatedWith: compactHeading
            )
            wait(for: [headingHidden], timeout: 2)
        } else {
            revealNavigation(in: app)
        }
        XCTAssertTrue(app.buttons["Jam"].exists)
        XCTAssertTrue(app.buttons["Band"].exists)
        XCTAssertTrue(app.buttons["Ear Training"].exists)
        XCTAssertTrue(app.buttons["Visualizer"].exists)
        XCTAssertTrue(app.buttons["Games"].exists)
        XCTAssertFalse(app.buttons["Studio"].exists)
        navigate(to: "Jam", in: app)
        if compactMenu.exists {
            XCTAssertTrue(compactHeading.waitForExistence(timeout: 2))
            XCTAssertEqual(compactHeading.label, "Jam")
        }
        XCTAssertTrue(app.staticTexts["Have fun Jamming"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Choose an instrument"].waitForExistence(timeout: 3))

        let guitar = app.buttons["jam-instrument-guitar"]
        XCTAssertTrue(guitar.waitForExistence(timeout: 3))
        guitar.tap()
        XCTAssertTrue(app.staticTexts["Guitar tracks are on the way"].waitForExistence(timeout: 3))

        navigate(to: "Songwriting", in: app)
        navigate(to: "Jam", in: app)
        XCTAssertTrue(app.staticTexts["Guitar tracks are on the way"].waitForExistence(timeout: 3))

        app.terminate()
        app.launch()
        navigate(to: "Jam", in: app)
        XCTAssertTrue(app.staticTexts["Choose an instrument"].waitForExistence(timeout: 3))
    }

    func testSignedOutBandGate() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-band-signed-out"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["band-account-required"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Make music together"].exists)
        XCTAssertTrue(app.buttons["Continue with Apple"].exists)
    }

    func testEmptyBandWelcomeCanCreateOrJoin() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-band-empty"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["band-welcome"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Create Band"].exists)
        XCTAssertTrue(app.buttons["Join with Invite"].exists)
    }

    func testDemoOwnerBandWorkspaceSections() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-band-demo"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["band-workspace"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Golden Hour"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Home, page 1 of 3"].waitForExistence(timeout: 3))
        let featuredProject = app.descendants(matching: .any)["band-featured-project"]
        XCTAssertTrue(featuredProject.exists)
        XCTAssertTrue(app.descendants(matching: .any)["band-board-card-note"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["band-board-card-image"].exists)
        featuredProject.tap()
        XCTAssertTrue(app.navigationBars["Open Skies"].waitForExistence(timeout: 3))
        app.navigationBars["Open Skies"].buttons.firstMatch.tap()
        app.swipeLeft()
        XCTAssertTrue(app.descendants(matching: .any)["Projects, page 2 of 3"].waitForExistence(timeout: 3))
        let project = app.staticTexts["Open Skies"]
        XCTAssertTrue(project.waitForExistence(timeout: 3))
        project.tap()
        XCTAssertTrue(app.navigationBars["Open Skies"].waitForExistence(timeout: 3))
        app.navigationBars["Open Skies"].buttons.firstMatch.tap()
        app.swipeLeft()
        XCTAssertTrue(app.descendants(matching: .any)["Members, page 3 of 3"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Jaylon"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Owner"].exists)
    }

    func testDemoOwnerCanOpenMoodBoardComposerAndAppearance() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-band-demo"]
        app.launch()
        let add = app.descendants(matching: .any)["band-add-to-board"]
        XCTAssertTrue(add.waitForExistence(timeout: 4))
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any)["band-card-type-note"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["band-card-type-image"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["band-card-type-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["band-card-type-project"].exists)
        app.buttons["Cancel"].tap()

        app.buttons["Band settings"].tap()
        let appearance = app.descendants(matching: .any)["band-appearance-settings-link"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        appearance.tap()
        XCTAssertTrue(app.descendants(matching: .any)["band-appearance-settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Accent color"].exists)
        XCTAssertTrue(app.staticTexts["Featured project"].exists)
    }

    func testEarTrainingGamificationAndGoalSettings() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-reset-ear-training")
        app.launch()
        navigate(to: "Ear Training", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["ear-training-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Daily Ear Workout"].exists)
        XCTAssertTrue(app.staticTexts["Today’s goal"].exists)
        XCTAssertTrue(app.staticTexts["Daily challenge"].exists)
        XCTAssertTrue(app.staticTexts["Skill mastery"].exists)
        app.buttons["Ear training settings"].tap()
        XCTAssertTrue(app.navigationBars["Ear Training Settings"].waitForExistence(timeout: 2))
        app.buttons["10 questions"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["0 of 10 questions"].waitForExistence(timeout: 2))
    }

    func testAchievementPopupAndInteractiveDetails() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-reset-ear-training", "--ui-testing-show-achievement"]
        app.launch()
        navigate(to: "Ear Training", in: app)
        XCTAssertTrue(app.staticTexts["ACHIEVEMENT UNLOCKED"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["First Note"].exists)
        app.buttons["Continue"].tap()
        XCTAssertFalse(app.staticTexts["ACHIEVEMENT UNLOCKED"].exists)

        let streak = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Current streak'")).firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 2))
        streak.tap()
        XCTAssertTrue(app.navigationBars["Listening Streak"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()

        app.swipeUp()
        let challenge = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Daily challenge'")).firstMatch
        XCTAssertTrue(challenge.waitForExistence(timeout: 3))
        challenge.tap()
        XCTAssertTrue(app.navigationBars["Daily Challenge"].waitForExistence(timeout: 2))
    }

    func testAnswersLockDuringPianoPlayback() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-reset-ear-training")
        app.launch()
        navigate(to: "Ear Training", in: app)
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
        let answer = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ear-answer-' ")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 2))
        app.buttons["Play"].tap()
        XCTAssertFalse(answer.isEnabled)
        XCTAssertTrue(app.buttons["Listening…"].exists)
        let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: answer)
        wait(for: [enabled], timeout: 2.5)
        XCTAssertTrue(answer.isEnabled)
    }

    func testGamesHubAndGameNavigation() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-reset-games"]
        app.launch()
        navigate(to: "Games", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["games-hub"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["harmonic-sudoku-card"].exists)
        XCTAssertTrue(app.buttons["melody-memory-card"].exists)
        app.buttons["harmonic-sudoku-card"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["harmonic-sudoku-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Every chord has its place"].exists)
        XCTAssertTrue(app.buttons["Notes"].exists)
        XCTAssertTrue(app.buttons["Hint"].exists)
    }

    func testHarmonicSudokuCompletionFlow() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-reset-games", "--ui-testing-sudoku-near-complete"]
        app.launch()
        navigate(to: "Games", in: app)
        app.buttons["harmonic-sudoku-card"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["harmonic-sudoku-screen"].waitForExistence(timeout: 5))
        let tonic = app.buttons["sudoku-value-0"]
        XCTAssertTrue(tonic.waitForExistence(timeout: 3))
        for _ in 0..<3 where !tonic.isHittable { app.swipeUp() }
        XCTAssertTrue(tonic.isHittable)
        tonic.tap()
        XCTAssertTrue(app.descendants(matching: .any)["sudoku-results"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Puzzle solved"].exists)
    }

    func testMelodyMemoryStartsWithPlaybackLocked() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-reset-games"]
        app.launch()
        navigate(to: "Games", in: app)
        app.buttons["melody-memory-card"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["melody-memory-screen"].waitForExistence(timeout: 3))
        app.buttons["start-melody-memory"].tap()
        XCTAssertTrue(app.staticTexts["Listen closely…"].waitForExistence(timeout: 2))
        let cKey = app.buttons["Play C4"]
        XCTAssertTrue(cKey.waitForExistence(timeout: 2))
        XCTAssertFalse(cKey.isEnabled)
        XCTAssertTrue(app.staticTexts["Now play it back"].waitForExistence(timeout: 4))
        XCTAssertTrue(cKey.isEnabled)
    }

    func testIPadWideLayoutsAndRotation() {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing-band-demo", "--ui-testing-reset-games", "--ui-testing-reset-ear-training"]
        app.launch()

        let splitView = app.descendants(matching: .any)["ipad-navigation-split-view"]
        guard splitView.waitForExistence(timeout: 3) else { return }

        XCTAssertTrue(app.descendants(matching: .any)["band-workspace"].waitForExistence(timeout: 4))
        assertContained(app.descendants(matching: .any)["band-featured-project"], in: app)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(splitView.waitForExistence(timeout: 3))

        navigate(to: "Songwriting", in: app)
        assertContained(app.descendants(matching: .any)["songwriting-screen"], in: app)
        navigate(to: "Jam", in: app)
        assertContained(app.descendants(matching: .any)["jam-screen"], in: app)
        navigate(to: "Ear Training", in: app)
        assertContained(app.descendants(matching: .any)["ear-training-screen"], in: app)
        navigate(to: "Visualizer", in: app)
        assertContained(app.descendants(matching: .any)["visualizer-screen"], in: app)
        navigate(to: "Games", in: app)
        assertContained(app.descendants(matching: .any)["games-hub"], in: app)
        XCTAssertTrue(app.buttons["harmonic-sudoku-card"].isHittable)
        XCTAssertTrue(app.buttons["melody-memory-card"].isHittable)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(splitView.waitForExistence(timeout: 3))
    }

    private func revealNavigation(in app: XCUIApplication) {
        if app.buttons["sidebar-Songwriting"].exists { return }
        if app.buttons["Jam"].exists && !app.buttons["Open navigation menu"].exists { return }
        let menu = app.buttons["Open navigation menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        menu.tap()
    }

    private func navigate(to destination: String, in app: XCUIApplication) {
        let visibleItem = app.buttons[destination]
        if visibleItem.exists && visibleItem.isHittable && !app.buttons["Open navigation menu"].exists {
            visibleItem.tap()
            return
        }
        let sidebar = app.buttons["sidebar-\(destination)"]
        if sidebar.waitForExistence(timeout: 1) {
            sidebar.tap()
            return
        }
        revealNavigation(in: app)
        XCTAssertTrue(visibleItem.waitForExistence(timeout: 3))
        visibleItem.tap()
    }

    private func assertContained(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 4))
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(element.frame))
    }
}
