import Foundation

/**
 * Where to write the road's name in the driving view with no route: along the road itself, from the
 * map's own road lines, rather than straight ahead (which floats off the road on a bend).
 */
public enum RoadAhead {
    /**
     * The stretch of road [from] to [to] metres ahead of [here] going [heading], following [lines]
     * (the map's pieces of the road you're on, in any order and direction). Nil when you're not on
     * one of them (30 m), or there isn't room ahead for the name.
     */
    public static func path(_ lines: [[LatLng]], at here: LatLng, heading: Double, from: Double = 40, to: Double = 200) -> [LatLng]? {
        var best: (i: Int, along: Double, offset: Double)?
        for (i, l) in lines.enumerated() where l.count >= 2 {
            let p = Geo.project(here, on: l)
            if p.offset <= 30, best.map({ p.offset < $0.offset }) ?? true { best = (i, p.along, p.offset) }
        }
        guard let b = best else { return nil }
        var line = lines[b.i]
        var along = b.along
        let len = Geo.length(line)
        // Which way along it you're going.
        let ahead = Geo.bearing(Geo.point(along: line, meters: max(0, along - 5)), Geo.point(along: line, meters: min(len, along + 5)))
        if turn(ahead, heading) > 90 {
            line.reverse()
            along = len - along
        }
        var path = Geo.slice(line, from: along, to: len)
        guard path.count >= 2 else { return nil }
        // On into the next piece (the map cuts roads at tile edges and junctions).
        var used: Set<Int> = [b.i]
        while Geo.length(path) < to, used.count < 8 {
            guard let end = path.last, path.count >= 2 else { break }
            let dir = Geo.bearing(path[path.count - 2], end)
            var next: (i: Int, line: [LatLng], turn: Double)?
            for (i, l) in lines.enumerated() where !used.contains(i) && l.count >= 2 {
                var c = l
                if l[l.count - 1].distance(to: end) < 5 { c.reverse() } else if l[0].distance(to: end) >= 5 { continue }
                let t = turn(Geo.bearing(c[0], c[1]), dir)
                if t < 100, next.map({ t < $0.turn }) ?? true { next = (i, c, t) }
            }
            guard let n = next else { break }
            used.insert(n.i)
            path += n.line.dropFirst()
        }
        let total = Geo.length(path)
        guard total >= from + 60 else { return nil }
        return Geo.slice(path, from: from, to: min(to, total))
    }

    private static func turn(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
