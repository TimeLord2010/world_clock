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

// MARK: - View: the dot-matrix world map, 2:1, pixel-crisp

struct WorldClockWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: MapEntry

    private static let renderer = WorldDotMapRenderer.loadDefault()

    private var mapSize: CGSize {
        // Map keeps its 2:1 aspect inside the widget frame.
        let width: CGFloat = family == .systemSmall ? 160 : 320
        return CGSize(width: width, height: width / 2)
    }

    private var mapImage: CGImage? {
        guard let renderer = Self.renderer else { return nil }
        let dpr = NSScreen.main?.backingScaleFactor ?? 2.0
        return renderer.render(now: entry.date, width: mapSize.width, height: mapSize.height, dpr: dpr)
    }

    var body: some View {
        Group {
            if let image = mapImage {
                Image(nsImage: NSImage(cgImage: image, size: mapSize))
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(2, contentMode: .fit)
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
    }
}

@main
struct WorldClockWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorldClockWidget()
    }
}
