import Foundation

/** One Google review of a place, as Google Maps lists them. */
public struct GoogleReview: Hashable, Sendable {
    public var author: String
    public var rating: Int?
    /** "2 months ago", as Google words it. */
    public var when: String?
    public var text: String
}

/**
 * A place's Google reviews, the ones Google Maps shows first (GitHub #70: Kite only ever showed one).
 * The page Google Maps itself asks; when it stops answering, Kite opens the place's reviews on Google instead.
 */
public enum GoogleReviews {
    /** Google's own numbers for the place ("0x4874…:0x1a2b…"), as the decimal pair its pages ask with. */
    public static func ids(_ featureId: String) -> (String, String)? {
        let parts = featureId.split(separator: ":").map { $0.hasPrefix("0x") ? String($0.dropFirst(2)) : String($0) }
        guard parts.count == 2, let a = UInt64(parts[0], radix: 16), let b = UInt64(parts[1], radix: 16) else { return nil }
        return (String(a), String(b))
    }

    static func url(featureId: String, count: Int = 20) -> URL? {
        guard let (a, b) = ids(featureId) else { return nil }
        let pb = "!1m2!1y\(a)!2y\(b)!2m2!1i0!2i\(count)!3e1!4m5!3b1!4b1!5b1!6b1!7b1"
        return URL(string: "https://www.google.com/maps/preview/review/listentitiesreviews?authuser=0&hl=en-GB&gl=gb&pb=" + pb)
    }

    /** Reviews from Google's answer; nil when it isn't the shape expected. Reviews with no words are left out. */
    public static func parse(_ body: String) -> [GoogleReview]? {
        guard let root = GoogleJSON.parse(body) as? [Any] else { return nil }
        guard root.count > 2 else { return [] }
        guard let list = root[2] as? [Any] else { return root[2] is NSNull ? [] : nil }
        return list.compactMap { item -> GoogleReview? in
            guard let r = item as? [Any], r.count > 4 else { return nil }
            let author = ((r[0] as? [Any]).flatMap { $0.count > 1 ? $0[1] as? String : nil }) ?? "Google user"
            guard let text = (r[3] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let rating = (r[4] as? NSNumber)?.intValue
            return GoogleReview(author: author, rating: rating.flatMap { (1...5).contains($0) ? $0 : nil },
                                when: r[1] as? String, text: text)
        }
    }

    /** Where to read every review on Google, for when Kite can't list them itself. */
    public static func webURL(_ p: Place) -> URL? {
        var c = URLComponents(string: "https://www.google.com/maps/search/")!
        c.queryItems = [URLQueryItem(name: "api", value: "1"),
                        URLQueryItem(name: "query", value: [p.name, p.address].compactMap { $0 }.joined(separator: ", "))]
        if let id = p.placeId { c.queryItems?.append(URLQueryItem(name: "query_place_id", value: id)) }
        return c.url
    }
}

extension GoogleClient {
    /** The place's Google reviews, most relevant first; nil when Google didn't answer as expected. */
    public func reviews(featureId: String) async -> [GoogleReview]? {
        guard let url = GoogleReviews.url(featureId: featureId), let body = try? await fetch(url) else { return nil }
        return GoogleReviews.parse(body)
    }
}
