import XCTest
@testable import VelaCore

final class WazeCameraTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            out.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    private func u32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }

    /** A piece of Waze's map as its server sends it, holding [cameras] as table 25. */
    private func piece(tile: Int, cameras: [UInt8]) -> Data {
        var tables = [[UInt8]](repeating: [], count: 46)
        tables[1] = Array("A27 - Bassett Green Rd".utf8) + [0]
        tables[25] = cameras
        tables[26] = u32(tile) + u32(0) + u32(1_793_783_731)
        let bits = 2, mask = (1 << bits) - 1
        var ends: [UInt8] = [], body: [UInt8] = []
        for t in tables {
            if !t.isEmpty {
                while body.count & mask != 0 { body.append(0) }
                body += t
            }
            ends += u32(body.count)
        }
        let plain = u32(tables.count) + u32(bits) + ends + body
        let deflated = [UInt8](try! (Data(plain) as NSData).compressed(using: .zlib) as Data)
        let packed: [UInt8] = [0x78, 0x9C] + deflated + [0, 0, 0, 0]
        let lead: [UInt8] = bytes("2e2e2e2e000000011329e29e00000000000010b2")
        return Data(lead + Array("WZDF".utf8) + bytes("0100000000000300") + u32(packed.count) + u32(plain.count) + packed)
    }

    /** The M27 at junction 5 as Waze sent it on 2026-11-15: a camera each way, both 112 km/h (70 mph). */
    private let j5 = "2ef0eaff5d6d090346000270629e00007ff0eaffa36c0903fa00027099190000"

    func testTheSpeedCamerasInAPieceOfWazesMap() {
        // After the two real ones: a red light camera (kind 3), and a speed camera placed far outside the piece.
        let extra = "30f0eaff606d0903000003000100000000000000000000004600027002000000"
        let cams = WazeCameras.parse(piece(tile: 321512094, cameras: bytes(j5 + extra)))
        XCTAssertEqual(cams?.count, 2)
        XCTAssertEqual(cams?[0].location.lat ?? 0, 50.949469, accuracy: 0.000001)
        XCTAssertEqual(cams?[0].location.lng ?? 0, -1.380306, accuracy: 0.000001)
        XCTAssertEqual(cams?[1].location.lat ?? 0, 50.949283, accuracy: 0.000001)
        XCTAssertEqual(cams?.map(\.kind), [.speed, .speed])
        XCTAssertEqual(cams?.map(\.maxspeedKmh), [112, 112])
        // Numbered below zero, so they never clash with OpenStreetMap's, and each its own.
        XCTAssertTrue(cams?.allSatisfy { WazeCameras.isWaze($0) } ?? false)
        XCTAssertEqual(Set(cams?.map(\.id) ?? []).count, 2)
        // No direction is taken from Waze: its meaning isn't certain, so the camera counts both ways.
        XCTAssertNil(cams?[0].directions)
    }

    func testAPieceWithoutCamerasAndSomethingThatIsntAPiece() {
        XCTAssertEqual(WazeCameras.parse(piece(tile: 321512093, cameras: []))?.count, 0)
        XCTAssertNil(WazeCameras.parse(Data("<html>busy</html>".utf8)))
        XCTAssertNil(WazeCameras.parse(Data()))
    }

    func testPieceNumbers() {
        XCTAssertEqual(WazeCameras.tileId(LatLng(50.9494996, -1.3803431)), 321512094)
        XCTAssertEqual(WazeCameras.tileId(LatLng(50.9300, -1.3855)), 321512093)
        // A route's pieces start where it starts, and take in the ones it only brushes past.
        let ids = WazeCameras.tileIds(along: [LatLng(50.9405, -1.3880), LatLng(50.9405, -1.3803)])
        XCTAssertEqual(ids.first, WazeCameras.tileId(LatLng(50.9405, -1.3880)))
        XCTAssertTrue(ids.contains(321512094))
        XCTAssertTrue(ids.contains(321512093))
        XCTAssertEqual(Set(ids).count, ids.count)
        // A map view: a town's worth is fine, a county's isn't asked for.
        XCTAssertEqual(WazeCameras.tileIds(south: 50.911, west: -1.389, north: 50.925, east: -1.371).count, 4)
        XCTAssertTrue(WazeCameras.tileIds(south: 50.7, west: -1.6, north: 51.1, east: -1.0).isEmpty)
    }

    func testACameraBothMapsHoldShowsOnce() {
        let osm = RoadCamera(id: 7, kind: .speed, location: LatLng(50.9494996, -1.3803431), maxspeedKmh: 112, average: true)
        let plate = RoadCamera(id: 8, kind: .plate, location: LatLng(50.9300, -1.3855))
        let same = RoadCamera(id: -1, kind: .speed, location: LatLng(50.949469, -1.380306), maxspeedKmh: 112)
        let new = RoadCamera(id: -2, kind: .speed, location: LatLng(50.92021, -1.39097), maxspeedKmh: 64)
        let twin = RoadCamera(id: -3, kind: .speed, location: LatLng(50.92021, -1.39096), maxspeedKmh: 64)
        // A number plate camera at the same spot is a different thing: Waze's speed camera stays.
        let byPlate = RoadCamera(id: -4, kind: .speed, location: LatLng(50.9300, -1.3855), maxspeedKmh: 48)
        let all = WazeCameras.merge([osm, plate], waze: [same, new, twin, byPlate])
        XCTAssertEqual(all.map(\.id), [7, 8, -2, -4])
        // Mixing twice adds nothing twice.
        XCTAssertEqual(WazeCameras.merge(all, waze: [same, new, twin, byPlate]).map(\.id), [7, 8, -2, -4])
        XCTAssertEqual(WazeCameras.merge([osm], waze: []).map(\.id), [7])
    }

    func testCamerasAreKeptOnThePhoneForAWeek() {
        let store = WazeCameraStore(file: nil)
        let now = Date()
        XCTAssertEqual(store.stale([1, 2, 3], now: now), [1, 2, 3])
        let cam = RoadCamera(id: -2, kind: .speed, location: LatLng(50.92021, -1.39097), maxspeedKmh: 64)
        let far = RoadCamera(id: -5, kind: .speed, location: LatLng(50.9495, -1.3803), maxspeedKmh: 112)
        store.put([1: [cam], 2: [far]], blank: [3], now: now)
        XCTAssertEqual(store.version, 1)
        XCTAssertEqual(store.stale([1, 2, 3], now: now), [])
        // A piece that came back blank is asked for again the next day; a read one after a week.
        XCTAssertEqual(store.stale([1, 2, 3], now: now.addingTimeInterval(2 * 86_400)), [3])
        XCTAssertEqual(store.stale([1, 2, 3], now: now.addingTimeInterval(8 * 86_400)), [1, 2, 3])
        XCTAssertEqual(Set(store.known().map(\.id)), [-2, -5])
        // Thomas Lewis Way, heading into Southampton: only the camera on it.
        let line = [LatLng(50.9300, -1.3850), LatLng(50.9202, -1.3910), LatLng(50.91894, -1.39534)]
        XCTAssertEqual(store.known(along: line).map(\.id), [-2])
    }

    func testWazeCamerasJoinWhatTheRoadCacheKnows() {
        let line = [LatLng(50.9300, -1.3850), LatLng(50.9202, -1.3910), LatLng(50.91894, -1.39534)]
        let real = WazeCameras.shared
        WazeCameras.shared = WazeCameraStore(file: nil)
        defer { WazeCameras.shared = real }
        WazeCameras.shared.put([999_999_001: [RoadCamera(id: -77, kind: .speed, location: LatLng(50.92021, -1.39097), maxspeedKmh: 64)]])
        let cache = RoadCache(file: nil)
        XCTAssertEqual(cache.along(line).cameras.map(\.id), [])
        WazeCameras.enabled = true
        defer { WazeCameras.enabled = false }
        XCTAssertEqual(cache.along(line).cameras.map(\.id), [-77])
    }
}
