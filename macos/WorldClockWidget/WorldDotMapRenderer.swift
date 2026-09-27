import CoreGraphics
import Foundation

/// Renders the dot-matrix world map with real solar illumination — Swift
/// port of `WorldDotMap` + `_DotPainter` (lib/world_dot_map.dart).
///
/// Produces a bitmap (CGImage) on demand with TWO dot layers:
///
/// * land — the dataset dots (`#FF9800`), exactly as before;
/// * ocean — every cell of the 1° grid whose center is NOT a land dot
///   (`#6E6E6E`, dimmer), i.e. the complement of the land set.
///
/// Both layers share the grid, the adaptive decimation (stride 1/2/4 by
/// containing cell, floor) and the dot size; each has its own minimum
/// brightness, and the moment's sun altitude (via [SunShading]) drives both.
struct WorldDotMapRenderer {
    let dots: [(lon: Double, lat: Double)]
    let ocean: [(lon: Double, lat: Double)]

    // Identidade visual do app (defaults do WorldDotMap).
    let backgroundColor: (r: Double, g: Double, b: Double) = (17 / 255, 17 / 255, 17 / 255) // #111111
    let dotColor: (r: Double, g: Double, b: Double) = (1.0, 152 / 255, 0) // #FF9800
    // Parity with the Flutter painter (world_dot_map.dart): 0.30 keeps the
    // night side readable against #111111 (0.10 was too dark).
    static let minBrightness = 0.30
    let oceanColor: (r: Double, g: Double, b: Double) = (110 / 255, 110 / 255, 110 / 255) // #6E6E6E
    /// Ocean night floor — dimmer than the land, so the continents stay the
    /// brightest thing on the night side.
    static let oceanMinBrightness = 0.15

    /// Grid of the projection: 1° cells, 360 columns × 180 rows.
    static let gridColumns = 360
    static let gridRows = 180

    private static var cached: (key: String, image: CGImage)?

    /// Parses the dataset JSON (`[[lon, lat], ...]`) and derives the ocean
    /// layer (the grid complement of the land dots).
    init?(jsonData: Data) {
        guard let raw = try? JSONSerialization.jsonObject(with: jsonData) as? [[Double]],
              !raw.isEmpty else { return nil }
        let land = raw.map { (lon: $0[0], lat: $0[1]) }
        dots = land
        ocean = WorldDotMapRenderer.oceanCells(land: land)
    }

