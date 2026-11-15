import Foundation

/**
 * Fixed speed cameras from Waze's own map. OpenStreetMap, where Kite's cameras came from until
 * now, is thin and old in places (Southampton's Thomas Lewis Way had none mapped), while Waze's
 * map is kept up by its drivers. The map comes in small pieces (a hundredth of a degree square,
 * a few kilobytes), each with a short table of cameras: where, which way, and the limit.
 * Read the way SABRE Plus reads the same pieces for their roads (MIT, see licenses).
 *
 * Only alongside OpenStreetMap's cameras, never instead: a camera both maps hold shows once.
 */
public enum WazeCameras {
    /** Set by the app: Waze's cameras are only asked for while Waze is switched on in Settings. */
    nonisolated(unsafe) public static var enabled = false
    /** The cameras read so far, kept on the phone. Swapped for an empty one in tests. */
    nonisolated(unsafe) public static var shared = WazeCameraStore()

    static let rows = 18_000
    /** A drive's pieces, nearest first: about 300 km of road. */
    static let maxRouteTiles = 700
    /** The most pieces one look at the map may ask for: a town, not a county. */
    static let maxBoxTiles = 80

    /** Waze's number for the piece of map holding [p]. */
    public static func tileId(_ p: LatLng) -> Int {
        ((Int(p.lng * 1_000_000) + 180_000_000) / 10_000) * rows + (Int(p.lat * 1_000_000) + 90_000_000) / 10_000
    }

    /** The pieces within about 150 m of [line], from its start on, each once. */
    public static func tileIds(along line: [LatLng]) -> [Int] {
        var seen = Set<Int>()
        var out: [Int] = []
        let dLat = 0.0014, dLng = 0.0022
        func note(_ p: LatLng) {
            for (dy, dx) in [(0.0, 0.0), (dLat, dLng), (dLat, -dLng), (-dLat, dLng), (-dLat, -dLng)] {
                let id = tileId(LatLng(p.lat + dy, p.lng + dx))
                if seen.insert(id).inserted { out.append(id) }
            }
        }
        guard var last = line.first else { return [] }
        note(last)
        for p in line.dropFirst() {
            let n = max(1, Int((last.distance(to: p) / 250).rounded(.up)))
            for i in 1...n {
                let t = Double(i) / Double(n)
                note(LatLng(last.lat + (p.lat - last.lat) * t, last.lng + (p.lng - last.lng) * t))
            }
            last = p
        }
        return out
    }

    /** The pieces covering a box; empty when it would take more than [most]. */
    public static func tileIds(south: Double, west: Double, north: Double, east: Double, most: Int = maxBoxTiles) -> [Int] {
        let a = tileId(LatLng(south, west)), b = tileId(LatLng(north, east))
        let x0 = a / rows, x1 = b / rows, y0 = a % rows, y1 = b % rows
        guard x1 >= x0, y1 >= y0, (x1 - x0 + 1) * (y1 - y0 + 1) <= most else { return [] }
        var out: [Int] = []
        for x in x0...x1 { for y in y0...y1 { out.append(x * rows + y) } }
        return out
    }

    // MARK: Reading a piece

    private static func u32(_ b: [UInt8], _ o: Int) -> Int {
        o >= 0 && o + 4 <= b.count ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 : 0
    }

    /** The speed cameras in one piece as Waze's server sends it; nil when [data] isn't a map piece. */
    public static func parse(_ data: Data) -> [RoadCamera]? {
        let d = [UInt8](data)
        // "WZDF", then the packed and unpacked sizes, then the tables, zlib-packed.
        var at = 0
        while at + 20 <= d.count, !(d[at] == 87 && d[at + 1] == 90 && d[at + 2] == 68 && d[at + 3] == 70) { at += 1 }
        guard at + 20 <= d.count else { return nil }
        let packed = u32(d, at + 12)
        guard packed > 6, at + 20 + packed <= d.count else { return nil }
        // Past zlib's two-byte header, without its four-byte check at the end.
        let body = Data(d[(at + 22)..<(at + 20 + packed - 4)])
        guard let out = try? (body as NSData).decompressed(using: .zlib) as Data else { return nil }
        return cameras(tables: [UInt8](out))
    }

