import XCTest

final class RootNavigationTests: XCTestCase {
    private enum Appearance: String, CaseIterable {
        case light = "Light"
        case dark = "Dark"

        var deviceAppearance: XCUIDevice.Appearance {
            switch self {
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .light
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
    }

    func testRootTabsAreAccessibleAndSelectable() {
        app.launch()

        let home = app.buttons["root-tab-home"]
        let news = app.buttons["root-tab-news"]
        let map = app.buttons["root-tab-map"]

        XCTAssertTrue(home.waitForExistence(timeout: 2))
        XCTAssertTrue(news.exists)
        XCTAssertTrue(map.exists)
        XCTAssertEqual(home.label, "主页")
        XCTAssertEqual(news.label, "新闻")
        XCTAssertEqual(map.label, "地图")

        news.tap()
        XCTAssertTrue(news.isSelected)
        map.tap()
        XCTAssertTrue(map.isSelected)
        home.tap()
        XCTAssertTrue(home.isSelected)
    }

    func testRootTabsRemainAccessibleAtLargestDynamicTypeSize() {
        for appearance in Appearance.allCases {
            launch(appearance: appearance, largestDynamicType: true)
            assertRootTabLayout(file: #filePath, line: #line)
            attachScreenshot(named: "root-tabs-\(appearance.rawValue.lowercased())-accessibility-xxxl")
            app.terminate()
        }
    }

    func testRootTabsLayoutInLightAndDarkAppearances() {
        for appearance in Appearance.allCases {
            launch(appearance: appearance, largestDynamicType: false)
            assertRootTabLayout(file: #filePath, line: #line)
            attachScreenshot(named: "root-tabs-\(appearance.rawValue.lowercased())-default-type")
            app.terminate()
        }
    }

    private func launch(appearance: Appearance, largestDynamicType: Bool) {
        XCUIDevice.shared.appearance = appearance.deviceAppearance
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)",
            "-UIUserInterfaceStyle", appearance.rawValue
        ]
        if largestDynamicType {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
            ]
        }
        app.launch()
    }

    private func assertRootTabLayout(
        file: StaticString,
        line: UInt
    ) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 2), file: file, line: line)
        let expectedTabs = [
            ("root-tab-home", "主页"),
            ("root-tab-news", "新闻"),
            ("root-tab-map", "地图")
        ]
        let tabs = expectedTabs.map { expected -> XCUIElement in
            let (identifier, label) = expected
            let tab = app.buttons[identifier]
            XCTAssertTrue(tab.waitForExistence(timeout: 2), file: file, line: line)
            XCTAssertTrue(tab.isHittable, file: file, line: line)
            XCTAssertFalse(tab.label.isEmpty, file: file, line: line)
            XCTAssertEqual(tab.label, label, file: file, line: line)
            XCTAssertGreaterThanOrEqual(tab.frame.width, 44, file: file, line: line)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44, file: file, line: line)
            XCTAssertTrue(
                window.frame.insetBy(dx: -0.5, dy: -0.5).contains(tab.frame),
                "Tab \(label) must remain within the window",
                file: file,
                line: line
            )
            return tab
        }

        for leftIndex in tabs.indices {
            for rightIndex in tabs.indices where rightIndex > leftIndex {
                XCTAssertFalse(
                    tabs[leftIndex].frame.intersects(tabs[rightIndex].frame),
                    "Root tab frames must not overlap",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
