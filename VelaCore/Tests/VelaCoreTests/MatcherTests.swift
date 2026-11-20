import XCTest
@testable import VelaCore

final class MatcherTests: XCTestCase {
    func testTolls() {
        let json = #"{"edges":[{"names":["A5"],"length":1.2,"toll":false},{"names":["M6 Toll"],"length":0.4,"toll":true},{"names":["M6 Toll"],"length":3.0,"toll":true},{"names":["A38"],"length":2.0},{"length":0.02,"toll":true},{"names":["A38"],"length":1.0}]}"#
        // The M6 Toll once; 20 m of toll mark at a junction is nothing.
        XCTAssertEqual(Valhalla.parseTolls(Data(json.utf8)), ["M6 Toll"])
        XCTAssertEqual(Valhalla.parseTolls(Data(#"{"edges":[{"length":0.3,"toll":true}]}"#.utf8)), ["A toll road"])
        XCTAssertEqual(Valhalla.parseTolls(Data(#"{"edges":[{"names":["A33"],"length":2.0}]}"#.utf8)), [])
    }

    func testHere() {
        let json = #"{"edges":[{"names":["High Street"],"speed_limit":48},{"names":["A33","Bassett Avenue"],"speed_limit":30}]}"#
        let h = Valhalla.parseHere(Data(json.utf8), at: LatLng(50.93, -1.40))
        XCTAssertEqual(h?.road, "Bassett Avenue")
        XCTAssertEqual(h?.ref, "A33")
        // "30" with no unit in Britain is 30 mph.
        XCTAssertEqual(h?.kmh ?? 0, 30 * 1.609344, accuracy: 0.01)
        XCTAssertEqual(Valhalla.parseHere(Data(#"{"edges":[{"names":["A3(M)"]}]}"#.utf8), at: LatLng(50.9, -1.0))?.ref, "A3(M)")
        XCTAssertNil(Valhalla.parseHere(Data(#"{"edges":[]}"#.utf8), at: LatLng(50.9, -1.0)))
    }

    func testCruiseCameras() {
        let here = LatLng(50.9000, -1.4000)
        // Driving north at 30 mph (13.4 m/s): warn from 250 m.
        let ahead = RoadCamera(id: 1, kind: .speed, location: LatLng(50.9020, -1.4000))
        let far = RoadCamera(id: 2, kind: .speed, location: LatLng(50.9060, -1.4000))
        let side = RoadCamera(id: 3, kind: .speed, location: LatLng(50.9015, -1.3985))
        let behind = RoadCamera(id: 4, kind: .speed, location: LatLng(50.8985, -1.4000))
        var otherWay = RoadCamera(id: 5, kind: .speed, location: LatLng(50.9010, -1.4000))
        otherWay.directions = [180]
        let plate = RoadCamera(id: 6, kind: .plate, location: LatLng(50.9005, -1.4000))
        let found = CruiseCameras.ahead([far, side, behind, otherWay, plate, ahead], at: here, heading: 0, speedMps: 13.4)
        XCTAssertEqual(found?.camera.id, 1)
        XCTAssertEqual(found?.meters ?? 0, 222, accuracy: 3)
        XCTAssertEqual(CruiseCameras.ahead([far, ahead], at: here, heading: 0, speedMps: 31)?.camera.id, 1)
        XCTAssertNil(CruiseCameras.ahead([far, side, behind, otherWay, plate], at: here, heading: 0, speedMps: 13.4))
    }
}