    /**
     * The speed cameras in a piece's unpacked tables. The tables sit one after another behind a
     * list of where each ends; table 26 opens with the piece's number, and table 25 holds the
     * cameras, 16 bytes each: longitude and latitude in millionths of a degree, the way it faces,
     * its kind (2 is a speed camera), its limit in km/h, and Waze's number for it.
     */
    static func cameras(tables s: [UInt8]) -> [RoadCamera]? {
        let n = u32(s, 0), bits = u32(s, 4)
        guard n > 26, n < 200, bits < 16, 8 + n * 4 <= s.count else { return nil }
        let base = 8 + n * 4, mask = (1 << bits) - 1
        func table(_ i: Int) -> [UInt8] {
            let start = i == 0 ? 0 : (u32(s, 8 + (i - 1) * 4) + mask) & ~mask, end = u32(s, 8 + i * 4)
            guard end > start, base + end <= s.count else { return [] }
            return Array(s[(base + start)..<(base + end)])
        }
        let head = table(26)
        guard head.count >= 4 else { return nil }
        let tile = u32(head, 0)
        let west = Double(tile / rows * 10_000 - 180_000_000) / 1e6, south = Double(tile % rows * 10_000 - 90_000_000) / 1e6
        let b = table(25)
        var out: [RoadCamera] = []
        var o = 0
        while o + 16 <= b.count {
            defer { o += 16 }
            let lng = Double(Int32(truncatingIfNeeded: u32(b, o))) / 1e6, lat = Double(Int32(truncatingIfNeeded: u32(b, o + 4))) / 1e6
            // Only a plain speed camera, and only where the piece itself is: anything else isn't one.
            guard b[o + 10] == 2, lat >= south - 0.001, lat <= south + 0.011, lng >= west - 0.001, lng <= west + 0.011 else { continue }
            let kmh = Int(b[o + 11])
            let number = Int(b[o + 12]) | Int(b[o + 13]) << 8
            out.append(RoadCamera(id: -(Int64(tile) * 100_000 + Int64(number) + 1), kind: .speed, location: LatLng(lat, lng),
                                  maxspeedKmh: kmh > 0 ? Double(kmh) : nil))
        }
        return out
    }

    // MARK: Mixing with OpenStreetMap's

    /** Whether a camera came from Waze's map (OpenStreetMap's numbers are all above zero). */
    public static func isWaze(_ c: RoadCamera) -> Bool { c.id < 0 }

    /**
     * [base] plus the cameras only Waze has: one within 60 m of a speed camera already there is the
     * same camera (the two maps place it a few metres apart), and Waze's own doubles go too.
     */
    public static func merge(_ base: [RoadCamera], waze: [RoadCamera]) -> [RoadCamera] {
        guard !waze.isEmpty else { return base }
        var out = base
        let mapped = base.filter { $0.kind == .speed && !isWaze($0) }
        var added = base.filter { isWaze($0) }
        for c in waze where !base.contains(where: { $0.id == c.id }) {
            if mapped.contains(where: { abs($0.location.lat - c.location.lat) < 0.001 && $0.location.distance(to: c.location) < 60 }) { continue }
            if added.contains(where: { abs($0.location.lat - c.location.lat) < 0.001 && $0.location.distance(to: c.location) < 12 }) { continue }
            added.append(c)
            out.append(c)
        }
        return out
    }

    // MARK: Asking Waze

    /**
     * Waze's speed cameras within 150 m of a route, asking for the pieces not yet on the phone.
     * Nil when Waze couldn't be asked and nothing is known; empty when it's switched off.
     */
    public static func along(_ line: [LatLng]) async -> [RoadCamera]? {
        guard enabled, line.count >= 2 else { return [] }
        let ok = await load(Array(tileIds(along: line).prefix(maxRouteTiles)), near: line[0])
        let found = shared.known(along: line)
        return ok || !found.isEmpty ? found : nil
    }

    /** Asks for the pieces covering what the map shows, when zoomed in enough. True when new ones came. */
    public static func load(south: Double, west: Double, north: Double, east: Double) async -> Bool {
        guard enabled else { return false }
        let ids = shared.stale(tileIds(south: south, west: west, north: north, east: east))
        guard !ids.isEmpty else { return false }
        return await load(ids, near: LatLng((south + north) / 2, (west + east) / 2))
    }

