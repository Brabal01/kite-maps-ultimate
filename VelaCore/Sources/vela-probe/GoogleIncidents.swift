import Foundation
import VelaCore

/**
 * Waze's website stopped sharing drivers' police, crash and hazard reports. Google Maps shows some
 * of them along routes: look for them in Google's raw route answers, around Southampton (where the
 * Waze app showed police at Bishopstoke), on the M27, across London and in Los Angeles.
 */
func googleIncidents() async {
    let drives: [(String, LatLng, LatLng)] = [
        ("Southampton to Bishopstoke", LatLng(50.909, -1.404), LatLng(50.966, -1.330)),
        ("M27 Southampton to Portsmouth", LatLng(50.915, -1.380), LatLng(50.805, -1.087)),
        ("Heathrow to the City", LatLng(51.470, -0.454), LatLng(51.513, -0.090)),
        ("Santa Monica to Downtown LA", LatLng(34.019, -118.491), LatLng(34.050, -118.250)),
        // Past fixed speed cameras known to be real: does Google's answer mention any of them?
        ("Thomas Lewis Way towards the city centre", LatLng(50.94056, -1.37789), LatLng(50.91894, -1.39534)),
        ("Northam Bridge eastbound (camera at 50.91563,-1.38512)", LatLng(50.9128, -1.3920), LatLng(50.9160, -1.3700)),
        ("M27 J4 to J8 (cameras at J5 and J7)", LatLng(50.9560, -1.4060), LatLng(50.9050, -1.3120)),
        ("M3 J10 to J9 northbound (camera at 51.07279,-1.29200)", LatLng(51.0450, -1.3050), LatLng(51.0900, -1.2850)),
        ("London A40 Westway and Western Avenue", LatLng(51.5205, -0.1830), LatLng(51.5330, -0.3200)),
    ]
    let words = ["speed trap", "police", "crash", "accident", "reported", "waze", "speed camera", "hazard",
                 "roadwork", "construction", "lane clos", "road closed", "incident", "stalled", "object on",
                 "camera", "radar", "speed check", "enforcement", "red light"]
    for (name, a, b) in drives {
        do {
            let body = try await GoogleClient.shared.directionsBody(from: a, to: b, mode: .drive)
            let low = body.lowercased()
            print("Google incidents · \(name): \(body.count) chars")
            // Every kind of thing Google marks along the route: [number, ["Label"]].
            if let re = try? NSRegularExpression(pattern: #"\[(\d+),\[\\?"([^"\\\]]{3,40})\\?"\]\]"#) {
                var kinds: [String: Int] = [:]
                let ns = body as NSString
                for m in re.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                    kinds["\(ns.substring(with: m.range(at: 1))) \(ns.substring(with: m.range(at: 2)))", default: 0] += 1
                }
                print("  kinds marked: " + (kinds.isEmpty ? "none" : kinds.sorted { $0.value > $1.value }.map { "\($0.key) x\($0.value)" }.joined(separator: ", ")))
            }
            for w in words {
                var hits: [String] = []
                var from = low.startIndex
                while let r = low.range(of: w, range: from..<low.endIndex) {
                    if hits.count < 3 {
                        let s = low.index(r.lowerBound, offsetBy: -80, limitedBy: low.startIndex) ?? low.startIndex
                        let e = low.index(r.upperBound, offsetBy: 120, limitedBy: low.endIndex) ?? low.endIndex
                        hits.append(String(body[s..<e]).replacingOccurrences(of: "\n", with: " "))
                    }
                    from = r.upperBound
                }
                let n = low.components(separatedBy: w).count - 1
                if n > 0 {
                    print("  \"\(w)\" ×\(n)")
                    for h in hits { print("    … \(h) …") }
                }
            }
        } catch {
            print("Google incidents · \(name): failed \(error)")
        }
    }
}
