import Foundation
import VelaCore

// Live check of the Google search and parser, run by the build workflow.
// Usage: swift run vela-probe "pizza" 40.7484 -73.9857
// Line by line, so a step cut off by its time limit still shows what it printed.
setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
if args.count > 1, args[1] == "google" {
    await googleCheck()
    exit(0)
}
if args.count > 1, args[1] == "audit" {
    await navAudit()
    exit(0)
}
if args.count > 1, args[1] == "incidents" {
    await googleIncidents()
    exit(0)
}
if args.count > 1, args[1] == "wazert" {
    // Live Waze reports through the app's own protocol (WazeLive), around Southampton, the M27 and London.
    let places: [(String, LatLng)] = [("Southampton (Bursledon Rd)", LatLng(50.905, -1.34)), ("Eastleigh", LatLng(50.97, -1.35)),
                                       ("M27 J5-J7", LatLng(50.92, -1.30)), ("Central London", LatLng(51.515, -0.13)),
                                       ("West London", LatLng(51.50, -0.25)),
                                       ("Southampton (Thomas Lewis Way)", LatLng(50.928, -1.388)), ("M3 J11-J12", LatLng(51.03, -1.33))]
    // Count everything Waze sends, to see whether it also carries fixed speed cameras.
    WazeLive.census = WazeCensus()
    var police = 0
    for (name, p) in places {
        let b = WazeLive.box(around: p, meters: 6_000)
        let found = await WazeLive.shared.alerts(boxes: [b], near: p)
        let s = WazeLive.lastStatus
        print("\(name): \(found == nil ? "FAILED (code \(s?.code ?? 0))" : "\(s?.summary ?? "nothing")")")
        for a in (found ?? []).filter({ $0.kind == .police }).prefix(8) {
            let mins = Int(Date().timeIntervalSince(a.reportedAt) / 60)
            print(String(format: "   %@ · %@ · %.5f,%.5f · %d min ago · %d thumbs", a.title, a.street ?? "?", a.location.lat, a.location.lng, mins, a.thumbsUp))
        }
        police += (found ?? []).filter { $0.kind == .police }.count
    }
    print("police in all: \(police)")
    let streets = await WazeLive.shared.alerts(boxes: [WazeLive.box(around: places[0].1, meters: 6_000)], near: places[0].1) ?? []
    print("with a street name: \(streets.filter { $0.street != nil }.count) of \(streets.count), e.g. \(streets.compactMap(\.street).prefix(5))")
    print("data used: \(WazeLive.bytes / 1024) KB")
    wazeCensusReport()
    // Does Waze send its fixed cameras (report type 11, or 103 "permanent hazard") when the map is
    // zoomed in close on one? Small boxes round cameras known to be real, at several zooms.
    let cams: [(String, LatLng)] = [("Northam Bridge", LatLng(50.9156326, -1.3851174)), ("M27 J5", LatLng(50.9494996, -1.3803431)),
                                     ("M27 J7", LatLng(50.9352479, -1.3411425)), ("Thomas Lewis Way", LatLng(50.9300, -1.3855)),
                                     ("M3 J9", LatLng(51.0727903, -1.2919975))]
    for scale in [67186, 20000, 5000, 1500, 400] {
        WazeLive.mapScale = scale
        for meters in [1500.0, 400.0] {
            WazeLive.census = WazeCensus()
            var asked = 0
            for (_, p) in cams {
                if await WazeLive.shared.alerts(boxes: [WazeLive.box(around: p, meters: meters)], near: p) != nil { asked += 1 }
            }
            let c = WazeLive.census ?? WazeCensus()
            let types = c.alertTypes.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: " ")
            let other = c.places.map { "\($0.key)x\($0.value.count)" }.joined(separator: " ")
            print("zoom \(scale), boxes of \(Int(meters)) m, \(asked) of \(cams.count) answered · elements \(c.elements.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: " ")) · report types: \(types.isEmpty ? "none" : types) · other places: \(other.isEmpty ? "none" : other)")
            for (path, pts) in c.places {
                let near: [String] = pts.prefix(12).map { p in
                    let best = cams.map { ($0.0, $0.1.distance(to: p)) }.min { $0.1 < $1.1 }
                    return String(format: "%.5f,%.5f (%.0f m from %@)", p.lat, p.lng, best?.1 ?? -1, best?.0 ?? "?")
                }
                print("   \(path): " + near.joined(separator: " · "))
            }
            for (n, list) in c.shapes.sorted(by: { $0.key < $1.key }) where ![2150, 2203, 2305, 2569, 2667].contains(n) {
                for text in list { print("   element \(n): \(text)") }
            }
            for key in c.alertTypes.keys where key.hasPrefix("11/") || key.hasPrefix("103/") || key.hasSuffix("/5001") {
                print("   CAMERA TYPE \(key): " + (c.alertPlaces[key] ?? []).prefix(20).map { String(format: "%.5f,%.5f", $0.lat, $0.lng) }.joined(separator: " "))
            }
        }
    }
    WazeLive.mapScale = 67186
    WazeLive.census = nil
    // Waze's own map pieces (the ones SABRE reads) hold fixed cameras in table 25. List every one
    // along Thomas Lewis Way and round the other known cameras.
    var seen = Set<Int>()
    var spots: [(String, LatLng)] = []
    for i in 0...24 { spots.append(("Thomas Lewis Way", LatLng(50.91894 + (50.94056 - 50.91894) * Double(i) / 24, -1.39534 + (-1.37789 + 1.39534) * Double(i) / 24))) }
    spots += cams + [("M27 J7 b", LatLng(50.935568, -1.3387029)), ("M27 J8", LatLng(50.9101758, -1.3184896)), ("Bitterne Rd", LatLng(50.9156984, -1.3614169))]
    var tiles = 0, total = 0
    for (name, p) in spots {
        for (dLat, dLng) in name == "Thomas Lewis Way" ? [(0.0, 0.0), (0.0, 0.01), (0.0, -0.01)] : [(0.0, 0.0)] {
            let q = LatLng(p.lat + dLat, p.lng + dLng)
            guard let t = await WazeLive.shared.mapTile(q), seen.insert(t.id).inserted else { continue }
            tiles += 1
            let found = wazeTileCameras(t.data)
            total += found.count
            print("TILECAMS \(name) tile \(t.id) (HTTP \(t.code), \(t.data.count) bytes): \(found.count)")
            for c in found {
                let line = (0...24).map { LatLng(50.91894 + (50.94056 - 50.91894) * Double($0) / 24, -1.39534 + (-1.37789 + 1.39534) * Double($0) / 24) }
                let road = line.map { $0.distance(to: c.at) }.min() ?? -1
                let cam = cams.map { $0.1.distance(to: c.at) }.min() ?? -1
                print(String(format: "   %.5f,%.5f · facing %d° · kind %d · %d km/h (%d mph) · %.0f m from Thomas Lewis Way · %.0f m from a camera the free map has", c.at.lat, c.at.lng, c.heading, c.kind, c.speed, Int((Double(c.speed) / 1.609).rounded()), road, cam))
            }
        }
    }
    print("TILECAMS total: \(total) in \(tiles) pieces, data used so far \(WazeLive.bytes / 1024) KB")
    // What happens when Waze can't be reached: a quick failure, then a pause before asking again.
    WazeLive.hostOverride = "127.0.0.1:9"
    let t = Date()
    let down = await WazeLive.shared.alerts(boxes: [WazeLive.box(around: places[0].1, meters: 6_000)], near: places[0].1)
    print(String(format: "unreachable: %@ in %.1f s, status code %d", down == nil ? "nil" : "\(down!.count) reports", Date().timeIntervalSince(t),
                 WazeLive.lastStatus?.code ?? 99))
    let again = await WazeLive.shared.alerts(boxes: [WazeLive.box(around: places[0].1, meters: 6_000)], near: places[0].1)
    print("asked again straight away: \(again == nil ? "skipped (waiting)" : "asked")")
    exit(0)
}
if args.count > 1, args[1] == "body" {
    await rawBody()
    exit(0)
}
if args.count > 1, args[1] == "limits" {
    await limitsCheck()
    exit(0)
}
if args.count > 1, args[1] == "reportsuk" {
    await ukReports()
    exit(0)
}
if args.count > 1, args[1] == "refresh" {
    await refreshCheck()
    exit(0)
}
if args.count > 1, args[1] == "route" {
    await routeCheck()
    exit(0)
}
if args.count > 1, args[1] == "roundabouts" {
    await overnightAudit()
    exit(0)
}
if args.count > 1, args[1] == "steps" {
    await stepsCompare()
    exit(0)
}
if args.count > 1, args[1] == "adoptcheck" {
    await adoptCheck()
    exit(0)
}
if args.count > 1, args[1] == "merges" {
    await mergeCheck()
    exit(0)
}
if args.count > 1, args[1] == "sv" {
    await streetViewShot()
    exit(0)
}
if args.count > 1, args[1] == "turns" {
    await turnAudit()
    exit(0)
}
if args.count > 1, args[1] == "ramps" {
    await rampAudit()
    exit(0)
}
if args.count > 1, args[1] == "rdebug" {
    await roundaboutDebug()
    exit(0)
}
if args.count > 1, args[1] == "drive" {
    await driveReplay()
    exit(0)
}
if args.count > 1, args[1] == "uk" {
    await ukRoutes()
    exit(0)
}
let query = args.count > 1 ? args[1] : "pizza"
let lat = args.count > 2 ? Double(args[2]) ?? 40.7484 : 40.7484
let lng = args.count > 3 ? Double(args[3]) ?? -73.9857 : -73.9857
let center = LatLng(lat, lng)
var exitCode: Int32 = 0

