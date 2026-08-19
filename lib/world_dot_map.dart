import 'dart:convert';
import 'dart:ui' show Offset, PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A dot-matrix world map.
///
/// Renders the landmasses of the world as a grid of dots (equirectangular
/// projection, 2:1 aspect). The dots come from [assets/world_dots.json], a
/// flat list of `[longitude, latitude]` pairs sampled from Natural Earth
/// (public domain, Antarctica excluded).
///
/// The widget is self-contained: it loads and caches the asset once per app
/// run, then paints all dots in a single `drawPoints` call (one draw
/// operation regardless of dot count).
class WorldDotMap extends StatefulWidget {
  const WorldDotMap({
    super.key,
    this.backgroundColor = const Color(0xFF0B1220),
    this.dotColor = const Color(0xFF7DD3FC),
  });

  /// Background behind the map.
  final Color backgroundColor;

  /// Color of the land dots.
  final Color dotColor;

  /// Loads the dot dataset from the asset bundle.
  ///
  /// Returns normalized offsets in the unit square: `Offset(0,0)` is the
  /// top-left (north-west), `Offset(1,1)` is bottom-right (south-east).
  static Future<List<Offset>> loadDots() {
    return _dotsFuture;
  }

  static final Future<List<Offset>> _dotsFuture = _parseDots();

  static Future<List<Offset>> _parseDots() async {
    final raw = await rootBundle.loadString('assets/world_dots.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    return [
      for (final pair in decoded)
        Offset(
          ((pair[0] as num) + 180) / 360,
          (90 - (pair[1] as num)) / 180,
        ),
    ];
  }

  @override
  State<WorldDotMap> createState() => _WorldDotMapState();
}

class _WorldDotMapState extends State<WorldDotMap> {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: FutureBuilder<List<Offset>>(
        future: WorldDotMap.loadDots(),
        builder: (context, snapshot) {
          final dots = snapshot.data;
          if (dots == null) {
            // Asset still loading (or failed): keep the background only.
            return const SizedBox.expand();
          }
          return CustomPaint(
            painter: _DotPainter(
              dots,
              widget.dotColor,
              MediaQuery.devicePixelRatioOf(context),
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.normalized, this.dotColor, this.devicePixelRatio);

  /// Dot positions in the unit square (0..1).
  final List<Offset> normalized;

  final Color dotColor;

  /// Physical pixels per logical pixel (used to snap dots to the pixel grid).
  final double devicePixelRatio;

  List<Offset>? _screenOffsets;
  Size? _cachedSize;

  void _ensureScreenOffsets(Size size) {
    if (_screenOffsets != null && _cachedSize == size) {
      return;
    }
    // The dataset sits on a regular grid (1 dot per 1-degree cell). Snap each
    // dot center to the nearest physical pixel so every dot is crisp and
    // aligned to the invisible grid on any display.
    final dpr = devicePixelRatio;
    final scaleX = size.width * dpr;
    final scaleY = size.height * dpr;
    _screenOffsets = [
      for (final o in normalized)
        Offset((o.dx * scaleX).round() / dpr, (o.dy * scaleY).round() / dpr),
    ];
    _cachedSize = size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureScreenOffsets(size);

    final dpr = devicePixelRatio;
    final cellPx = size.width * dpr / 360;

    // Adaptive decimation: when the window gets small the grid cells shrink
    // and dots would nearly touch. Keep the density comfortable by drawing
    // every 2nd (or 4th) dot in each direction, which doubles/quadruples the
    // on-screen spacing while staying perfectly aligned to the same grid.
    final stride = cellPx >= 4 ? 1 : (cellPx >= 2 ? 2 : 4);
    final effCellPx = cellPx * stride;

    // Diameter rounded to a whole physical pixel so the circles are sharp;
    // ~0.7 of the effective cell keeps visible gaps between neighbors.
    var dotPx = (effCellPx * 0.7).round();
    if (dotPx < 1) {
      dotPx = 1;
    }
    final paint = Paint()
      ..color = dotColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = dotPx / dpr;

    if (stride == 1) {
      canvas.drawPoints(PointMode.points, _screenOffsets!, paint);
      return;
    }

    final kept = <Offset>[
      for (final o in _screenOffsets!)
        if ((o.dx * 360 / size.width).round() % stride == 0 &&
            (o.dy * 180 / size.height).round() % stride == 0)
          o,
    ];
    canvas.drawPoints(PointMode.points, kept, paint);
  }

  @override
  bool shouldRepaint(covariant _DotPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.normalized != normalized;
  }
}
