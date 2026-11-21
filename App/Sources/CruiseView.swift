import SwiftUI
import VelaCore

/**
 * The driving view with no route: the warning card up top (a speed camera or a Waze report), the
 * speed sign bottom left, and one slim bar with ✕. The road's name is written on the road itself.
 */
struct CruiseOverlay: View {
    @ObservedObject var model: AppModel
    @ObservedObject var cruise: Cruise
    @Environment(\.colorScheme) private var scheme
    @Environment(\.sidePanel) private var panel

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                // One warning at a time, nearest first, like on a route; a camera you're speeding at always wins.
                if let cam = cruise.cameraAhead, cameraFirst {
                    CameraCard(alert: cam, speedKmh: cruise.speedMps * 3.6, roadLimitKmh: cruise.limitKmh)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if let w = cruise.wazeAhead {
                    WazeCard(ahead: w)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture { withAnimation { cruise.dismissWaze() } }
                        .accessibilityHint("Tap to hide")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .inSidePanel(panel)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: cruise.cameraAhead?.startMeters)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: cruise.wazeAhead?.alert.id)

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                SpeedBadge(mps: cruise.speedMps, limitKmh: cruise.limitKmh)
                Spacer()
            }
            .padding(.horizontal, 16)
            if !model.browseFollowing {
                Button { model.recenterCruise() } label: {
                    Label("Re-centre", systemImage: "location.north.line.fill")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.horizontal, 22).frame(height: 52)
                        .foregroundColor(Vela.onAccent(scheme))
                        .background(Capsule().fill(Vela.accent(scheme)))
                        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.leading, panel)
            }
            CruiseBar(ref: cruise.ref) { model.endCruise(closed: true) }
                .inSidePanel(panel)
        }
    }

    /** The camera's card goes first when it's nearer, or when you're over its limit. */
    private var cameraFirst: Bool {
        guard let c = cruise.cameraAhead else { return false }
        guard let w = cruise.wazeAhead else { return true }
        if let limit = c.limitKmh ?? cruise.limitKmh, cruise.speedMps * 3.6 > limit + 3 { return true }
        return c.meters <= w.meters
    }
}

/** ✕, then "Driving" and the road's number: no arrival time, since there's no route. */
struct CruiseBar: View {
    let ref: String?
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundColor(scheme == .dark ? Color(hex: 0xFCA5A5) : Vela.closed)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to the map")
            HStack(spacing: 10) {
                Image(systemName: "car.fill").font(.system(size: 18, weight: .bold)).foregroundColor(Vela.accentText(scheme))
                Text("Driving").font(.system(size: 22, weight: .heavy))
                if let ref {
                    Text(ref)
                        .font(.system(size: 16, weight: .heavy))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundColor(ref.hasPrefix("M") ? .white : Color(hex: 0xFFD200))
                        .background(RoundedRectangle(cornerRadius: 5).fill(ref.hasPrefix("M") ? Color(hex: 0x0067B1) : Color(hex: 0x00703C)))
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            // Balances the ✕ so "Driving" sits in the middle.
            Color.clear.frame(width: 56, height: 56)
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 6)
        .frame(height: 64)
        .glass(Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}
