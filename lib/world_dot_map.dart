import 'dart:convert';
import 'dart:ui' show Offset, PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'world_sun.dart';

/// A dot-matrix world map with real solar illumination.
///
/// Renders the landmasses of the world as a grid of dots (equirectangular
/// projection, 2:1 aspect). The dots come from [assets/world_dots.json], a
/// flat list of `[longitude, latitude]` pairs sampled from Natural Earth
/// (public domain, Antarctica excluded).
///
/// When [now] is provided, each dot is shaded by the actual sun position at
/// that instant: places in daylight are bright, places in darkness are dim
/// (with a smooth twilight transition). Pass a fresh [now] periodically
/// (e.g. once a minute) so the day/night boundary keeps moving.
///
/// The widget is self-contained: it loads and caches the asset once per app
/// run, then paints all dots in a handful of `drawPoints` calls (one per
/// brightness bucket, regardless of dot count).
class WorldDotMap extends StatefulWidget {
  const WorldDotMap({
    super.key,
    this.backgroundColor = const Color(0xFF0B1220),
    this.dotColor = const Color(0xFF7DD3FC),
    this.now,
  });

  /// Background behind the map.
  final Color backgroundColor;

  /// Color of the land dots in full daylight.
  final Color dotColor;

  /// Reference instant for the solar shading. When null, [DateTime.now] is
  /// used each time the painter repaints.
  final DateTime? now;

  /// Loads the dot dataset as normalized offsets in the unit square.
  ///
  /// `Offset(0,0)` is the top-left (north-west), `Offset(1,1)` is the
  /// bottom-right (south-east).
  static Future<List<Offset>> loadDots() =>
      loadData().then((data) => data.normalized);

  /// Loads the dot dataset (normalized offsets + geographic coordinates).
  static Future<WorldDotData> loadData() => _dataFuture;

  /// Whether the dot at [normalized] position (unit square) survives
  /// decimation for the given [stride].
  ///
  /// Dots are kept only when the 1°-grid cell that CONTAINS them has column
  /// and row multiples of [stride], so on-screen spacing doubles/quadruples
  /// while every kept dot stays aligned to the same invisible grid.
  ///
  /// The cell is the one containing the dot (`floor`), not the nearest one
  /// (`round`): the dataset places dots at cell CENTERS (lon = col + 0.5),
  /// and Dart's `round` rounds .5 up — `round(col+180.5)` would map every
  /// dot to its neighbor cell, shifting the whole kept grid one cell right
  /// and eating coastlines asymmetrically.
  static bool keepDot(Offset normalized, int stride) {
    if (stride == 1) {
      return true;
    }
    final col = (normalized.dx * 360).floor();
    final row = (normalized.dy * 180).floor();
    return col % stride == 0 && row % stride == 0;
  }

  static final Future<WorldDotData> _dataFuture = _parseData();

  static Future<WorldDotData> _parseData() async {
    final raw = await rootBundle.loadString('assets/world_dots.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    return WorldDotData(
      normalized: [
        for (final pair in decoded)
          Offset(
            ((pair[0] as num) + 180) / 360,
            (90 - (pair[1] as num)) / 180,
          ),
      ],
      geo: [
        for (final pair in decoded)
          Offset((pair[0] as num).toDouble(), (pair[1] as num).toDouble()),
      ],
    );
  }

  @override
  State<WorldDotMap> createState() => _WorldDotMapState();
}

/// Dot dataset: [normalized] positions in the unit square (for layout) and
/// [geo] lon/lat coordinates in degrees (for solar shading), index-aligned.
class WorldDotData {
  const WorldDotData({required this.normalized, required this.geo});

  final List<Offset> normalized;
  final List<Offset> geo;
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
              normalized: data.normalized,
              geo: data.geo,
              dotColor: widget.dotColor,
              backgroundColor: widget.backgroundColor,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              now: widget.now,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter({
    required this.normalized,
    required this.geo,
    required this.dotColor,
    required this.backgroundColor,
    required this.devicePixelRatio,
    this.now,
  });

  /// Dot positions in the unit square (0..1).
  final List<Offset> normalized;

  /// Lon/lat degrees per dot, index-aligned with [normalized].
  final List<Offset> geo;

  final Color dotColor;
  final Color backgroundColor;

