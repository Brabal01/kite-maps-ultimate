import AVFoundation
import OSLog
import CoreLocation
import Foundation
import UIKit
import VelaCore

/**
 * Driving with no route: Kite noticed you set off (faster than walking pace for a few seconds) and
 * switched to its driving view by itself. No turns and no arrival time, but the road you're on, its
 * speed limit, your speed and speed cameras ahead, the same as on a route. Ends by itself once you've
 * been parked for two minutes, or with the ✕.
 */
@MainActor
final class Cruise: ObservableObject {
    /** The road under you ("Bassett Avenue") and its number ("A33"), from the road matcher. */
    @Published private(set) var road: String?
    @Published private(set) var ref: String?
    /** The posted limit here, in km/h; nil when the map doesn't say (never guessed). */
    @Published private(set) var limitKmh: Double?
    @Published private(set) var speedMps: Double = 0
    @Published private(set) var cameraAhead: CameraAlert?
    /** A police car, crash or hazard reported by Waze drivers just ahead. */
    @Published private(set) var wazeAhead: WazeAhead?
    /** The last good fix and which way you're going, for the map. */
    @Published private(set) var fix: CLLocation?

    /** The last few hundred metres driven, oldest first: what the road matcher places you with. */
    private var trace: [CLLocation] = []
    private var askedAt = Date.distantPast
    private var askedFrom: CLLocation?
    private var asking = false
    private var cameras: [Int64: RoadCamera] = [:]
    private var camerasFrom: CLLocation?
    private var camerasLoading = false
    private var warned: Set<Int64> = []
    private var cameraId: Int64?
    private var stoppedSince: Date?
    private var waze: [WazeAlert] = []
    private var wazeFrom: CLLocation?
    private var wazeAt = Date.distantPast
    private var wazeLoading = false
    private var wazeWarned: Set<String> = []
    private var wazeHidden: Set<String> = []
    private let speech = AVSpeechSynthesizer()
    private static let log = Logger(subsystem: "app.vela.ios", category: "voice")
    /** Called when you've been parked long enough for the driving view to end. */
    var onParked: (() -> Void)?

