import AppKit
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

struct WorldClockWidgetView: View {
    @Environment(\.displayScale) var displayScale
    let entry: MapEntry

    private static let renderer = WorldDotMapRenderer.loadDefault()

    private func mapImage(container: CGSize) -> CGImage? {
        guard let renderer = Self.renderer else { return nil }
        let dpr = displayScale > 0 ? displayScale : 2.0
        // The renderer draws the FULL widget canvas (background + map with
        // its internal safety margin), so the view just fills the frame —
        // there is no uncovered area where a system background could show.
        return renderer.render(now: entry.date, width: container.width, height: container.height, dpr: dpr)
    }

    var body: some View {
        GeometryReader { geo in
            if let image = mapImage(container: geo.size) {
                Image(nsImage: NSImage(cgImage: image, size: geo.size))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
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