do {
    let places = try await GoogleClient.shared.search(query, center: center, spanMeters: 5_000)
    print("Google: \(places.count) results for \"\(query)\"")
    for p in places.prefix(5) {
        print("- \(p.name) | \(p.category ?? "-") | \(p.address ?? "-") | \(p.rating.map { String($0) } ?? "-") (\(p.reviewCount ?? 0)) | \(p.statusText ?? "-") | hours \(p.hours.count) | photos \(p.photoUrls.count)")
    }
    if places.isEmpty { exitCode = 2 }
} catch {
    print("Google failed: \(error)")
    exitCode = 1
}

let osm = try await Photon.search("Eiffel Tower", near: center)
print("Photon: \(osm.count) results, first: \(osm.first?.name ?? "-") | \(osm.first?.address ?? "-")")

// Directions: Davis to Sacramento airport, Google first, then the open router.
let davis = LatLng(38.5449, -121.7405), smf = LatLng(38.6951, -121.5908)
do {
    let routes = try await GoogleClient.shared.directions(from: davis, to: smf, mode: .drive)
    print("Google directions: \(routes.count) routes")
    for r in routes {
        print("- \(Int(r.distanceMeters)) m, typical \(Int(r.typicalSeconds / 60)) min, traffic \(r.trafficSeconds.map { "\(Int($0 / 60)) min" } ?? "-"), via \(r.summary ?? "-"), points \(r.polyline.count), steps \(r.maneuvers.count), spans \(r.trafficSpans.count)")
    }
    for m in routes.first?.maneuvers.prefix(4) ?? [] {
        print("  · \(m.type.rawValue) @\(Int(m.alongMeters)) m: \(m.instruction)")
    }
    if routes.isEmpty { exitCode = 3 }
} catch {
    print("Google directions failed: \(error)")
    exitCode = 3
}
let osrm = try await OSRM.route(from: davis, to: smf, mode: .drive)
print("OSRM: \(osrm.count) routes, first \(Int(osrm.first?.distanceMeters ?? 0)) m, \(osrm.first?.maneuvers.count ?? 0) steps: \(osrm.first?.maneuvers.prefix(3).map(\.instruction) ?? [])")
let merged = await Directions.routes(from: davis, to: smf, mode: .drive)
print("Merged steps on Google's line: \(merged.routes.first?.maneuvers.count ?? 0)")
for m in merged.routes.first?.maneuvers.prefix(6) ?? [] {
    print("  · \(m.type.rawValue) @\(Int(m.alongMeters)) m: \(m.instruction)")
}

