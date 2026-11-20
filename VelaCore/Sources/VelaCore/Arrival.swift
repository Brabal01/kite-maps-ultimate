import Foundation

/** A car park near where you're going, from the open map. */
public struct CarPark: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String?
    public var location: LatLng
    /** Metres from where you're going. */
    public var meters: Double
    /** True when the map says you pay, false when it says free; nil when it doesn't say. */
    public var fee: Bool?
    public var spaces: Int?
    /** Underground, multi-storey or open air. */
    public var kind: String?
}

/**
 * Help at the other end (GitHub #63): car parks near the destination, and a big place's main entrance
 * so the drive ends at the door rather than wherever the map's pin sits in a huge building.
 */
public enum ArrivalHelp {
    /** Places big enough for the pin to be far from the way in. */
    public static func isBigPlace(_ category: String?) -> Bool {
        let c = (category ?? "").lowercased()
        return ["hospital", "shopping", "mall", "station", "airport", "terminal", "university", "college", "stadium", "arena",
                "retail park", "outlet", "museum", "zoo", "theme park", "leisure centre", "exhibition", "conference", "campus"]
            .contains { c.contains($0) }
    }

    public static func parkingQuery(near p: LatLng, radius: Int = 500) -> String {
        "[out:json][timeout:25];nwr[\"amenity\"=\"parking\"](around:\(radius),\(p.lat),\(p.lng));out center tags 60;"
    }

    public static func entranceQuery(near p: LatLng, radius: Int = 350) -> String {
        "[out:json][timeout:25];node[\"entrance\"=\"main\"](around:\(radius),\(p.lat),\(p.lng));out 30;"
    }

    /** The car parks anyone can use, nearest first: not private, not just a few spaces along a street. */
    public static func parseParking(_ data: Data, near p: LatLng, limit: Int = 8) -> [CarPark]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { return nil }
        var out: [CarPark] = []
        for e in elements {
            let tags = e["tags"] as? [String: String] ?? [:]
            let access = tags["access"]?.lowercased() ?? "yes"
            guard !["private", "no", "permit", "residents", "delivery"].contains(access) else { continue }
            let kind = tags["parking"]?.lowercased()
            if let kind, ["street_side", "lane", "on_kerb", "half_on_kerb", "layby", "garage_boxes", "carports"].contains(kind) { continue }
            let center = e["center"] as? [String: Any]
            guard let lat = (e["lat"] ?? center?["lat"]) as? Double, let lng = (e["lon"] ?? center?["lon"]) as? Double else { continue }
            let at = LatLng(lat, lng)
            let fee = tags["fee"].map { ["yes", "true"].contains($0.lowercased()) ? true : ["no", "false"].contains($0.lowercased()) ? false : nil } ?? nil
            let id = "\(e["type"] as? String ?? "x")\((e["id"] as? NSNumber)?.int64Value ?? 0)"
            out.append(CarPark(id: id, name: tags["name"], location: at, meters: at.distance(to: p), fee: fee,
                               spaces: tags["capacity"].flatMap { Int($0) },
                               kind: kind == "underground" ? "Underground" : kind == "multi-storey" ? "Multi-storey" : nil))
        }
        // Small unnamed ones (a few spaces behind a shop) last: a named or big car park is the useful answer.
        return Array(out.sorted { a, b in
            let ka = a.meters + (a.name == nil && (a.spaces ?? 0) < 20 ? 250 : 0)
            let kb = b.meters + (b.name == nil && (b.spaces ?? 0) < 20 ? 250 : 0)
            return ka < kb
        }.prefix(limit))
    }

    /** The main entrance nearest the pin, if there's one at least 40 m from it (any closer and the pin is fine). */
    public static func parseEntrance(_ data: Data, near p: LatLng) -> LatLng? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else { return nil }
        let doors = elements.compactMap { e -> LatLng? in
            let tags = e["tags"] as? [String: String] ?? [:]
            if ["private", "no"].contains(tags["access"]?.lowercased() ?? "") { return nil }
            guard let lat = e["lat"] as? Double, let lng = e["lon"] as? Double else { return nil }
            return LatLng(lat, lng)
        }
        guard let door = doors.min(by: { $0.distance(to: p) < $1.distance(to: p) }), door.distance(to: p) >= 40 else { return nil }
        return door
    }

    public static func parking(near p: LatLng) async -> [CarPark]? {
        guard let data = await Overpass.query(parkingQuery(near: p)) else { return nil }
        return parseParking(data, near: p)
    }

    public static func mainEntrance(near p: LatLng) async -> LatLng? {
        guard let data = await Overpass.query(entranceQuery(near: p)) else { return nil }
        return parseEntrance(data, near: p)
    }
}
