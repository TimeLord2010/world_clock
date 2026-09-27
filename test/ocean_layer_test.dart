import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/world_dot_map.dart';

void main() {
  // The plain tests below load the asset through `rootBundle`.
  TestWidgetsFlutterBinding.ensureInitialized();

  const gridCells = WorldDotMap.gridColumns * WorldDotMap.gridRows;

  group('ocean layer', () {
    test('the ocean completes the grid: land + ocean == every 1° cell', () async {
      final data = await WorldDotMap.loadData();

      expect(data.land.length, greaterThan(10000));
      expect(data.land.length + data.ocean.length, gridCells);
      expect(data.ocean.length, gridCells - data.land.length);
      expect(data.ocean.length, greaterThan(data.land.length));
    });

    test('land and ocean never share a grid cell', () async {
      final data = await WorldDotMap.loadData();

      final landKeys = {
        for (final g in data.landGeo) WorldDotMap.cellKey(g.dx, g.dy),
      };
      for (final g in data.oceanGeo) {
        expect(
          landKeys.contains(WorldDotMap.cellKey(g.dx, g.dy)),
          isFalse,
          reason: 'ocean cell (${g.dx}, ${g.dy}) duplicates a land cell',
        );
      }
      expect(data.oceanGeo.length, gridCells - landKeys.length);
    });

    test('every ocean dot is unique and sits on a 1° cell center', () async {
      final data = await WorldDotMap.loadData();

      final seen = <int>{};
      for (var i = 0; i < data.ocean.length; i++) {
        final o = data.ocean[i];
        expect(o.dx, inInclusiveRange(0, 1));
        expect(o.dy, inInclusiveRange(0, 1));

        // Cell centers: lon = col + 0.5 → dx*360 - 0.5 is a whole column.
        expect(o.dx * 360 - 0.5, closeTo((o.dx * 360 - 0.5).roundToDouble(), 1e-9));
        expect(o.dy * 180 - 0.5, closeTo((o.dy * 180 - 0.5).roundToDouble(), 1e-9));

        expect(seen.add(WorldDotMap.cellKey(data.oceanGeo[i].dx, data.oceanGeo[i].dy)),
            isTrue);
      }
      expect(seen.length, data.ocean.length);
    });

    test('open ocean is ocean, a dataset dot is not', () async {
      final data = await WorldDotMap.loadData();
      final oceanKeys = {
        for (final g in data.oceanGeo) WorldDotMap.cellKey(g.dx, g.dy),
      };

      // 0.5°N 140.5°W — mid Pacific.
      expect(oceanKeys.contains(WorldDotMap.cellKey(-140.5, 0.5)), isTrue);
      // The very first dataset dot (83.5°N 38.5°W, Greenland) stays land.
      final first = data.landGeo.first;
      expect(oceanKeys.contains(WorldDotMap.cellKey(first.dx, first.dy)), isFalse);
    });

    test('the ocean decimates on the same stride-aligned grid as the land',
        () async {
      final data = await WorldDotMap.loadData();

      expect(
        data.ocean.where((o) => WorldDotMap.keepDot(o, 1)).length,
        data.ocean.length,
      );
      final kept4 = data.ocean.where((o) => WorldDotMap.keepDot(o, 4)).length;
      expect(kept4, closeTo(data.ocean.length / 16, data.ocean.length / 16 * 0.2));
    });

    test('normalize() and cellCenter() agree with cellKey()', () {
      // Round trip over every cell of the grid: center → normalized → key.
      for (var row = 0; row < WorldDotMap.gridRows; row++) {
        for (var col = 0; col < WorldDotMap.gridColumns; col++) {
          final center = WorldDotMap.cellCenter(col, row);
          expect(WorldDotMap.cellKey(center.dx, center.dy),
              col * WorldDotMap.gridRows + row);
          final n = WorldDotMap.normalize(center.dx, center.dy);
          expect(WorldDotMap.keepDot(n, 1), isTrue);
        }
      }
    });
  });
}