// Autocomplete
do {
    let sug = try await GoogleClient.shared.suggest("pier 50", near: LatLng(38.5449, -121.7405))
    print("Google suggest: \(sug.places.count) places, \(sug.queries.count) queries; first: \(sug.places.first?.name ?? "-") | \(sug.places.first?.address ?? "-")")
} catch {
    print("Google suggest failed: \(error)")
}

// Cameras around Munich (speed) and Davis (plate readers).
let munich = await Overpass.cameras(south: 48.10, west: 11.50, north: 48.18, east: 11.62, speed: true, plate: false)
print("Overpass speed cameras near Munich: \(munich.map { "\($0.count)" } ?? "failed")")
let plates = await Overpass.cameras(south: 38.50, west: -121.80, north: 38.60, east: -121.68, speed: false, plate: true)
print("Overpass plate cameras near Davis: \(plates.map { "\($0.count)" } ?? "failed")")
if munich == nil || plates == nil {
    let q = Overpass.query(filter: "(48.10,11.50,48.18,11.62)", speed: true, plate: false)
    for ep in Overpass.endpoints {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let url = URL(string: ep + "?data=" + (q.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""))!
        var req = URLRequest(url: url)
        req.timeoutInterval = 40
        let start = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            print("  \(ep): HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0) in \(Int(Date().timeIntervalSince(start))) s, \(data.count) bytes: \(String(decoding: data.prefix(160), as: UTF8.self))")
        } catch {
            print("  \(ep): \(error.localizedDescription) after \(Int(Date().timeIntervalSince(start))) s")
        }
    }
}
let via = try? await OSRM.routeVia(merged.routes.first?.polyline ?? [], mode: .drive)
print("OSRM via Google's line: \(via.map { "\(Int($0.distanceMeters)) m, \($0.maneuvers.count) steps" } ?? "failed")")
if let via, let line = merged.routes.first?.polyline {
    let cum = Geo.cumulative(line)
    for m in via.maneuvers {
        let p = Geo.project(m.location, on: line, cumulative: cum)
        print("  · \(m.type.rawValue) \(m.instruction): along \(Int(p.along)) m, off \(Int(p.offset)) m")
    }
    print("  adopted: \(StepMerge.adopt([via], onto: line)?.count ?? 0) steps")
}
// Cameras and speed limits along the Davis to airport route.
if let line = merged.routes.first?.polyline, let extra = await Overpass.alongRoute(line, speed: true, plate: true) {
    let limits = Overpass.speedLimits(extra.ways, on: line)
    print("Along the route: \(extra.signals.count) traffic lights, \(extra.cameras.count) cameras, \(extra.ways.count) roads with limits, \(limits.count) changes: \(limits.prefix(10).map { "\(Int($0.startMeters)) m \($0.kmh.map { String(Int(($0 / 1.609344).rounded())) + " mph" } ?? "?")" })")
} else {
    print("Along the route: Overpass failed")
}

