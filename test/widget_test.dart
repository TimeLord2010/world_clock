import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/main.dart';
import 'package:world_clock/user_location.dart';
import 'package:world_clock/world_dot_map.dart';

/// Nos testes a posição do usuário é fixa: sem rede, sem permissão e sem
/// espera — a tela é montada com uma resposta pronta.
Future<UserLocation> noLocation() async =>
    const UserLocation.failed(UserLocationFailure.unavailable);

void main() {
  test('dot dataset loads with valid normalized coordinates', () async {
    final dots = await WorldDotMap.loadDots();

    expect(
      dots.length,
      greaterThan(10000),
      reason: 'dataset should contain a full-world dot grid',
    );
    for (final o in dots) {
      expect(o.dx, inInclusiveRange(0, 1));
      expect(o.dy, inInclusiveRange(0, 1));
    }
  });

  test('decimation keeps only dots on stride-aligned grid cells', () async {
    final dots = await WorldDotMap.loadDots();

    // Stride 1 keeps everything.
    expect(dots.where((o) => WorldDotMap.keepDot(o, 1)).length, dots.length);

    // Stride 4 keeps only ~1/16 of the 1°-grid cells (col % 4 == 0 &&
    // row % 4 == 0). Anything near 100% would mean the filter is broken
    // (the regression that clustered every dot on small windows).
    final kept4 = dots.where((o) => WorldDotMap.keepDot(o, 4)).length;
    expect(kept4, lessThan(dots.length ~/ 4));
    expect(kept4, greaterThan(dots.length ~/ 64));
    expect(kept4, closeTo(dots.length / 16, dots.length / 16 * 0.2));
  });

  testWidgets('app renders the dot map without errors', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(WorldClockApp(locationLookup: noLocation));
      // Give the async asset load time to complete, then rebuild.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.byType(WorldDotMap), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tear down so the screen's 1-minute timer is disposed.
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a tela re-renderiza o mapa a cada 5 minutos', (tester) async {
    WorldDotMap map() =>
        tester.widget<WorldDotMap>(find.byType(WorldDotMap).first);

    await tester.pumpWidget(WorldClockApp(locationLookup: noLocation));
    await tester.pump();

    // O tique é um `setState` que reconstrói a tela com `_now` novo, então
    // uma instância NOVA de `WorldDotMap` É o tique. `hasScheduledFrame` não
    // serve (o `pump` consome o frame que o próprio tique agendou) e comparar
    // `_now` também não (o relógio falso do teste não move `DateTime.now()`).
    var previous = map();

    Future<void> advance(int minutes, {required bool tick}) async {
      await tester.pump(Duration(minutes: minutes));
      final current = map();
      expect(
        identical(previous, current),
        !tick,
        reason: tick
            ? 'faltou o tique depois de $minutes min'
            : 'tique indesejado antes dos 5 min',
      );
      previous = current;
    }

    // Dois ciclos: um único tique também apareceria com um intervalo errado.
    await advance(4, tick: false);
    await advance(1, tick: true);
    await advance(4, tick: false);
    await advance(1, tick: true);

    // Desmonta para o ticker da tela ser cancelado.
    await tester.pumpWidget(const SizedBox());
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

  testWidgets('o crepúsculo muda os PIXELS no fim da tarde (e o mapa repinta '
      'na hora da virada)', (tester) async {
    // 18:30 local em 27/09/2026: fim da tarde, com um lado do mundo na virada.
    // O MESMO `now` nos dois lados — quem muda é a opção; se o pintor esquecer
    // de comparar a opção no `shouldRepaint`, os dois renders saem iguais e é
    // aqui que quebra.
    await tester.runAsync(() async {
      final now = DateTime.utc(2026, 9, 27, 21, 30);

      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const key = ValueKey('mapa');
      Widget harness({required bool includeTwilight}) => MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 720,
              height: 360,
              child: WorldDotMap(now: now, includeTwilight: includeTwilight),
            ),
          ),
        ),
      );

      /// Maior vermelho numa janela 5×5 em volta do ponto (lon, lat). Janela e
      /// não média: o ponto tem 2 px num fundo quase preto, e a média dilui a
      /// diferença; o miolo do ponto é o pixel mais claro da janela.
      Future<int> brightestRed(String label, double lon, double lat) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        expect(boundary.size, const Size(720, 360), reason: label);
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final p = WorldDotMap.normalize(lon, lat);
        final cx = (p.dx * image.width).round();
        final cy = (p.dy * image.height).round();
        var best = 0;
        for (var y = cy - 2; y <= cy + 2; y++) {
          for (var x = cx - 2; x <= cx + 2; x++) {
            final red = bytes.getUint8((y * image.width + x) * 4);
            if (red > best) {
              best = red;
            }
          }
        }
        return best;
      }

      await tester.pumpWidget(harness(includeTwilight: false));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      final duskSem = await brightestRed('sem crepúsculo', -50.5, -9.5);

      await tester.pumpWidget(harness(includeTwilight: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      final duskCom = await brightestRed('com crepúsculo', -50.5, -9.5);

      // Célula de TERRA na faixa do fim da tarde (interior do Pará; o ponto
      // sobre Florianópolis cai no mar na grade de 1°, e o oceano tem metade
      // do contraste do laranja). Medido neste render: canal R 72 → 104.
      expect(
        duskCom,
        greaterThan(duskSem + 12),
        reason:
            'o ponto de terra no fim da tarde tem de estar visivelmente '
            'mais claro com o crepúsculo ligado',
      );

      // O contraste entre as duas versões some onde o sol está a pino: a
      // mudança é só na virada, não no mapa inteiro.
      final solSem = await brightestRed(
        'sem crepúsculo no subsolar',
        -142.5,
        -3.5,
      );
      final solCom = await brightestRed(
        'com crepúsculo no subsolar',
        -142.5,
        -3.5,
      );
      expect((solCom - solSem).abs(), lessThanOrEqualTo(2));

      await tester.pumpWidget(const SizedBox());
    });
  });
}
