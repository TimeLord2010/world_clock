import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/main.dart';
import 'package:world_clock/world_dot_map.dart';

void main() {
  test('dot dataset loads with valid normalized coordinates', () async {
    final dots = await WorldDotMap.loadDots();

    expect(dots.length, greaterThan(10000),
        reason: 'dataset should contain a full-world dot grid');
    for (final o in dots) {
      expect(o.dx, inInclusiveRange(0, 1));
      expect(o.dy, inInclusiveRange(0, 1));
    }
  });

  testWidgets('app renders the dot map without errors', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const WorldClockApp());
      // Give the async asset load time to complete, then rebuild.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.byType(WorldDotMap), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tear down so the screen's 1-minute timer is disposed.
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('dot map renders solar shading without errors', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: WorldDotMap(now: DateTime.utc(2026, 3, 20, 12)),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(find.byType(WorldDotMap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