// Transit: San Francisco Ferry Building to Ocean Beach.
do {
    let trips = try await Transitous.plan(from: LatLng(37.7955, -122.3937), to: LatLng(37.7599, -122.5100))
    print("Transitous trips: \(trips.count)")
    for t in trips.prefix(3) {
        print("  · \(Int(t.durationSeconds / 60)) min, \(t.transfers) transfers: " + t.legs.map {
            $0.isWalk ? "walk \(Int($0.durationSeconds / 60))m" : "\($0.mode) \($0.line) → \($0.headsign ?? "?") (\($0.stops) stops, \($0.path.count) pts)"
        }.joined(separator: ", "))
    }
} catch {
    print("Transitous failed: \(error.localizedDescription)")
}

// Departure board: Davis train station.
if let b = await Transitous.departures(near: LatLng(38.5435, -121.7377)) {
    print("Departures at \(b.stop): \(b.departures.count), next: " + b.departures.prefix(4).map { "\($0.line) to \($0.headsign)" }.joined(separator: "; "))
} else {
    print("Departures: none or failed")
}


// A trip with a stop: Davis to Sacramento through Woodland.
do {
    let davis = LatLng(38.5449, -121.7405), sac = LatLng(38.5816, -121.4944), woodland = LatLng(38.6785, -121.7733)
    let g = try await GoogleClient.shared.directions(from: davis, to: sac, mode: .drive, via: [woodland])
    print("Google with a stop: \(g.count) routes" + (g.first.map { r in
        ", \(Int(r.distanceMeters)) m, \(Int(r.durationSeconds / 60)) min, \(r.polyline.count) pts, ends \(Int(r.polyline.last!.distance(to: sac))) m from Sacramento, passes \(Int(r.polyline.map { $0.distance(to: woodland) }.min()!)) m from Woodland, \(r.maneuvers.count) steps"
    } ?? ""))
} catch {
    print("Google with a stop failed: \(error)")
}
let viaOSRM = try? await OSRM.route(from: LatLng(38.5449, -121.7405), to: LatLng(38.5816, -121.4944), mode: .drive, via: [LatLng(38.6785, -121.7733)])
print("OSRM with a stop: \(viaOSRM?.first.map { "\(Int($0.distanceMeters)) m, \($0.maneuvers.count) steps" } ?? "failed")")


