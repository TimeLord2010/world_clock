import SwiftUI
import WidgetKit

// MARK: - Timeline: one entry every 30 minutes, like the app's refresh
// interval. 48 entries = 24h of ticks, so the system only requests a new
// timeline once a day. Each entry carries its instant; the map is rendered
// with the solar light of that exact moment.

struct MapEntry: TimelineEntry {
    let date: Date
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MapEntry {
        MapEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (MapEntry) -> Void) {
        completion(MapEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MapEntry>) -> Void) {
        let tick: TimeInterval = 30 * 60
        let now = Date()
        var entries: [MapEntry] = []
        for i in 0..<48 {
            entries.append(MapEntry(date: Date(timeIntervalSince1970: now.timeIntervalSince1970 + Double(i) * tick)))
        }
        let timeline = Timeline(entries: entries, policy: .after(entries.last!.date))
        completion(timeline)
    }
}

// MARK: - View: renders the widget-sized bitmap edge to edge

/// Layout of the dot map inside the widget frame.
///
/// The frame and the projection have different aspects, and a plain
/// aspect-fit leaves a dark band — the visible "padding" — on two sides.
/// The widget fixes that WITHOUT cropping the map, using two knobs:
///
/// 1. **Latitude window.** A uniform equirectangular map of the whole world
///    is exactly 2:1 (360° x 180°), while the wide widget frame is ~2.1:1.
///    Below the last land dot (-55.5°) the dataset has no topography at all:
///    the southern band is just the faint ocean grid — the void where
///    Antarctica would be. The widget drops that band and widens the window
///    until its aspect matches its own frame, so the map fills the frame edge
///    to edge with no distortion and no dot lost. The app keeps ±90.
/// 2. **Safety inset.** 2 pt is the smallest inset that keeps every LAND dot
///    clear of the rounded-corner mask (measured against the real dataset:
///    at 1 pt the dateline dots at lon ±179.5, lat 66-71 fall under the
///    corner curve; at 0 pt they are rounded away).
enum WidgetLayout {
    /// Latitude window (top = 90 always) matched to the frame's aspect.
    ///
    /// Clamped so it never exceeds the whole world (a square frame therefore
    /// keeps the full 2:1 map, as before) and never reaches the southern
    /// land, which runs down to -55.5.
    static func latitudeWindow(container: CGSize, inset: CGFloat) -> (top: Double, bottom: Double) {
        let w = Double(container.width - 2 * inset)
        let h = Double(container.height - 2 * inset)
        guard w > 0, h > 0 else { return (90, -90) }
        let span = min(max(360 * h / w, 150), 180)
        return (90, 90 - span)
    }

    /// Safety inset in logical points (see above).
    static let inset: CGFloat = 2
}

struct WorldClockWidgetView: View {
    @Environment(\.displayScale) var displayScale
    let entry: MapEntry

    private static let renderer = WorldDotMapRenderer.loadDefault()

    /// Display scale of the widget surface (fallback 2.0), used both to
    /// render the bitmap at physical resolution and to size it 1:1.
    private var dpr: CGFloat { displayScale > 0 ? displayScale : 2.0 }

    private func mapImage(container: CGSize, window: (top: Double, bottom: Double)) -> CGImage? {
        guard let renderer = Self.renderer else { return nil }
        // The renderer draws the map over the whole canvas with its internal
        // safety inset, so the view just fills the frame — there is no
        // uncovered area where a system background could show.
        return renderer.render(now: entry.date, width: container.width,
                               height: container.height, dpr: dpr,
                               marginPt: Double(WidgetLayout.inset),
                               latBottom: window.bottom)
    }

    var body: some View {
        // Canvas draws the bitmap synchronously in the widget's own render
        // pass — no AppKit NSImage involvement. (Image(nsImage:) with a
        // runtime-generated image could render blank while the extension
        // process is suspended in the background, e.g. desktop unfocused.)
        //
        // The canvas draws ONLY the dots (transparent elsewhere); the dark
        // panel comes from containerBackground below. This separation is
        // what keeps the widget alive: when the desktop loses focus chronod
        // re-renders desktop widgets with backgroundViewPolicy=Remove
        // (strips the background layer so the wallpaper shows through). A
        // single fully-opaque bitmap (map+background fused) leaves nothing
        // after the strip → blank widget. Real content layers survive.
        Canvas(opaque: false) { context, size in
            let window = WidgetLayout.latitudeWindow(container: size, inset: WidgetLayout.inset)
            if let image = mapImage(container: size, window: window) {
                // Image(decorative:scale: dpr) gives the bitmap a point size
                // equal to the canvas size, so this draw is a 1:1 blit —
                // no resampling, dots stay crisp.
                context.draw(Image(decorative: image, scale: dpr),
                             in: CGRect(origin: .zero, size: size))
            }
        }
        .containerBackground(for: .widget) {
            Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)
        }
    }
}

// MARK: - Widget

struct WorldClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorldClockWidget", provider: Provider()) { entry in
            WorldClockWidgetView(entry: entry)
        }
        .configurationDisplayName("World Clock")
        .description("Mapa-múndi com a luz solar atual")
        .supportedFamilies([.systemSmall, .systemMedium])
        // Remove the system default content margins so the map bleeds to
        // the widget's edge (the map fills the full content frame already).
        .contentMarginsDisabled()
    }
}

@main
struct WorldClockWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorldClockWidget()
    }
}
