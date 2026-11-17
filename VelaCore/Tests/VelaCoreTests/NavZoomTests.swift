import XCTest
@testable import VelaCore

final class NavZoomTests: XCTestCase {
    let mph30 = 13.4
    let mph70 = 31.3

    func testNormalBetweenTurns() {
        let v = NavZoom.view(speed: mph30, toNext: 500, next: .turnLeft, driving: true)
        XCTAssertEqual(v.across, 702, accuracy: 1)
        XCTAssertEqual(v.pitch, 50)
    }

    func testPullsBackOnLongStretch() {
        let v = NavZoom.view(speed: mph70, toNext: 5000, next: .rampLeft, driving: true)
        XCTAssertEqual(v.across, 1549, accuracy: 1)
        XCTAssertEqual(v.pitch, 55)
    }

    func testZoomsInBeforeTurn() {
        let far = NavZoom.view(speed: mph30, toNext: 300, next: .turnLeft, driving: true)
        let mid = NavZoom.view(speed: mph30, toNext: 180, next: .turnLeft, driving: true)
        let close = NavZoom.view(speed: mph30, toNext: 50, next: .turnLeft, driving: true)
        XCTAssertTrue(far.across > mid.across && mid.across > close.across)
        XCTAssertEqual(close.across, 330, accuracy: 0.1)
        XCTAssertEqual(close.pitch, 35)
    }

    func testMotorwayExitStaysFurtherOut() {
        let v = NavZoom.view(speed: mph70, toNext: 50, next: .rampLeft, driving: true)
        XCTAssertEqual(v.across, mph70 * 14, accuracy: 0.1)
    }

    func testNoCloseInForStraightOrArrive() {
        XCTAssertEqual(NavZoom.view(speed: mph30, toNext: 100, next: .straight, driving: true).pitch, 50)
        XCTAssertEqual(NavZoom.view(speed: mph30, toNext: 100, next: .arrive, driving: true).pitch, 50)
    }

    func testRoundaboutStaysClose() {
        XCTAssertEqual(NavZoom.view(speed: mph30, toNext: 50, next: .roundabout, driving: true).across, 330, accuracy: 0.1)
        XCTAssertLessThanOrEqual(NavZoom.view(speed: mph30, toNext: 340, next: .roundabout, driving: true).across, 380)
    }

    func testWalking() {
        XCTAssertEqual(NavZoom.view(speed: 1.4, toNext: 50, next: .turnLeft, driving: false), NavZoom.View(across: 300, pitch: 50))
    }
}