// Transit lines layer: lower Manhattan.
let tl = await Transitous.lines(south: 40.70, west: -74.02, north: 40.74, east: -73.97, zoom: 13)
if let first = tl?.first { print("Transit line sample: color \(String(format: "%06X", first.color)), \(first.points.count) pts, from \(first.points.first!) to \(first.points.last!)") }
print("Transit lines: \(tl.map { "\($0.count) stretches, lines \(Set($0.flatMap(\.names)).sorted().prefix(12))" } ?? "failed")")


// Lanes and roundabout exits in the merged steps.
if let r = merged.routes.first {
    let withLanes = r.maneuvers.filter { !$0.lanes.isEmpty }
    print("Lanes: \(withLanes.count) of \(r.maneuvers.count) steps; " + withLanes.prefix(3).map { m in
        m.instruction + " " + m.lanes.map { ($0.valid ? "*" : "") + $0.indications.joined(separator: "/") }.joined(separator: "|")
    }.joined(separator: "; "))
}

// Britain: the A9 north of Perth has average speed cameras; Wales and Scotland drive on the left too.
if let uk = try? await OSRM.route(from: LatLng(56.4120, -3.4700), to: LatLng(56.9370, -4.2400), mode: .drive).first {
    if let found = await Overpass.alongRoute(uk.polyline, speed: true, plate: false) {
        let projected = CameraAlerts.project(found.cameras, on: uk.polyline)
        let zones = CameraAlerts.merge(found.zones, CameraAlerts.averageZones(projected))
        let mph: (Double?) -> Int = { k in Int(((k ?? 0) / 1.609344).rounded()) }
        let limits = Overpass.speedLimits(found.ways, on: uk.polyline).map { mph($0.kmh) }
        let zoneText = zones.map { "\(Int($0.startMeters))-\(Int($0.endMeters)) m @ \(mph($0.kmh)) mph" }.joined(separator: ", ")
        print("UK A9: \(Int(uk.distanceMeters)) m, roundabout exits \(uk.maneuvers.compactMap(\.exit)), cameras \(found.cameras.count) on route \(projected.count) (average \(projected.filter { $0.camera.average }.count)), limits \(limits.prefix(20)), average zones: \(zoneText)")
    } else {
        print("UK A9: Overpass failed")
    }
} else {
    print("UK A9: routing failed")
}

// What Britain maps for cameras around Perth and the A9 (to tune the query above).
do {
    let q = "[out:json][timeout:40];(relation[\"type\"=\"enforcement\"](56.3,-4.0,56.8,-3.3);node[\"highway\"=\"speed_camera\"](56.3,-4.0,56.8,-3.3);node[\"enforcement\"](56.3,-4.0,56.8,-3.3););out tags 40;"
    var r = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
    r.httpMethod = "POST"
    r.httpBody = ("data=" + q.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!).data(using: .utf8)
    r.setValue("vela-probe", forHTTPHeaderField: "User-Agent")
    let (data, _) = try await URLSession.shared.data(for: r)
    let els = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["elements"] as? [[String: Any]]) ?? []
    print("UK camera tags: \(els.count) — " + els.prefix(15).map { "\($0["type"] ?? "")\(($0["tags"] as? [String: String] ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })" }.joined(separator: " ; "))
} catch {
    print("UK camera tags failed: \(error)")
}

// A British postcode in the open-data search.
let pc = await Postcodes.lookup("cf10 1ns")
print("Postcode: \(pc.map { "\($0.name) at \($0.location.lat),\($0.location.lng), \($0.address ?? "")" } ?? "failed")")

// Google Street View: a panorama near Davis's F Street and Pier 50 Sushi, its thumbnail and viewer.
do {
    let near = LatLng(38.54436, -121.74073)
    let raw = (try? await URLSession.shared.data(for: StreetView.searchRequest(near, radius: 60))).map { String(decoding: $0.0, as: UTF8.self) } ?? "failed"
    print("Street View reply: " + String(raw.prefix(1200)))
    var pano = await StreetView.find(near: near)
    if pano == nil { pano = await StreetView.find(near: LatLng(51.50080, -0.12460)) }
    if let pano {
        let heading = Geo.bearing(pano.location, pano.location.distance(to: near) < 1000 ? near : LatLng(51.5007, -0.1246))
        print("Street View: \(pano.id) \(pano.width)x\(pano.height) facing \(Int(pano.heading)) at \(pano.location), \(Int(pano.location.distance(to: near))) m away, heading \(Int(heading))")
        for url in [StreetView.thumbnailURL(pano, heading: heading), StreetView.tileURL(pano, x: 7, y: 3, zoom: 3)] {
            if let (data, resp) = try? await URLSession.shared.data(from: url) {
                let h = resp as? HTTPURLResponse
                print("  \(h?.statusCode ?? 0) \(h?.value(forHTTPHeaderField: "Content-Type") ?? "") \(data.count) bytes: \(url.absoluteString.prefix(90))")
            }
        }
    } else {
        print("Street View: none found")
    }
    let embed = URL(string: "https://www.google.com/maps/embed?pb=!4v1!6m8!1m7!1s!2m2!1d38.54436!2d-121.74073!3f0!4f0!5f0.78")!
    if let (d, resp) = try? await URLSession.shared.data(from: embed) {
        print("  embed by position only: \((resp as? HTTPURLResponse)?.statusCode ?? 0), \(d.count) bytes")
    }
    let london = await StreetView.find(near: LatLng(51.50080, -0.12460))
    print("Street View London: \(london.map { "\($0.id)" } ?? "none")")
}

