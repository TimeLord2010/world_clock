import CoreGraphics
import Foundation

/// Renders the dot-matrix world map with real solar illumination — Swift
/// port of `WorldDotMap` + `_DotPainter` (lib/world_dot_map.dart).
///
/// Produces a bitmap (CGImage) on demand: background `#111111`, dots
/// `#FF9800` shaded by [SunShading] (night = lerp toward the background,
/// minimum 10% brightness), pixel-snapped centers, adaptive decimation
/// (stride 1/2/4 by containing cell, floor — same as the Flutter side).
struct WorldDotMapRenderer {
    let dots: [(lon: Double, lat: Double)]

    // Identidade visual do app (defaults do WorldDotMap).
    let backgroundColor: (r: Double, g: Double, b: Double) = (17 / 255, 17 / 255, 17 / 255) // #111111
    let dotColor: (r: Double, g: Double, b: Double) = (1.0, 152 / 255, 0) // #FF9800
    static let minBrightness = 0.10

    private static var cached: (key: String, image: CGImage)?

    /// Parses the dataset JSON (`[[lon, lat], ...]`).
    init?(jsonData: Data) {
        guard let raw = try? JSONSerialization.jsonObject(with: jsonData) as? [[Double]],
              !raw.isEmpty else { return nil }
        dots = raw.map { (lon: $0[0], lat: $0[1]) }
    }

    /// Loads the dataset bundled with the widget extension.
    static func loadDefault() -> WorldDotMapRenderer? {
        guard let url = Bundle.main.url(forResource: "world_dots", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return WorldDotMapRenderer(jsonData: data)
    }

    /// Adaptive decimation — same thresholds as `_DotPainter._strideFor`.
    func stride(widthLogical: CGFloat, dpr: CGFloat) -> Int {
        let cellPx = Double(widthLogical) * Double(dpr) / 360
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
    func render(now: Date, width: CGFloat, height: CGFloat, dpr: CGFloat) -> CGImage {
        let wPhys = Int((Double(width) * Double(dpr)).rounded())
        let hPhys = Int((Double(height) * Double(dpr)).rounded())
        guard wPhys > 0, hPhys > 0 else { return emptyImage(width: wPhys, height: hPhys) }

        let minute = Int(now.timeIntervalSince1970 / 60)
        let key = "\(minute)-\(wPhys)x\(hPhys)"
        if let c = Self.cached, c.key == key { return c.image }

        let cellPx = Double(wPhys) / 360
        let stride = stride(widthLogical: width, dpr: dpr)
        var dotPx = (cellPx * Double(stride) * 0.5).rounded()
        if dotPx < 1 { dotPx = 1 }

        guard let ctx = CGContext(
            data: nil, width: wPhys, height: hPhys,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return emptyImage(width: wPhys, height: hPhys) }

        ctx.setFillColor(CGColor(red: backgroundColor.r, green: backgroundColor.g,
                                 blue: backgroundColor.b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: wPhys, height: hPhys))

        ctx.setShouldAntialias(true)
        let half = dotPx / 2
        var prevColor = (r: -1.0, g: 0.0, b: 0.0) // force first set

        for dot in dots {
            guard keepDot(lon: dot.lon, lat: dot.lat, stride: stride) else { continue }

            let t = SunShading.intensity(latDeg: dot.lat, lonDeg: dot.lon, now: now)
            let level = Self.minBrightness + t * (1 - Self.minBrightness)
            let r = backgroundColor.r + (dotColor.r - backgroundColor.r) * level
            let g = backgroundColor.g + (dotColor.g - backgroundColor.g) * level
            let b = backgroundColor.b + (dotColor.b - backgroundColor.b) * level
            if r != prevColor.r || g != prevColor.g || b != prevColor.b {
                ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
                prevColor = (r, g, b)
            }

            // Pixel-snapped center; CGContext y grows upward, so flip.
            let x = ((dot.lon + 180) / 360 * Double(wPhys)).rounded()
            let yScreen = ((90 - dot.lat) / 180 * Double(hPhys)).rounded()
            let y = Double(hPhys) - yScreen
            ctx.fillEllipse(in: CGRect(x: x - half, y: y - half, width: dotPx, height: dotPx))
        }

        let image = ctx.makeImage() ?? emptyImage(width: wPhys, height: hPhys)
        Self.cached = (key, image)
        return image
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
