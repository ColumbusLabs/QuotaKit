import CodexBarCore
import XCTest
@testable import CodexBar

final class MenuCardCompactAccountRowTests: XCTestCase {
    func test_cachedHeadroomDoesNotHideErrorIndicator() {
        let model = MenuCardCompactAccountRowView.Model(
            label: "Stale account",
            headroomPercent: 72,
            severity: .healthy,
            constraintDetail: nil,
            hasError: true,
            showsBestBadge: false)

        XCTAssertTrue(model.showsErrorIndicator)
        XCTAssertTrue(model.showsHeadroomIndicator)
        XCTAssertEqual(model.headroomLabel, "72%")
    }
}