// Waze live map: reports over central London, and along the Davis to airport drive.
do {
    // The feed alone, then again after opening the live map page with the same cookies.
    let url = Waze.url(south: 51.48, west: -0.20, north: 51.54, east: -0.05)
    for step in ["feed", "page", "feed after page"] {
        let target = step == "page" ? Waze.pageURL : url
        if let (data, resp) = try? await Waze.session.data(from: target) {
            let h = resp as? HTTPURLResponse
            let cookies = Waze.session.configuration.httpCookieStorage?.cookies?.map(\.name) ?? []
            print("Waze \(step): HTTP \(h?.statusCode ?? 0), \(data.count) bytes, cookies \(cookies): \(step == "page" ? "" : String(decoding: data.prefix(300), as: UTF8.self))")
        } else {
            print("Waze \(step): network error")
        }
    }
    let london = await Waze.alerts(south: 51.48, west: -0.20, north: 51.54, east: -0.05)
    if let london {
        let counts = Dictionary(grouping: london, by: \.kind).map { "\($0.key.rawValue) \($0.value.count)" }.sorted()
        print("Waze London: \(london.count) reports: \(counts); subtypes \(Set(london.map(\.subtype)).sorted().prefix(20))")
        for a in london.prefix(6) {
            print("  · \(a.title) on \(a.street ?? "-") at \(a.location), heading \(a.heading.map { String(Int($0)) } ?? "-"), \(Int(Date().timeIntervalSince(a.reportedAt) / 60)) min old, 👍 \(a.thumbsUp), reliability \(a.reliability)")
        }
    } else {
        print("Waze London: failed")
    }
    let davis = await Waze.alerts(south: 38.40, west: -121.90, north: 38.70, east: -121.40)
    print("Waze Davis/Sacramento (env \(Waze.env(for: LatLng(38.5, -121.6)))): \(davis.map { "\($0.count) reports" } ?? "failed")")
}

// Police aircraft: what the open flight trackers send around London, and police ones found.
for base in Aircraft.endpoints {
    let url = Aircraft.url(base, near: LatLng(51.5, -0.12), nauticalMiles: 40)
    if let (data, resp) = try? await URLSession.shared.data(from: url) {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let ac = root?["ac"] as? [[String: Any]] ?? []
        let ops = Set(ac.compactMap { $0["ownOp"] as? String }).sorted().prefix(15)
        print("Aircraft \(base): HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0), \(ac.count) aircraft, police \(Aircraft.parse(data)?.count ?? -1); fields \(ac.first.map { Array($0.keys).sorted() } ?? []); operators \(Array(ops))")
    } else {
        print("Aircraft \(base): network error")
    }
}

exit(exitCode)




/**
 * What Waze's answers held besides the reports Kite reads: is there a list of fixed speed
 * cameras in there? Each set of places is measured against cameras known to be real (from
 * OpenStreetMap, checked 2026-11-14), so a set that sits on them is the camera list.
 */