  /// Physical pixels per logical pixel (used to snap dots to the pixel grid).
  final double devicePixelRatio;

  final DateTime? now;

  /// Brightness quantization: dots with similar brightness share one
  /// drawPoints call (a handful of draw ops, never one per dot).
  static const int _buckets = 32;

  /// Minimum dot brightness at night: land stays faintly visible so the
  /// map shape never fully disappears.
  static const double _minBrightness = 0.10;

  List<Offset>? _screenOffsets;
  List<int>? _keptIndices;
  Size? _cachedSize;
  List<double>? _brightness;
  int? _brightnessMinute;

  static int _minuteKey(DateTime? d) =>
      (d ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 60000;

  /// Snaps every dot center to the nearest physical pixel so dots are crisp
  /// and aligned to the invisible grid on any display; also caches which
  /// dots survive decimation for this size.
  void _ensureScreenOffsets(Size size) {
    if (_screenOffsets != null && _cachedSize == size) {
      return;
    }
    final dpr = devicePixelRatio;
    final scaleX = size.width * dpr;
    final scaleY = size.height * dpr;
    _screenOffsets = [
      for (final o in normalized)
        Offset((o.dx * scaleX).round() / dpr, (o.dy * scaleY).round() / dpr),
    ];

    final stride = _strideFor(size);
    _keptIndices = [
      for (var i = 0; i < normalized.length; i++)
        if (WorldDotMap.keepDot(normalized[i], stride)) i,
    ];
    _cachedSize = size;
  }

  /// Adaptive decimation: when the window gets small the grid cells shrink
  /// and dots would nearly touch. Keep the density comfortable by drawing
  /// every 2nd (or 4th) dot in each direction, which doubles/quadruples the
  /// on-screen spacing while staying perfectly aligned to the same grid.
  int _strideFor(Size size) {
    final cellPx = size.width * devicePixelRatio / 360;
    return cellPx >= 4 ? 1 : (cellPx >= 2 ? 2 : 4);
  }

  /// Per-dot brightness for the current [now], cached until the minute ticks
  /// over (the sun barely moves within a minute, and the trig loop over
  /// ~15k dots only runs once per minute instead of once per frame).
  List<double> _brightnessFor() {
    final minute = _minuteKey(now);
    if (_brightness != null && _brightnessMinute == minute) {
      return _brightness!;
    }
    final moment = (now ?? DateTime.now()).toUtc();
    final out = List<double>.filled(normalized.length, 0);
    for (var i = 0; i < normalized.length; i++) {
      out[i] = SunShading.intensity(geo[i].dy, geo[i].dx, moment);
    }
    _brightness = out;
    _brightnessMinute = minute;
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureScreenOffsets(size);

    final dpr = devicePixelRatio;
    final stride = _strideFor(size);
    final cellPx = size.width * dpr / 360;

    // Diameter rounded to a whole physical pixel so the circles are sharp;
    // ~0.5 of the effective cell leaves a visible gap (≈ dot size) between
    // neighbors at every stride — 0.7 made dots nearly touch, reading as
    // a clustered blob on small windows.
    var dotPx = (cellPx * stride * 0.5).round();
    if (dotPx < 1) {
      dotPx = 1;
    }
    final strokeWidth = dotPx / dpr;

    final brightness = _brightnessFor();
    final kept = _keptIndices!;
    final screen = _screenOffsets!;

    // Group dots by brightness bucket, one drawPoints call per bucket.
    final buckets = List.generate(_buckets, (_) => <Offset>[]);
    for (final i in kept) {
      var b = (brightness[i] * _buckets).floor();
      if (b >= _buckets) {
        b = _buckets - 1;
      }
      buckets[b].add(screen[i]);
    }

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    for (var b = 0; b < _buckets; b++) {
      final points = buckets[b];
      if (points.isEmpty) {
        continue;
      }
      final t = (b + 0.5) / _buckets;
      final level = _minBrightness + t * (1 - _minBrightness);
      paint.color = Color.lerp(backgroundColor, dotColor, level)!;
      canvas.drawPoints(PointMode.points, points, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.normalized != normalized ||
        oldDelegate.geo != geo ||
        _minuteKey(oldDelegate.now) != _minuteKey(now);
  }
}
