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

        let codexProvider = app.otherElements["provider-group-codex"]
        XCTAssertTrue(codexProvider.waitForExistence(timeout: 5))
        codexProvider.tap()

        let dailySpendDetail = app.otherElements["provider-daily-spend-selection-detail"]
        XCTAssertTrue(dailySpendDetail.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Model Mix"].exists)
        XCTAssertTrue(
            app.otherElements["provider-daily-spend-model-row-gpt-5.4"]
                .waitForExistence(timeout: 5))

        // The chart exposes the same selection surface as its Mac counterpart:
        // a tap/scrub updates the selected-day detail card. The card is
        // already visible for the latest day, so this coordinate tap verifies
        // the chart is present and hit-testable without depending on a
        // particular date label in preview data.
        let chart = app.otherElements["provider-daily-spend-chart-codex"]
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let initialDetailValue = dailySpendDetail.value as? String
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).tap()
        XCTAssertTrue(dailySpendDetail.exists)
        XCTAssertNotEqual(initialDetailValue, dailySpendDetail.value as? String)
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
