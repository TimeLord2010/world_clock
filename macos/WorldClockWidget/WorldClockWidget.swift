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

// MARK: - View: the dot-matrix world map, filling the whole widget

struct WorldClockWidgetView: View {
    @Environment(\.displayScale) var displayScale
    let entry: MapEntry

    private static let renderer = WorldDotMapRenderer.loadDefault()

    /// Map size that covers [container] while keeping the 2:1 aspect:
    /// width = max(containerW, 2*containerH). The widget frame then clips
    /// the overflow, so the map fills the widget edge to edge (no empty
    /// bands top/bottom or left/right).
    private func fillSize(_ container: CGSize) -> CGSize {
        let w = max(container.width, container.height * 2)
        return CGSize(width: w, height: w / 2)
    }

    private func mapImage(container: CGSize) -> CGImage? {
        guard let renderer = Self.renderer else { return nil }
        let size = fillSize(container)
        let dpr = displayScale > 0 ? displayScale : 2.0
        return renderer.render(now: entry.date, width: size.width, height: size.height, dpr: dpr)
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image = mapImage(container: geo.size) {
                    Image(nsImage: NSImage(cgImage: image, size: fillSize(geo.size)))
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
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
