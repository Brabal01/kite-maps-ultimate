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

    func testZoomSettingAndLook() {
        let v = NavZoom.View(across: 700, pitch: 50)
        XCTAssertEqual(v.applying(.closer, .tilted).across, 490, accuracy: 0.1)
        XCTAssertEqual(v.applying(.wider, .tilted).across, 980, accuracy: 0.1)
        XCTAssertEqual(v.applying(.normal, .tilted), v)
        XCTAssertEqual(v.applying(.normal, .flat).pitch, 0)
        XCTAssertEqual(v.applying(.normal, .north).pitch, 0)
        XCTAssertEqual(MapLook.tilted.next, .flat)
        XCTAssertEqual(MapLook.flat.next, .north)
        XCTAssertEqual(MapLook.north.next, .tilted)
    }

    func testNextLimitDrop() {
        var r = Route(mode: .drive, polyline: [], distanceMeters: 5000, typicalSeconds: 300, trafficSeconds: nil,
                      summary: nil, maneuvers: [], source: "osm")
        r.speedLimits = [SpeedLimit(startMeters: 0, kmh: 96.6), SpeedLimit(startMeters: 1000, kmh: 48.3),
                         SpeedLimit(startMeters: 2000, kmh: nil), SpeedLimit(startMeters: 3000, kmh: 32.2),
                         SpeedLimit(startMeters: 4000, kmh: 64.4)]
        // 60 to 30 in 300 m: shown.
        XCTAssertEqual(r.nextLimitDrop(at: 700, within: 400)?.kmh, 48.3)
        // Too far yet.
        XCTAssertNil(r.nextLimitDrop(at: 100, within: 400))
        // Into an unmapped stretch: nothing guessed.
        XCTAssertNil(r.nextLimitDrop(at: 1800, within: 400))
        // From an unmapped stretch: we don't know it's a drop.
        XCTAssertNil(r.nextLimitDrop(at: 2800, within: 400))
        // Going up: nothing.
        XCTAssertNil(r.nextLimitDrop(at: 3800, within: 400))
        XCTAssertEqual(NavZoom.limitHeadsUp(speed: 31.3), 469.5, accuracy: 0.1)
        XCTAssertEqual(NavZoom.limitHeadsUp(speed: 5), 200)
    }
}
