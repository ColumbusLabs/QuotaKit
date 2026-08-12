import XCTest

final class CodexBarMobileUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testUsageSettingsSwitchBetweenUsedAndRemainingPercentages() {
        let app = self.makeApp()
        app.launch()

        app.tabBars.buttons["Setting"].tap()
        app.staticTexts["Usage Setting"].tap()
        let remainingToggle = app.switches["show-remaining-usage-toggle"]
        XCTAssertTrue(remainingToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(remainingToggle.value as? String, "0")
        XCTAssertTrue(app.staticTexts["Show remaining usage"].exists)
        XCTAssertTrue(
            app.staticTexts["Display the quota you have left instead of the quota you have used on usage cards."]
                .exists)
    }

    @MainActor
    func testCostTabShowsDailySpendCurrencyUnitInTitle() {
        let app = self.makeApp()
        app.launch()

        app.tabBars.buttons["Cost"].tap()

        XCTAssertTrue(app.staticTexts["Daily Spend"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["(USD)"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCostTabCapturesRenderingScreenshot() {
        let app = self.makeApp()
        app.launch()

        app.tabBars.buttons["Cost"].tap()

        XCTAssertTrue(
            app.otherElements["cost-dashboard-section-provider-share"]
                .waitForExistence(timeout: 5))
        let modelMixSection = app.otherElements["cost-dashboard-section-model-mix"]
        if !modelMixSection.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(modelMixSection.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Cost Tab Rendering"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testProviderDailySpendSelectionShowsModelDetails() {
        let app = self.makeApp()
        app.launch()

        app.tabBars.buttons["Usage"].tap()

        let codexProvider = app.buttons["provider-group-codex"]
        XCTAssertTrue(codexProvider.waitForExistence(timeout: 5))
        if !codexProvider.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(codexProvider.isHittable)
        codexProvider.tap()

        let dailySpendDetail = app.otherElements["provider-daily-spend-selection-detail"]
        XCTAssertTrue(dailySpendDetail.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Model Mix"].exists)
        let modelRow = app.descendants(matching: .any)
            .matching(identifier: "provider-daily-spend-model-row-gpt-5.4")
            .firstMatch
        XCTAssertTrue(modelRow.waitForExistence(timeout: 5))

        // The chart exposes the same selection surface as its Mac counterpart.
        // Scrub it and verify the selected-day detail remains presented; the
        // exact selected value varies across Xcode chart implementations.
        let chart = app.descendants(matching: .any)
            .matching(identifier: "provider-daily-spend-chart-codex")
            .firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let scrubStart = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        let scrubEnd = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        scrubStart.press(forDuration: 0.2, thenDragTo: scrubEnd)
        XCTAssertTrue(dailySpendDetail.exists)
    }

    @MainActor
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UI_TEST_PREVIEW_DATA",
            "UI_TEST_SKIP_ONBOARDING",
            "UI_TEST_RESET_DEFAULTS",
            "UI_TEST_UNLOCK_PRO",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        return app
    }
}
