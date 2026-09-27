import 'dart:convert';
import 'dart:ui' show Offset, PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'world_sun.dart';

/// A dot-matrix world map with real solar illumination.
///
/// Renders the WHOLE 1° grid of the equirectangular projection (2:1 aspect,
/// 360 columns × 180 rows) as dots, in two layers:
///
/// * **land** — the dots from [assets/world_dots.json] (Natural Earth,
///   public domain), painted in [dotColor];
/// * **ocean** — every cell of the grid whose center is NOT one of those
///   land dots, painted in [oceanColor] (default: neutral mid gray). The ocean
///   is therefore the exact complement of the land set: no extra dataset and
///   no extra asset, it is
///   derived at load time by [WorldDotMap.oceanCells].
///
/// Both layers are shaded by the actual sun position at [now]: cells in
/// daylight are bright, cells in darkness fade into [backgroundColor] with
/// a smooth twilight ramp. Pass a fresh [now] periodically (e.g. once a
/// minute) so the day/night boundary keeps moving.
///
/// The widget is self-contained: it loads and caches the asset once per app
/// run, then paints each layer in a handful of `drawPoints` calls (one per
/// brightness bucket, regardless of dot count).
class WorldDotMap extends StatefulWidget {
  const WorldDotMap({
    super.key,
    this.backgroundColor = defaultBackgroundColor,
    this.dotColor = defaultDotColor,
    this.oceanColor = defaultOceanColor,
    this.now,
    this.includeTwilight = false,
  });

  /// Background behind the map.
  final Color backgroundColor;

  /// Color of the land dots in full daylight.
  final Color dotColor;

  /// Color of the ocean dots in full daylight (the shading only ever lerps
  /// from the background up to this color, so this is the brightest the
  /// water gets).
  ///
  /// Pass [backgroundColor] to switch the ocean layer off: the map then
  /// paints exactly the land dots it painted before.
  final Color oceanColor;

  /// Reference instant for the solar shading. When null, [DateTime.now] is
  /// used each time the painter repaints.
  final DateTime? now;

  /// Whether the shading waits for the twilight: with it, a dot only reaches
  /// full darkness once the sun is 6° BELOW the horizon (civil twilight), so
  /// the map stops reading "night" while the sky is still lit. Off (default)
  /// keeps the original ramp — night starts at the horizon.
  final bool includeTwilight;

  /// Default daylight color of the ocean: a neutral gray — dark enough that
  /// the sea texture never competes with the orange continents (the previous
  /// #6E6E6E read as too light, especially on the desktop widget, where the
  /// generic-RGB → sRGB re-encode lit it up to ~129).
  static const Color defaultOceanColor = Color(0xFF5A5A5A);

  /// Default background behind the map: the app's near-black. Named so the
  /// palettes in `map_theme.dart` can point at it instead of repeating the
  /// literal (a theme and this default drifting apart was silent before).
  static const Color defaultBackgroundColor = Color(0xFF111111);

  /// Default daylight color of the land dots: the app's orange.
  static const Color defaultDotColor = Color(0xFFFF9800);

  /// Columns of the source grid (1° of longitude per cell).
  static const int gridColumns = 360;

  /// Rows of the source grid (1° of latitude per cell).
  static const int gridRows = 180;

  /// Center of grid cell ([col], [row]) in degrees.
  static Offset cellCenter(int col, int row) =>
      Offset(-179.5 + col, 89.5 - row);

  /// Index of the grid cell that CONTAINS ([lonDeg], [latDeg]).
  ///
  /// The cell is the one containing the point (`floor`), not the nearest one
  /// (`round`): the dataset places dots at cell CENTERS (lon = col + 0.5),
  /// and Dart's `round` rounds .5 up — `round(col+180.5)` would map every
  /// dot to its neighbor cell (see [keepDot]).
  static int cellKey(double lonDeg, double latDeg) =>
      (lonDeg + 180).floor() * gridRows + (90 - latDeg).floor();

  /// Normalized position (unit square) of ([lonDeg], [latDeg]).
  ///
  /// `Offset(0,0)` is the top-left (north-west), `Offset(1,1)` is the
  /// bottom-right (south-east).
  static Offset normalize(double lonDeg, double latDeg) =>
      Offset((lonDeg + 180) / 360, (90 - latDeg) / 180);

