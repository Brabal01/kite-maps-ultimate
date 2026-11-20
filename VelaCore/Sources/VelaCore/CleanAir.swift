import Foundation

/**
 * Britain's clean air zones that cars can pay or be fined in (GitHub #75): London's ULEZ (all of
 * Greater London), Birmingham, Bristol, Oxford's zero emission zone, and Scotland's low emission
 * zones. The shapes are from OpenStreetMap, made simpler, and kept in the app (they rarely change).
 * Zones that only charge buses, lorries and taxis (Bath, Sheffield, Newcastle, Portsmouth, Bradford)
 * aren't listed, since a car never pays there. No prices: they change, and the point is only to know.
 */
public enum CleanAirZones {
    struct Zone {
        let name: String
        let note: String
        /** Charged even when the car meets the usual rules (Oxford: only electric cars are free). */
        let everyCar: Bool
        let ring: [LatLng]
        let minLat: Double, maxLat: Double, minLng: Double, maxLng: Double
        /** How far inside the edge counts: the road round a zone is usually free. */
        let depth: Double

        init(_ name: String, _ note: String, everyCar: Bool = false, depth: Double = 100, _ flat: [Double]) {
            self.name = name
            self.note = note
            self.everyCar = everyCar
            self.depth = depth
            var r: [LatLng] = []
            var i = 0
            while i + 1 < flat.count { r.append(LatLng(flat[i], flat[i + 1])); i += 2 }
            if let f = r.first, let l = r.last, f != l { r.append(f) }
            ring = r
            minLat = r.map(\.lat).min() ?? 0; maxLat = r.map(\.lat).max() ?? 0
            minLng = r.map(\.lng).min() ?? 0; maxLng = r.map(\.lng).max() ?? 0
        }

        func contains(_ p: LatLng) -> Bool {
            guard ring.count >= 4, p.lat > minLat, p.lat < maxLat, p.lng > minLng, p.lng < maxLng else { return false }
            var inside = false
            var j = ring.count - 1
            for i in 0..<ring.count {
                let a = ring[i], b = ring[j]
                if (a.lat > p.lat) != (b.lat > p.lat),
                   p.lng < (b.lng - a.lng) * (p.lat - a.lat) / (b.lat - a.lat) + a.lng { inside.toggle() }
                j = i
            }
            return inside && Geo.project(p, on: ring).offset > depth
        }
    }

    /**
     * The zones a route goes into. With [cleanCar] ("My car meets the rules" in Settings) only those
     * that charge every car are left. Empty for nearly every route.
     */
    public static func on(_ line: [LatLng], cleanCar: Bool) -> [RoadCharge] {
        guard line.count >= 2 else { return [] }
        var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0
        for p in line {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLng = min(minLng, p.lng); maxLng = max(maxLng, p.lng)
        }
        var found: [RoadCharge] = []
        for z in zones where !cleanCar || z.everyCar {
            guard z.maxLat > minLat, z.minLat < maxLat, z.maxLng > minLng, z.minLng < maxLng else { continue }
            if line.contains(where: { z.contains($0) }) { found.append(RoadCharge(name: z.name, note: z.note, zone: true)) }
        }
        return found
    }

    static let older = "Older cars pay a daily charge: most petrol cars from before 2006 and diesels from before late 2015. Pay online."
    static let scotland = "Older cars aren't allowed in, and get a fine: most petrol cars from before 2006 and diesels from before late 2015. No barriers."

    static let zones: [Zone] = CleanAirShapes.all
}