    init() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        speech.stopSpeaking(at: .immediate)
    }

    /** Made-up values for the build's screenshots: real fixes are ignored from then on. */
    private var demo = false
    var isDemo: Bool { demo }

    func showDemo(_ loc: CLLocation, road: String, ref: String?, limitKmh: Double) {
        demo = true
        fix = loc
        speedMps = loc.speed
        self.road = road
        self.ref = ref
        self.limitKmh = limitKmh
    }

    /** Every GPS fix while the driving view is up. */
    func handle(_ loc: CLLocation) {
        guard !demo, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 65 else { return }
        fix = loc
        speedMps = max(0, loc.speed)
        // Parked: two minutes under walking pace ends it (a red light or a queue is shorter than that).
        if loc.speed >= 0 && loc.speed < 1.5 {
            if stoppedSince == nil { stoppedSince = loc.timestamp }
            if let s = stoppedSince, loc.timestamp.timeIntervalSince(s) > 120 { onParked?(); return }
        } else {
            stoppedSince = nil
        }
        if let last = trace.last, last.distance(from: loc) < 8 {
            // Barely moved: no new point, so a stop at the lights doesn't fill the trace with one spot.
        } else {
            trace.append(loc)
        }
        // About 400 m of road is plenty to know which road you're on.
        while trace.count > 2, let first = trace.first, let l = trace.last, first.distance(from: l) > 400 { trace.removeFirst() }
        whereAmI(loc)
        loadCameras(loc)
        checkCameras(loc)
        loadWaze(loc)
        checkWaze(loc)
    }

    /** Drivers' reports within about 4 km, asked again every 90 seconds or 2 km. */
    private func loadWaze(_ loc: CLLocation) {
        guard AppSettings.shared.wazeOn, !wazeLoading,
              Date().timeIntervalSince(wazeAt) > 90 || (wazeFrom.map { $0.distance(from: loc) > 2_000 } ?? true) else { return }
        wazeLoading = true
        wazeAt = Date()
        wazeFrom = loc
        let c = loc.coordinate
        let dLat = 0.036, dLng = 0.036 / max(cos(c.latitude * .pi / 180), 0.2)
        let box = (s: c.latitude - dLat, w: c.longitude - dLng, n: c.latitude + dLat, e: c.longitude + dLng)
        let here = LatLng(c.latitude, c.longitude)
        Task {
            async let closures = Waze.alerts(south: box.s, west: box.w, north: box.n, east: box.e)
            let live = await WazeLive.shared.alerts(boxes: [box], near: here)
            let fromMap = await closures
            wazeLoading = false
            guard fromMap != nil || live != nil else { return }
            var merged: [String: WazeAlert] = [:]
            for a in (fromMap ?? []) + (live ?? []) { merged[a.id] = a }
            waze = Array(merged.values)
            WazeHistory.shared.record(waze)
        }
    }

    /** The nearest report ahead worth a card: like on a route, a little earlier than a camera. */
    private func checkWaze(_ loc: CLLocation) {
        let s = AppSettings.shared
        guard s.wazeOn, loc.course >= 0, loc.speed > 3 else {
            if loc.speed > 3 || !s.wazeOn { wazeAhead = nil }
            return
        }
        let here = LatLng(loc.coordinate.latitude, loc.coordinate.longitude)
        let reach = min(max(loc.speed * 20, 250), 1200)
        var best: (WazeAlert, Double)?
        for a in waze where a.kind != .jam && !wazeHidden.contains(a.id) && s.shows(a) {
            guard let d = CruiseCameras.distanceAhead(a.location, at: here, heading: loc.course, reach: reach) else { continue }
            if best.map({ d < $0.1 }) ?? true { best = (a, d) }
        }
        guard let (a, d) = best else { wazeAhead = nil; return }
        let same = wazeAhead?.alert.id == a.id
        wazeAhead = WazeAhead(alert: a, meters: d, startMeters: same ? max(wazeAhead?.startMeters ?? d, d) : d)
        if !same, !wazeWarned.contains(a.id) {
            wazeWarned.insert(a.id)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if s.voice, s.wazeVoice, a.kind == .police { say("Police reported ahead.") }
        }
    }

    /** Tapped away: that report stays hidden for the rest of this drive. */
    func dismissWaze() {
        if let id = wazeAhead?.alert.id { wazeHidden.insert(id) }
        wazeAhead = nil
    }

    /** Asks the road matcher every few seconds while moving (and never two at once). */
    private func whereAmI(_ loc: CLLocation) {
        guard !asking, trace.count >= 3, Date().timeIntervalSince(askedAt) > 4,
              askedFrom.map({ $0.distance(from: loc) > 40 }) ?? true else { return }
        asking = true
        askedAt = Date()
        askedFrom = loc
        let points = trace.map { LatLng($0.coordinate.latitude, $0.coordinate.longitude) }
        Task {
            let here = await Valhalla.here(trace: points)
            asking = false
            // No answer keeps what was known: a blank sign every time the server is slow helps no one.
            guard let here else { return }
            road = here.road
            ref = here.ref
            limitKmh = here.kmh
        }
    }

    /** The speed cameras within about 5 km, asked again every 3 km driven. */
    private func loadCameras(_ loc: CLLocation) {
        let s = AppSettings.shared
        guard s.speedCameras, !camerasLoading, camerasFrom.map({ $0.distance(from: loc) > 3_000 }) ?? true else { return }
        camerasLoading = true
        camerasFrom = loc
        let c = loc.coordinate
        let dLat = 0.045, dLng = 0.045 / max(cos(c.latitude * .pi / 180), 0.2)
        Task {
            let found = await Overpass.cameras(south: c.latitude - dLat, west: c.longitude - dLng,
                                               north: c.latitude + dLat, east: c.longitude + dLng, speed: true, plate: false)
            camerasLoading = false
            // A busy server: try again after another kilometre rather than straight away.
            guard let found else { camerasFrom = loc; return }
            for cam in found { cameras[cam.id] = cam }
        }
    }

    private func checkCameras(_ loc: CLLocation) {
        let s = AppSettings.shared
        guard s.speedCameras, loc.course >= 0, loc.speed > 3 else {
            if cameraAhead != nil, loc.speed <= 3 { return }
            cameraAhead = nil
            return
        }
        var all = Array(cameras.values)
        if s.wazeOn { all = WazeCameras.merge(all, waze: WazeCameras.shared.known()) }
        let here = LatLng(loc.coordinate.latitude, loc.coordinate.longitude)
        guard let found = CruiseCameras.ahead(all, at: here, heading: loc.course, speedMps: loc.speed) else {
            cameraAhead = nil
            cameraId = nil
            return
        }
        let first = cameraId != found.camera.id
        cameraId = found.camera.id
        cameraAhead = CameraAlert(kind: .speed, meters: found.meters,
                                  startMeters: first ? found.meters : max(cameraAhead?.startMeters ?? found.meters, found.meters),
                                  limitKmh: found.camera.maxspeedKmh ?? limitKmh)
        if first, !warned.contains(found.camera.id) {
            warned.insert(found.camera.id)
            if s.voice, s.cameraWarnings { say("Speed camera ahead.") }
        }
    }

    private func say(_ text: String) {
        Cruise.log.info("say: \(text, privacy: .public)")
        if Navigator.silent { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = Navigator.voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        speech.speak(u)
    }

    /**
     * Whether to switch to the driving view: going faster than a brisk run (about 15 mph) for six
     * seconds in a row, with a good fix. [moving] is when that started, kept by the caller.
     */
    static func shouldStart(_ loc: CLLocation, movingSince: inout Date?) -> Bool {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 50, loc.speed >= 6.7 else {
            movingSince = nil
            return false
        }
        if movingSince == nil { movingSince = loc.timestamp }
        return loc.timestamp.timeIntervalSince(movingSince!) >= 6
    }
}