/** Everything in one piece of Waze's map: its tables, their sizes, and any places written out in full. */
func wazeTileReport(_ name: String, _ cam: LatLng, _ raw: Data, _ code: Int, _ id: Int) {
    let d = [UInt8](raw)
    func u32(_ b: [UInt8], _ o: Int) -> Int { o + 4 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 : 0 }
    func i32(_ b: [UInt8], _ o: Int) -> Int { Int(Int32(truncatingIfNeeded: u32(b, o))) }
    func hex(_ b: ArraySlice<UInt8>) -> String { b.map { String(format: "%02x", $0) }.joined() }
    print("TILE \(name) id \(id): HTTP \(code), \(d.count) bytes, starts \(hex(d.prefix(24)))")
    let magic: [UInt8] = [87, 90, 68, 70]
    var at = 0, blobs = 0
    while at + 20 <= d.count {
        guard Array(d[at..<at + 4]) == magic else { at += 1; continue }
        let comp = u32(d, at + 12), full = u32(d, at + 16)
        print("  WZDF at \(at): header \(hex(d[at..<at + 20])), packed \(comp), unpacked \(full)")
        blobs += 1
        guard comp > 6, at + 20 + comp <= d.count else { at += 4; continue }
        let body = Data(d[(at + 22)..<(at + 20 + comp - 4)])
        at += 20 + comp
        guard let out = try? (body as NSData).decompressed(using: .zlib) as Data else { print("  could not unpack"); continue }
        let s = [UInt8](out)
        let n = u32(s, 0), bits = u32(s, 4)
        guard n > 0, n < 200, 8 + n * 4 <= s.count else { print("  odd table count \(n)"); continue }
        let base = 8 + n * 4, mask = (1 << bits) - 1
        var prev = 0, sizes: [String] = []
        var parts: [(Int, [UInt8])] = []
        for i in 0..<n {
            let start = (prev + mask) & ~mask, end = u32(s, 8 + i * 4)
            prev = end
            guard end > start, base + end <= s.count else { continue }
            parts.append((i, Array(s[(base + start)..<(base + end)])))
            sizes.append("\(i):\(end - start)")
        }
        print("  \(n) tables, sizes \(sizes.joined(separator: " "))")
        let lonLo = Int((cam.lng - 0.02) * 1e6), lonHi = Int((cam.lng + 0.02) * 1e6)
        let latLo = Int((cam.lat - 0.02) * 1e6), latHi = Int((cam.lat + 0.02) * 1e6)
        for (i, b) in parts {
            // Places written out in full (millionths of a degree), either way round.
            var pts: [(Int, LatLng)] = []
            var o = 0
            while o + 8 <= b.count {
                let a = i32(b, o), c = i32(b, o + 4)
                if a >= lonLo, a <= lonHi, c >= latLo, c <= latHi { pts.append((o, LatLng(Double(c) / 1e6, Double(a) / 1e6))) }
                else if c >= lonLo, c <= lonHi, a >= latLo, a <= latHi { pts.append((o, LatLng(Double(a) / 1e6, Double(c) / 1e6))) }
                o += 1
            }
            if !pts.isEmpty {
                let list = pts.prefix(10).map { String(format: "@%d %.5f,%.5f (%.0f m)", $0.0, $0.1.lat, $0.1.lng, $0.1.distance(to: cam)) }
                print("  table \(i): \(pts.count) full places: " + list.joined(separator: " · "))
            }
            let text = String(decoding: b.map { $0 >= 32 && $0 < 127 ? $0 : 124 }, as: UTF8.self)
            let words: [String] = text.split(separator: "|").map { String($0) }.filter { $0.count >= 3 }
            if words.count >= 3 && words.map(\.count).reduce(0, +) * 2 > b.count {
                let hits = words.filter { let w = $0.lowercased(); return w.contains("cam") || w.contains("speed") || w.contains("radar") || w.contains("alert") }
                print("  table \(i) text (\(words.count) words): \(words.prefix(12).joined(separator: "; "))" + (hits.isEmpty ? "" : " · CAMERA WORDS: \(hits.prefix(10).joined(separator: "; "))"))
            } else if ![8, 9, 13].contains(i), b.count <= 160 {
                print("  table \(i) raw: \(hex(b[...]))")
            } else if ![8, 9, 13].contains(i) {
                print("  table \(i) starts: \(hex(b.prefix(48)))")
            }
        }
    }
    if blobs == 0 { print("  no WZDF map data in the answer: \(String(decoding: d.prefix(200).map { $0 >= 32 && $0 < 127 ? $0 : 46 }, as: UTF8.self))") }
}

