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

    func testLineAvoiding() {
        // Two legs (through a stop): joined without the stop twice.
        let json = #"{"trip":{"legs":[{"shape":"_aua`B~jmtA_pR~oR"},{"shape":"_rhb`B~{`uA_pR~oR"}]}}"#
        let line = Valhalla.parseLine(Data(json.utf8))
        XCTAssertEqual(line?.count, 3)
        XCTAssertEqual(line?.last?.lat ?? 0, 50.92, accuracy: 1e-6)
        XCTAssertEqual(line?.last?.lng ?? 0, -1.42, accuracy: 1e-6)
        XCTAssertNil(Valhalla.parseLine(Data(#"{"error":"No path could be found"}"#.utf8)))
    }

    func testDestination() {
        let a = LatLng(50.9, -1.4)
        let p = Geo.destination(a, bearing: 90, meters: 100)
        XCTAssertEqual(a.distance(to: p), 100, accuracy: 1)
        XCTAssertEqual(Geo.bearing(a, p), 90, accuracy: 0.5)
    }

    func testGoogleReviews() {
        XCTAssertEqual(GoogleReviews.ids("0x48738c3e0a3b4c4f:0x1a2b")?.0, String(UInt64("48738c3e0a3b4c4f", radix: 16)!))
        XCTAssertEqual(GoogleReviews.ids("0x48738c3e0a3b4c4f:0x1a2b")?.1, "6699")
        XCTAssertNil(GoogleReviews.ids("ChIJ123"))
        let body = ")]}'\n" + #"[null,null,[[[null,"Sam P"],"2 months ago",null,"Great coffee, friendly staff.",5],[[null,"Jo"],"a week ago",null,null,4],[[null,"Al"],"a year ago",null,"Slow.",2]]]"#
        let r = GoogleReviews.parse(body)
        XCTAssertEqual(r?.count, 2)
        XCTAssertEqual(r?.first?.author, "Sam P")
        XCTAssertEqual(r?.first?.rating, 5)
        XCTAssertEqual(r?.first?.when, "2 months ago")
        XCTAssertEqual(r?.last?.text, "Slow.")
        XCTAssertNil(GoogleReviews.parse("<html>"))
    }

    func testDetours() {
        let d = OSRM.parseDetours(Data(#"{"code":"Ok","durations":[[100,200,300,500],[0,10,260,999],[10,0,999,400]]}"#.utf8), count: 2)
        XCTAssertEqual(d?[0] ?? 0, 60, accuracy: 0.01)
        XCTAssertEqual(d?[1] ?? 0, 100, accuracy: 0.01)
        XCTAssertNil(OSRM.parseDetours(Data(#"{"code":"Ok","durations":[[null,200,300,500],[0,10,260,999],[10,0,999,400]]}"#.utf8), count: 2)?[0] ?? nil)
        XCTAssertNil(OSRM.parseDetours(Data(#"{"code":"NoTable"}"#.utf8), count: 2))
    }

    func testArrivalHelp() {
        let here = LatLng(50.9000, -1.4000)
        let parks = ArrivalHelp.parseParking(Data(#"{"elements":[{"type":"way","id":1,"center":{"lat":50.9010,"lon":-1.4000},"tags":{"amenity":"parking","name":"West Quay Car Park","fee":"yes","capacity":"1200","parking":"multi-storey"}},{"type":"node","id":2,"lat":50.9001,"lon":-1.4000,"tags":{"amenity":"parking","access":"private"}},{"type":"node","id":3,"lat":50.9002,"lon":-1.4000,"tags":{"amenity":"parking","parking":"street_side"}},{"type":"node","id":4,"lat":50.9003,"lon":-1.4000,"tags":{"amenity":"parking","capacity":"6"}}]}"#.utf8), near: here)
        XCTAssertEqual(parks?.map(\.id), ["way1", "node4"])
        XCTAssertEqual(parks?.first?.fee, true)
        XCTAssertEqual(parks?.first?.spaces, 1200)
        XCTAssertEqual(parks?.first?.kind, "Multi-storey")
        XCTAssertEqual(ArrivalHelp.parseEntrance(Data(#"{"elements":[{"type":"node","id":9,"lat":50.9005,"lon":-1.4000,"tags":{"entrance":"main"}},{"type":"node","id":10,"lat":50.9001,"lon":-1.4000,"tags":{"entrance":"main","access":"private"}}]}"#.utf8), near: here)?.lat ?? 0, 50.9005, accuracy: 1e-6)
        XCTAssertNil(ArrivalHelp.parseEntrance(Data(#"{"elements":[{"type":"node","id":9,"lat":50.9001,"lon":-1.4000,"tags":{}}]}"#.utf8), near: here))
        XCTAssertTrue(ArrivalHelp.isBigPlace("Shopping mall"))
        XCTAssertFalse(ArrivalHelp.isBigPlace("Cafe"))
    }

    func testCleanAirZones() {
        func names(_ line: [LatLng], clean: Bool = false) -> [String] { CleanAirZones.on(line, cleanCar: clean).map(\.name) }
        // Into central London from outside: the ULEZ, and nothing once the car meets the rules.
        XCTAssertEqual(names([LatLng(51.60, -0.60), LatLng(51.5074, -0.1278)]), ["London ULEZ"])
        XCTAssertEqual(names([LatLng(51.60, -0.60), LatLng(51.5074, -0.1278)], clean: true), [])
        XCTAssertEqual(CleanAirZones.on([LatLng(51.5074, -0.1278), LatLng(51.5080, -0.1270)], cleanCar: false).first?.zone, true)
        // Oxford's zone charges every car that isn't electric.
        XCTAssertEqual(names([LatLng(51.70, -1.30), LatLng(51.7527, -1.2590)], clean: true), ["Oxford Zero Emission Zone"])
        XCTAssertEqual(names([LatLng(55.90, -4.40), LatLng(55.8611, -4.2502)]), ["Glasgow Low Emission Zone"])
        XCTAssertEqual(names([LatLng(52.55, -1.80), LatLng(52.4797, -1.9026)]), ["Birmingham Clean Air Zone"])
        // Southampton, and a drive past London that never goes in.
        XCTAssertEqual(names([LatLng(50.90, -1.40), LatLng(50.93, -1.39)]), [])
        XCTAssertEqual(names([LatLng(51.60, -0.60), LatLng(51.70, -0.55)]), [])
    }
}