  /// The ocean dots: every cell center of the full grid that is NOT one of
  /// the [landGeo] dots — i.e. everything that is not a piece of land.
  ///
  /// The grid spans the whole projection (−180..180 lon, −90..90 lat), so
  /// the ocean layer completes the map: the land dots are left untouched
  /// and no cell of the grid stays unpainted.
  static List<Offset> oceanCells(List<Offset> landGeo) {
    final land = {for (final g in landGeo) cellKey(g.dx, g.dy)};
    return [
      for (var row = 0; row < gridRows; row++)
        for (var col = 0; col < gridColumns; col++)
          if (!land.contains(col * gridRows + row)) cellCenter(col, row),
    ];
  }

  /// Loads the land dots as normalized offsets in the unit square.
  static Future<List<Offset>> loadDots() =>
      loadData().then((data) => data.land);

  /// Loads the dot dataset (land + ocean layers: normalized offsets and
  /// geographic coordinates).
  static Future<WorldDotData> loadData() => _dataFuture;

  /// Whether the dot at [normalized] position (unit square) survives
  /// decimation for the given [stride].
  ///
  /// Dots are kept only when the 1°-grid cell that CONTAINS them has column
  /// and row multiples of [stride], so on-screen spacing doubles/quadruples
  /// while every kept dot stays aligned to the same invisible grid. Both
  /// layers sit on that same grid, so they decimate together and stay
  /// pixel-aligned.
  static bool keepDot(Offset normalized, int stride) {
    if (stride == 1) {
      return true;
    }
    final col = (normalized.dx * gridColumns).floor();
    final row = (normalized.dy * gridRows).floor();
    // Centred lattice (`offset = stride ~/ 2`), not anchored on cell 0:
    // anchoring on 0 left the last column 3.5° from the right border while the
    // first sat 0.5° from the left one, so the right edge read as if a column
    // of dots were missing.
    final offset = stride ~/ 2;
    return (col - offset) % stride == 0 && (row - offset) % stride == 0;
  }

  static final Future<WorldDotData> _dataFuture = _parseData();

  /// Smallest dot diameter worth drawing, in logical points.
  ///
  /// The decimation step is derived from THIS floor, not from the size of the
  /// grid cell (the previous rule: cell >= 4 px / 2 px). The old rule changed
  /// step only once the cell got small, which is exactly when the map is at its
  /// densest, so the dots had already shrunk to 2 physical pixels (1 pt on a
  /// Retina display) before anything happened — the "too small to see" state.
  static const double minDotPt = 1.5;

  /// Largest decimation step: beyond this the map loses its shape, so the dot
  /// keeps its [minDotPt] floor instead of stepping up again.
  static const int maxStride = 8;

  /// Decimation step for a map [mapWidthPt] logical points wide.
  ///
  /// The smallest power of two that leaves an on-screen spacing of at least
  /// twice [minDotPt] — with a dot at half the spacing, that guarantees the
  /// dot never falls below the floor. Measured in logical points (not physical
  /// pixels), so the promise holds on any display density: on the 360-column
  /// grid the step goes 1 → 2 → 4 → 8 at 1080 / 540 / 270 / 135 pt.
  static int strideFor(double mapWidthPt) {
    if (!(mapWidthPt > 0)) {
      // Degenerate layout (zero, negative, NaN): no room to draw — step all
      // the way up instead of spinning here.
      return maxStride;
    }
    final cellPt = mapWidthPt / gridColumns;
    var stride = 1;
    while (stride < maxStride && cellPt * stride < 2 * minDotPt) {
      stride *= 2;
    }
    return stride;
  }

  /// Diameter of every dot, in PHYSICAL pixels, for a map [mapWidthPt]
  /// logical points wide on a [dpr] display drawn with [stride].
  ///
  /// Half of the on-screen spacing — dots and gaps stay visually equal — but
  /// never below [minDotPt]. Rounded to whole physical pixels: sub-pixel
  /// circles are what made the small windows look like dust.
  static int dotDiameterPx(double mapWidthPt, double dpr, int stride) {
    final spacingPx = mapWidthPt * dpr / gridColumns * stride;
    final floorPx = (minDotPt * dpr).round();
    final dotPx = (spacingPx * 0.5).round();
    return dotPx < floorPx ? floorPx : dotPx;
  }