/** The fixed cameras in one piece of Waze's map: table 25, 16 bytes each (place, facing, kind, speed, id). */
func wazeTileCameras(_ raw: Data) -> [(at: LatLng, heading: Int, kind: Int, speed: Int)] {
    let d = [UInt8](raw)
    func u32(_ b: [UInt8], _ o: Int) -> Int { o + 4 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 : 0 }
    func i32(_ b: [UInt8], _ o: Int) -> Int { Int(Int32(truncatingIfNeeded: u32(b, o))) }
    var at = 0
    while at + 20 <= d.count, !(d[at] == 87 && d[at + 1] == 90 && d[at + 2] == 68 && d[at + 3] == 70) { at += 1 }
    guard at + 20 <= d.count else { return [] }
    let comp = u32(d, at + 12)
    guard comp > 6, at + 20 + comp <= d.count else { return [] }
    guard let out = try? (Data(d[(at + 22)..<(at + 20 + comp - 4)]) as NSData).decompressed(using: .zlib) as Data else { return [] }
    let s = [UInt8](out)
    let n = u32(s, 0), bits = u32(s, 4)
    guard n > 25, n < 200, 8 + n * 4 <= s.count, bits < 16 else { return [] }
    let base = 8 + n * 4, mask = (1 << bits) - 1
    let start = (u32(s, 8 + 24 * 4) + mask) & ~mask, end = u32(s, 8 + 25 * 4)
    guard end > start, base + end <= s.count else { return [] }
    let b = Array(s[(base + start)..<(base + end)])
    var list: [(at: LatLng, heading: Int, kind: Int, speed: Int)] = []
    var o = 0
    while o + 16 <= b.count {
        list.append((LatLng(Double(i32(b, o + 4)) / 1e6, Double(i32(b, o)) / 1e6), Int(b[o + 8]) | Int(b[o + 9]) << 8, Int(b[o + 10]), Int(b[o + 11])))
        o += 16
    }
    return list
}

func wazeCensusReport() {
    guard let c = WazeLive.census else { return }
    WazeLive.census = nil
    print("--- everything Waze sent ---")
    print("elements: " + c.elements.sorted { $0.key < $1.key }.map { "\($0.key)x\($0.value)" }.joined(separator: " "))
    for (name, n) in c.commands.sorted(by: { $0.value > $1.value }) {
        print("command \(name) x\(n): \(c.commandSample[name] ?? "")")
    }
    let known: [(String, LatLng)] = [("Northam Bridge", LatLng(50.9156326, -1.3851174)), ("M27 J5 a", LatLng(50.9494996, -1.3803431)),
                                      ("M27 J5 b", LatLng(50.949223, -1.3801986)), ("M27 J7 a", LatLng(50.9352479, -1.3411425)),
                                      ("M27 J7 b", LatLng(50.935568, -1.3387029)), ("M27 J8 a", LatLng(50.9101758, -1.3184896)),
                                      ("M27 J8 b", LatLng(50.9078083, -1.3180459)), ("M3 J9", LatLng(51.0727903, -1.2919975)),
                                      ("Bitterne Rd", LatLng(50.9156984, -1.3614169))]
    // Thomas Lewis Way (A335), from the city end to the Swaythling end.
    let lewis = [LatLng(50.91894, -1.39534), LatLng(50.9245, -1.3905), LatLng(50.9300, -1.3855), LatLng(50.9350, -1.3815), LatLng(50.94056, -1.37789)]
    func measure(_ name: String, _ pts: [LatLng]) {
        let near: [(String, Double)] = known.map { k in
            let d: Double = pts.map { $0.distance(to: k.1) }.min() ?? Double.infinity
            return (k.0, d)
        }
        let hits = near.filter { $0.1 < 120 }.count
        let onLewis = pts.filter { Geo.project($0, on: lewis).offset < 60 }
        print("\(name): \(pts.count) places · on \(hits) of \(known.count) known cameras · \(onLewis.count) on Thomas Lewis Way")
        print("   nearest to each known camera: " + near.map { String(format: "%@ %.0f m", $0.0, $0.1) }.joined(separator: ", "))
        for p in onLewis.prefix(6) { print(String(format: "   Thomas Lewis Way: %.5f,%.5f", p.lat, p.lng)) }
        print("   first places: " + pts.prefix(8).map { String(format: "%.5f,%.5f", $0.lat, $0.lng) }.joined(separator: " "))
    }
    for (key, n) in c.alertTypes.sorted(by: { $0.value > $1.value }) {
        measure("report type \(key) x\(n)", c.alertPlaces[key] ?? [])
    }
    for (path, pts) in c.places.sorted(by: { $0.value.count > $1.value.count }).prefix(40) {
        measure("other \(path)", pts)
    }
    for (root, w) in c.words.sorted(by: { $0.key < $1.key }) { print("words in \(root): \(w)") }
}
