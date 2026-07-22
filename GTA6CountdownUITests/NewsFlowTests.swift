import XCTest

final class NewsFlowTests: XCTestCase {
    func testNewsTabExposesDeterministicFixtureContent() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-news-fixture"]
        app.launch()

        app.tabBars.buttons["新闻"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["root-screen-news"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["news-pinned-official"]
                .waitForExistence(timeout: 3)
        )
    }

    func testPinnedOfficialCardOpensSummaryOnlyDetailWithOriginalButton() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-news-fixture"]
        app.launch()
        app.tabBars.buttons["新闻"].tap()

        let pinned = app.descendants(matching: .any)["news-pinned-official"]
        XCTAssertTrue(pinned.waitForExistence(timeout: 3))
        pinned.tap()

        XCTAssertTrue(app.descendants(matching: .any)["news-detail-rockstar-1"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["news-detail-summary"].label, "来自 Rockstar Games 的官方更新。")
        XCTAssertTrue(app.buttons["news-read-original"].exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }
}
