import Foundation

/**
 How far out the driving map sits and how much it tilts, from your speed and the next turn.
 On a long stretch it pulls back and tilts up so you see far ahead; in the last 300 m before a turn it
 glides in and flattens so the whole junction and the road you turn onto fill the screen; after the
 turn it eases back out. Moving faster keeps it further out, so a motorway exit still shows the slip road.
 */
public enum NavZoom {
    /** Meters across the screen, and the camera's tilt in degrees. */
    public struct View: Equatable, Sendable {
        public var across: Double
        public var pitch: Double
        public init(across: Double, pitch: Double) { self.across = across; self.pitch = pitch }
    }

    /** Where the zoom starts closing in before a turn, and where it is fully in. */
    public static let nearStart = 300.0
    public static let nearEnd = 60.0

    /**
     The view for driving at [speed] m/s with the next maneuver [toNext] meters away, or a fixed
     close view on foot or by bike.
     */
    public static func view(speed: Double, toNext: Double?, next: ManeuverType?, driving: Bool) -> View {
        guard driving else { return View(across: 300, pitch: 50) }
        let v = max(0, speed)
        var across = min(1400, max(450, 300 + v * 30))
        var pitch = 50.0
        if let d = toNext, let t = next {
            let turning = t != .straight && t != .arrive && t != .depart && t != .unknown
            if turning && d < nearStart {
                // 1 at 300 m out, 0 from 60 m in: slide from the normal view to the close one.
                let f = max(0, min(1, (d - nearEnd) / (nearStart - nearEnd)))
                let close = max(330, v * 14)
                if close < across { across = close + (across - close) * f }
                pitch = 35 + 15 * f
            } else {
                // A long way to the next turn: pull back and look further ahead, a bit more the longer it is.
                let f = max(0, min(1, (d - 600) / 800))
                across = min(1800, across * (1 + 0.25 * f))
                pitch = 50 + 5 * f
            }
            // Close to a roundabout, the whole of it and its exits fill the view.
            if t == .roundabout && d < 350 { across = min(across, 380) }
        }
        return View(across: across, pitch: pitch)
    }

    /** How far ahead the next lower limit shows: about 15 seconds at your speed, 200 to 600 m. */
    public static func limitHeadsUp(speed: Double) -> Double { min(600, max(200, max(0, speed) * 15)) }
}

/** How close the driving map sits, picked in Settings. Normal is the zoom Kite always had. */
public enum MapZoom: String, CaseIterable, Sendable {
    case closer, normal, wider

    public var title: String {
        switch self {
        case .closer: return "Closer"
        case .normal: return "Normal"
        case .wider: return "Wider"
        }
    }

    /** Times the normal distance across the screen. */
    public var scale: Double {
        switch self {
        case .closer: return 0.7
        case .normal: return 1
        case .wider: return 1.4
        }
    }
}

/** Which way the map looks: tilted toward the road ahead, flat facing ahead, or flat with north up. */
public enum MapLook: String, CaseIterable, Sendable {
    case tilted, flat, north

    /** The next one for the map button: 3D, then 2D, then north up, then round again. */
    public var next: MapLook {
        switch self {
        case .tilted: return .flat
        case .flat: return .north
        case .north: return .tilted
        }
    }

    /** What the button says for a moment after a tap. */
    public var title: String {
        switch self {
        case .tilted: return "3D view"
        case .flat: return "2D view"
        case .north: return "North up"
        }
    }

    public var detail: String {
        switch self {
        case .tilted: return "Tilted toward the road ahead"
        case .flat: return "Flat, facing the way you go"
        case .north: return "Flat, with north at the top"
        }
    }
}

public extension NavZoom.View {
    /** This view with the zoom setting and the map button's choice applied. */
    func applying(_ zoom: MapZoom, _ look: MapLook) -> NavZoom.View {
        NavZoom.View(across: across * zoom.scale, pitch: look == .tilted ? pitch : 0)
    }
}