  static Future<WorldDotData> _parseData() async {
    final raw = await rootBundle.loadString('assets/world_dots.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    final landGeo = [
      for (final pair in decoded)
        Offset((pair[0] as num).toDouble(), (pair[1] as num).toDouble()),
    ];
    final oceanGeo = oceanCells(landGeo);
    return WorldDotData(
      land: [for (final g in landGeo) normalize(g.dx, g.dy)],
      landGeo: landGeo,
      ocean: [for (final g in oceanGeo) normalize(g.dx, g.dy)],
      oceanGeo: oceanGeo,
    );
  }

  @override
  State<WorldDotMap> createState() => _WorldDotMapState();
}

/// Dot dataset: [land]/[ocean] positions in the unit square (for layout) and
/// [landGeo]/[oceanGeo] lon/lat coordinates in degrees (for solar shading),
/// index-aligned within each layer.
class WorldDotData {
  const WorldDotData({
    required this.land,
    required this.landGeo,
    required this.ocean,
    required this.oceanGeo,
  });

  final List<Offset> land;
  final List<Offset> landGeo;
  final List<Offset> ocean;
  final List<Offset> oceanGeo;
}

class _WorldDotMapState extends State<WorldDotMap> {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: FutureBuilder<WorldDotData>(
        future: WorldDotMap.loadData(),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            // Asset still loading (or failed): keep the background only.
            return const SizedBox.expand();
          }
          return CustomPaint(
            painter: _DotPainter(
              data: data,
              dotColor: widget.dotColor,
              oceanColor: widget.oceanColor,
              backgroundColor: widget.backgroundColor,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              now: widget.now,
              includeTwilight: widget.includeTwilight,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

/// One dot layer (land or ocean): its dots, its color ramp and the caches
/// the painter needs. Both layers share the same grid, decimation and dot
/// size — only the colors differ.
class _DotLayer {
  _DotLayer({
    required this.normalized,
    required this.geo,
    required this.color,
    required this.minBrightness,
  });

  /// Dot positions in the unit square (0..1).
  final List<Offset> normalized;

  /// Lon/lat degrees per dot, index-aligned with [normalized].
  final List<Offset> geo;

  /// Daylight color of this layer.
  final Color color;

  /// Minimum brightness at night: the layer fades toward the background but
  /// never fully disappears, so the map shape stays readable.
  final double minBrightness;

  List<Offset>? _screenOffsets;
  List<int>? _keptIndices;
  Size? _cachedSize;
  int? _cachedStride;
  List<double>? _brightness;
  int? _brightnessMinute;
  bool? _brightnessTwilight;

  /// Snaps every dot center to the nearest physical pixel so dots are crisp
  /// and aligned to the invisible grid on any display; also caches which
  /// dots survive decimation for this size/stride.
  void ensureLayout(Size size, double dpr, int stride) {
    if (_screenOffsets != null &&
        _cachedSize == size &&
        _cachedStride == stride) {
      return;
    }
    final scaleX = size.width * dpr;
    final scaleY = size.height * dpr;
    _screenOffsets = [
      for (final o in normalized)
        Offset((o.dx * scaleX) / dpr, (o.dy * scaleY) / dpr),
    ];
    _keptIndices = [
      for (var i = 0; i < normalized.length; i++)
        if (WorldDotMap.keepDot(normalized[i], stride)) i,
    ];
    _cachedSize = size;
    _cachedStride = stride;
  }

  List<Offset> get screenOffsets => _screenOffsets!;

  List<int> get keptIndices => _keptIndices!;

  /// Per-dot brightness for [now], cached until the minute ticks over (the
  /// sun barely moves within a minute, and the trig loop over ~15k land +
  /// ~50k ocean dots only runs once per minute instead of once per frame).
  ///
  /// The cache key also carries [includeTwilight]: flipping the menu option
  /// must never serve the other formula's numbers for the rest of the minute.
  List<double> brightnessFor(DateTime? now, bool includeTwilight) {
    final minute = minuteKey(now);
    if (_brightness != null &&
        _brightnessMinute == minute &&
        _brightnessTwilight == includeTwilight) {
      return _brightness!;
    }
    final moment = (now ?? DateTime.now()).toUtc();
    final out = List<double>.filled(geo.length, 0);
    for (var i = 0; i < geo.length; i++) {
      out[i] = SunShading.intensity(
        geo[i].dy,
        geo[i].dx,
        moment,
        includeTwilight: includeTwilight,
      );
    }
    _brightness = out;
    _brightnessMinute = minute;
    _brightnessTwilight = includeTwilight;
    return out;
  }

  static int minuteKey(DateTime? d) =>
      (d ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 60000;
}

class _DotPainter extends CustomPainter {
  _DotPainter({
    required this.data,
    required this.dotColor,
    required this.oceanColor,
    required this.backgroundColor,
    required this.devicePixelRatio,
    this.now,
    this.includeTwilight = false,
  }) {
    _land = _DotLayer(
      normalized: data.land,
      geo: data.landGeo,
      color: dotColor,
      minBrightness: _minBrightness,
    );
    _ocean = _DotLayer(
      normalized: data.ocean,
      geo: data.oceanGeo,
      color: oceanColor,
      minBrightness: _oceanMinBrightness,
    );
  }

  /// Land + ocean dots (normalized offsets and lon/lat, index-aligned).
  final WorldDotData data;

  final Color dotColor;
  final Color oceanColor;
  final Color backgroundColor;

  /// Physical pixels per logical pixel (used to snap dots to the pixel grid).
  final double devicePixelRatio;

  final DateTime? now;

  /// Whether to shade with the twilight ramp
  /// (see [WorldDotMap.includeTwilight]).
  final bool includeTwilight;

  /// Brightness quantization: dots with similar brightness share one
  /// drawPoints call (a handful of draw ops, never one per dot).
  static const int _buckets = 32;

  /// Minimum dot brightness at night: land stays faintly visible so the
  /// map shape never fully disappears. 0.10 was too dark against the
  /// #111111 background; 0.30 keeps a clear "night" look while readable.
  static const double _minBrightness = 0.30;

  /// Ocean minimum brightness: same floor as the land (0.30) — the sea and the
  /// continents now fade to the same minimum. At 0.15 the water dots sat only
  /// ~11 levels above the background, so the polar-night rows at the top border
  /// faded out of view and the map looked cropped at the edge; the continents
  /// still stand out at night by colour, not by this floor.
  static const double _oceanMinBrightness = 0.30;

  late final _DotLayer _land;
  late final _DotLayer _ocean;

  @override
  void paint(Canvas canvas, Size size) {
    final dpr = devicePixelRatio;
    final stride = WorldDotMap.strideFor(size.width);

    // Diameter rounded to a whole physical pixel so the circles are sharp,
    // and floored at WorldDotMap.minDotPt so a cramped window degrades the
    // DENSITY (fewer dots, via the step) instead of the dot size.
    final dotPx = WorldDotMap.dotDiameterPx(size.width, dpr, stride);
    final strokeWidth = dotPx / dpr;

    _land.ensureLayout(size, dpr, stride);
    _ocean.ensureLayout(size, dpr, stride);

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    // Ocean first: land is drawn on top of the water, so the continents
    // keep exactly the look they had before the ocean layer existed.
    _paintLayer(canvas, _ocean, paint);
    _paintLayer(canvas, _land, paint);
  }

  /// Paints one layer: group its dots by brightness bucket and issue one
  /// drawPoints call per bucket.
  void _paintLayer(Canvas canvas, _DotLayer layer, Paint paint) {
    if (layer.normalized.isEmpty) {
      return;
    }
    final brightness = layer.brightnessFor(now, includeTwilight);
    final screen = layer.screenOffsets;

    final buckets = List.generate(_buckets, (_) => <Offset>[]);
    for (final i in layer.keptIndices) {
      var b = (brightness[i] * _buckets).floor();
      if (b >= _buckets) {
        b = _buckets - 1;
      }
      buckets[b].add(screen[i]);
    }

    for (var b = 0; b < _buckets; b++) {
      final points = buckets[b];
      if (points.isEmpty) {
        continue;
      }
      final t = (b + 0.5) / _buckets;
      final level = layer.minBrightness + t * (1 - layer.minBrightness);
      paint.color = Color.lerp(backgroundColor, layer.color, level)!;
      canvas.drawPoints(PointMode.points, points, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor ||
        oldDelegate.oceanColor != oceanColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.data != data ||
        oldDelegate.includeTwilight != includeTwilight ||
        _DotLayer.minuteKey(oldDelegate.now) != _DotLayer.minuteKey(now);
  }
}