    /// Loads the dataset bundled with the widget extension.
    static func loadDefault() -> WorldDotMapRenderer? {
        guard let url = Bundle.main.url(forResource: "world_dots", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return WorldDotMapRenderer(jsonData: data)
    }

    /// Index of the grid cell that CONTAINS the point — same as
    /// `WorldDotMap.cellKey` (dataset dots sit at cell centers .5).
    static func cellKey(lon: Double, lat: Double) -> Int {
        Int(floor(lon + 180)) * gridRows + Int(floor(90 - lat))
    }

    /// The ocean cells: every grid center that is NOT a land dot.
    static func oceanCells(land: [(lon: Double, lat: Double)]) -> [(lon: Double, lat: Double)] {
        var occupied = Set<Int>(minimumCapacity: land.count)
        for dot in land { occupied.insert(cellKey(lon: dot.lon, lat: dot.lat)) }
        var cells: [(lon: Double, lat: Double)] = []
        cells.reserveCapacity(gridColumns * gridRows - land.count)
        for row in 0..<gridRows {
            let lat = 89.5 - Double(row)
            for col in 0..<gridColumns where !occupied.contains(col * gridRows + row) {
                cells.append((lon: -179.5 + Double(col), lat: lat))
            }
        }
        return cells
    }

    /// Adaptive decimation — same thresholds as `_DotPainter._strideFor`.
    func stride(widthLogical: CGFloat, dpr: CGFloat) -> Int {
        let cellPx = Double(widthLogical) * Double(dpr) / Double(WorldDotMapRenderer.gridColumns)
        return cellPx >= 4 ? 1 : (cellPx >= 2 ? 2 : 4)
    }

    /// Whether the dot survives decimation — same as `WorldDotMap.keepDot`
    /// (containing cell via floor; dataset sits at cell centers .5).
    func keepDot(lon: Double, lat: Double, stride: Int) -> Bool {
        if stride == 1 { return true }
        let col = Int(floor(lon + 180))
        let row = Int(floor(90 - lat))
        return col % stride == 0 && row % stride == 0
    }

    /// Renders the map for instant [now] into physical pixels
    /// (width/height logical × dpr). Cached per (minute, size).
    ///
    /// The bitmap covers the whole widget: the `#111111` background fills
    /// every pixel, and the 2:1 map is drawn centered inside with a small
    /// safety margin. The margin is part of OUR drawing — there is no area
    /// where the system widget background could show through.
    func render(now: Date, width: CGFloat, height: CGFloat, dpr: CGFloat) -> CGImage {
        let wPhys = Int((Double(width) * Double(dpr)).rounded())
        let hPhys = Int((Double(height) * Double(dpr)).rounded())
        guard wPhys > 0, hPhys > 0 else { return emptyImage(width: wPhys, height: hPhys) }

        let minute = Int(now.timeIntervalSince1970 / 60)
        let key = "\(minute)-\(wPhys)x\(hPhys)"
        if let c = Self.cached, c.key == key { return c.image }

        // Safety margin inside our own canvas (5pt logical).
        let marginPx = max(1, (5 * Double(dpr)).rounded())
        let availW = Double(wPhys) - 2 * marginPx
        let availH = Double(hPhys) - 2 * marginPx
        let mapW = min(availW, availH * 2)
        let mapH = mapW / 2
        let originX = (Double(wPhys) - mapW) / 2
        let originY = (Double(hPhys) - mapH) / 2

        // Decimation by the MAP width (not the widget width).
        let cellPx = mapW / Double(WorldDotMapRenderer.gridColumns)
        let stride = stride(widthLogical: mapW / Double(dpr), dpr: dpr)
        var dotPx = (cellPx * Double(stride) * 0.5).rounded()
        if dotPx < 1 { dotPx = 1 }

        guard let ctx = CGContext(
            data: nil, width: wPhys, height: hPhys,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return emptyImage(width: wPhys, height: hPhys) }

        // NO background fill here: the bitmap must stay TRANSPARENT outside
        // the dots. The dark #111111 panel comes from the view's
        // containerBackground; fusing an opaque background into this bitmap
        // made chronod treat the whole widget as background-only and strip
        // it (backgroundViewPolicy=Remove) when the desktop loses focus.

        ctx.setShouldAntialias(true)

        // Ocean first: land is drawn on top of the water.
        paint(cells: ocean, color: oceanColor, minBrightness: Self.oceanMinBrightness,
              ctx: ctx, now: now, stride: stride, dotPx: dotPx,
              originX: originX, originY: originY, mapW: mapW, mapH: mapH, hPhys: hPhys)
        paint(cells: dots, color: dotColor, minBrightness: Self.minBrightness,
              ctx: ctx, now: now, stride: stride, dotPx: dotPx,
              originX: originX, originY: originY, mapW: mapW, mapH: mapH, hPhys: hPhys)

        let image = ctx.makeImage() ?? emptyImage(width: wPhys, height: hPhys)
        Self.cached = (key, image)
        return image
    }

    /// Paints one dot layer, shading every dot by the sun altitude at its
    /// position ([SunShading]).
    ///
    /// Brightness is encoded in the dot's ALPHA (pure dot color), not in a
    /// color lerp: composited over the #111111 panel this yields the same
    /// shade as the Flutter lerp (color×α + bg×(1−α)), and when the system
    /// shows the widget in its monochrome treatment (desktop unfocused) it
    /// fills the alpha mask with white — so the day/night shading survives
    /// as gray tones, like Apple's clock widgets. With uniform alpha it
    /// flattened to all-white.
    private func paint(cells: [(lon: Double, lat: Double)],
                       color: (r: Double, g: Double, b: Double),
                       minBrightness: Double,
                       ctx: CGContext, now: Date, stride: Int, dotPx: Double,
                       originX: Double, originY: Double,
                       mapW: Double, mapH: Double, hPhys: Int) {
        let half = dotPx / 2

        for dot in cells {
            guard keepDot(lon: dot.lon, lat: dot.lat, stride: stride) else { continue }

            let t = SunShading.intensity(latDeg: dot.lat, lonDeg: dot.lon, now: now)
            let level = minBrightness + t * (1 - minBrightness)
            ctx.setFillColor(CGColor(red: color.r, green: color.g,
                                     blue: color.b, alpha: level))

            // Pixel-snapped center inside the map rect; CGContext y grows
            // upward, so flip.
            let x = (originX + (dot.lon + 180) / 360 * mapW).rounded()
            let yScreen = (originY + (90 - dot.lat) / 180 * mapH).rounded()
            let y = Double(hPhys) - yScreen
            ctx.fillEllipse(in: CGRect(x: x - half, y: y - half, width: dotPx, height: dotPx))
        }
    }

    private func emptyImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: max(width, 1), height: max(height, 1),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: backgroundColor.r, green: backgroundColor.g,
                                 blue: backgroundColor.b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: max(width, 1), height: max(height, 1)))
        return ctx.makeImage()!
    }
}
