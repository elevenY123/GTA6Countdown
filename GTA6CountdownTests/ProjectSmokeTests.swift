import XCTest
@testable import GTA6Countdown

final class ProjectSmokeTests: XCTestCase {
    func testRootTabDefinesStableIdentifiers() {
        XCTAssertEqual(RootTab.allCases, [.home, .news, .map])
        XCTAssertEqual(RootTab.home.rawValue, "home")
        XCTAssertEqual(RootTab.news.rawValue, "news")
        XCTAssertEqual(RootTab.map.rawValue, "map")
    }
}