    /** True when every piece asked for is now known (or already was). */
    static func load(_ ids: [Int], near: LatLng) async -> Bool {
        let want = shared.stale(ids)
        guard !want.isEmpty else { return true }
        guard let got = await WazeLive.shared.mapTiles(want, near: near) else { return false }
        var fresh: [Int: [RoadCamera]] = [:]
        var blank: [Int] = []
        for (id, data) in got {
            if let cams = parse(data) { fresh[id] = cams } else { blank.append(id) }
        }
        shared.put(fresh, blank: blank)
        return got.count == want.count
    }
}

/** Waze's cameras by map piece, kept on the phone: a piece is asked for again after a week. */
public final class WazeCameraStore: @unchecked Sendable {
    struct Tile: Codable {
        /** When it was read, in seconds since 1970. */
        var at: Double
        var cameras: [RoadCamera]
    }

    private let lock = NSLock()
    private var tiles: [Int: Tile]?
    private let file: URL?
    private var saving = false
    private var changes = 0

    static let keep: Double = 7 * 86_400
    static let maxTiles = 8_000

    /** [file] nil keeps it in memory only (tests). */
    public init(file: URL? = WazeCameraStore.defaultFile) {
        self.file = file
    }

    public static var defaultFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("waze-cameras.json")
    }

    /** Goes up whenever new pieces come in, so the map knows to draw again. */
    public var version: Int {
        lock.lock(); defer { lock.unlock() }
        return changes
    }

    private func loaded() -> [Int: Tile] {
        if let tiles { return tiles }
        var t: [Int: Tile] = [:]
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Int: Tile].self, from: data) { t = saved }
        tiles = t
        return t
    }

    /** Which of [ids] aren't on the phone, or were read more than a week ago. */
    public func stale(_ ids: [Int], now: Date = Date()) -> [Int] {
        lock.lock(); defer { lock.unlock() }
        let t = loaded()
        return ids.filter { id in t[id].map { now.timeIntervalSince1970 - $0.at > Self.keep } ?? true }
    }

    /** Remembers pieces just read. A [blank] one (no map came back) is only trusted for a day. */
    public func put(_ fresh: [Int: [RoadCamera]], blank: [Int] = [], now: Date = Date()) {
        guard !fresh.isEmpty || !blank.isEmpty else { return }
        lock.lock()
        var t = loaded()
        let at = now.timeIntervalSince1970
        for (id, cams) in fresh { t[id] = Tile(at: at, cameras: cams) }
        for id in blank where t[id] == nil { t[id] = Tile(at: at - Self.keep + 86_400, cameras: []) }
        if t.count > Self.maxTiles {
            for (id, _) in t.sorted(by: { $0.value.at < $1.value.at }).prefix(t.count - Self.maxTiles / 2) { t[id] = nil }
        }
        tiles = t
        changes += 1
        let start = !saving && file != nil
        if start { saving = true }
        lock.unlock()
        if start {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { self.save() }
        }
    }

    private func save() {
        lock.lock()
        let t = tiles
        saving = false
        lock.unlock()
        guard let file, let t, let data = try? JSONEncoder().encode(t) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /** Every Waze camera on the phone. */
    public func known() -> [RoadCamera] {
        lock.lock(); defer { lock.unlock() }
        return loaded().values.flatMap(\.cameras)
    }

    /** Those within [meters] of a route. */
    public func known(along line: [LatLng], meters: Double = 150) -> [RoadCamera] {
        guard line.count >= 2 else { return [] }
        let all = known()
        guard !all.isEmpty else { return [] }
        let lats = line.map(\.lat), lngs = line.map(\.lng)
        let pad = 0.004
        let s0 = lats.min()! - pad, n0 = lats.max()! + pad, w0 = lngs.min()! - pad, e0 = lngs.max()! + pad
        let close = all.filter { (s0...n0).contains($0.location.lat) && (w0...e0).contains($0.location.lng) }
        guard !close.isEmpty else { return [] }
        let cum = Geo.cumulative(line)
        return close.filter { Geo.project($0.location, on: line, cumulative: cum).offset <= meters }
    }
}
