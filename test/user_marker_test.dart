import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/main.dart';
import 'package:world_clock/map_theme.dart';
import 'package:world_clock/moon_marker.dart';
import 'package:world_clock/user_location.dart';
import 'package:world_clock/user_marker.dart';
import 'package:world_clock/world_dot_map.dart';

/// O ponto do usuário no mapa: onde ele cai, o que aparece sem posição e a
/// garantia de que ele não suja a camada dos pontos.
void main() {
  const here = UserLocation.fix(
    latitude: -27.586252,
    longitude: -48.542783,
    accuracyM: 40,
    source: UserLocationSource.system,
  );
  const mapSize = Size(1200, 600);

  group('projeção', () {
    test('cai na mesma projeção do dataset do mapa', () {
      final offset = UserMarker.offsetFor(here, mapSize)!;
      final unit = WorldDotMap.normalize(here.longitude!, here.latitude!);

      expect(offset.dx, closeTo(unit.dx * mapSize.width, 1e-9));
      expect(offset.dy, closeTo(unit.dy * mapSize.height, 1e-9));
    });

    test('usa exatamente a projeção do marcador da Lua', () {
      // Mesma coordenada nos dois marcadores = mesmo ponto na tela. Se alguém
      // trocar a projeção de um lado só, este teste quebra.
      expect(
        UserMarker.offsetFor(here, mapSize),
        MoonMarker.offsetFor(here.longitude!, here.latitude!, mapSize),
      );
    });

    test('hemisférios: o canto do mundo é o canto do mapa', () {
      const northeast = UserLocation.fix(
        latitude: 89,
        longitude: 179,
        source: UserLocationSource.system,
      );
      const southwest = UserLocation.fix(
        latitude: -89,
        longitude: -179,
        source: UserLocationSource.system,
      );

      final ne = UserMarker.offsetFor(northeast, mapSize)!;
      final sw = UserMarker.offsetFor(southwest, mapSize)!;

      expect(ne.dx, greaterThan(mapSize.width * 0.99));
      expect(ne.dy, lessThan(mapSize.height * 0.01));
      expect(sw.dx, lessThan(mapSize.width * 0.01));
      expect(sw.dy, greaterThan(mapSize.height * 0.99));
    });

    test('a linha do Equador e o meridiano de Greenwich caem no centro', () {
      const zero = UserLocation.fix(
        latitude: 0,
        longitude: 0,
        source: UserLocationSource.system,
      );
      final offset = UserMarker.offsetFor(zero, mapSize)!;

      expect(offset.dx, closeTo(mapSize.width / 2, 1e-9));
      expect(offset.dy, closeTo(mapSize.height / 2, 1e-9));
    });

    test('sem posição (ou sem consulta respondida) não há ponto', () {
      expect(UserMarker.offsetFor(null, mapSize), isNull);
      expect(
        UserMarker.offsetFor(
          const UserLocation.failed(UserLocationFailure.permissionDenied),
          mapSize,
        ),
        isNull,
      );
    });
  });

  group('desenho', () {
    Finder dot() => find.descendant(
      of: find.byType(UserMarker),
      matching: find.byType(CustomPaint),
    );

    testWidgets('sem posição, nada é desenhado', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UserMarker(
            location: const UserLocation.failed(
              UserLocationFailure.permissionDenied,
            ),
            mapSize: mapSize,
            land: MapThemes.standard.land,
            background: MapThemes.standard.background,
          ),
        ),
      );

      expect(dot(), findsNothing);
    });

    testWidgets('com posição, o disco sai centrado na coordenada', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: mapSize.width,
              height: mapSize.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: UserMarker(
                      location: here,
                      mapSize: mapSize,
                      land: MapThemes.standard.land,
                      background: MapThemes.standard.background,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(dot(), findsOneWidget);
      final rect = tester.getRect(dot());
      final box = tester.getRect(find.byType(SizedBox).first);
      final expected = box.topLeft + UserMarker.offsetFor(here, mapSize)!;

      expect(rect.center.dx, closeTo(expected.dx, 0.01));
      expect(rect.center.dy, closeTo(expected.dy, 0.01));
      expect(rect.width, UserMarker.diameter);
      expect(rect.height, UserMarker.diameter);
    });
  });

  group('integração com a tela', () {
    /// A tela com a posição chegando DEPOIS do primeiro quadro — que é o que
    /// acontece de verdade: a consulta é assíncrona e o app abre sem o ponto.
    Future<void> pumpScreen(
      WidgetTester tester,
      Completer<UserLocation> completer,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: WorldMapScreen(locationLookup: () => completer.future),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });
    }

    /// Entrega a resposta da consulta e deixa o `setState` chegar ao quadro.
    /// Precisa de `runAsync` porque a consulta é assíncrona DE VERDADE (fora do
    /// relógio falso do teste); o `pump` depois desenha o resultado.
    Future<void> deliver(
      WidgetTester tester,
      Completer<UserLocation> completer,
      UserLocation location,
    ) async {
      await tester.runAsync(() async {
        completer.complete(location);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    }

    CustomPainter mapPainter(WidgetTester tester) {
      final finder = find.descendant(
        of: find.byType(WorldDotMap),
        matching: find.byType(CustomPaint),
      );
      expect(finder, findsOneWidget);
      return tester.widget<CustomPaint>(finder).painter!;
    }

    testWidgets('o ponto aparece quando a posição chega, sem repintar o mapa', (
      tester,
    ) async {
      // Mesmo contrato do hover do marcador da Lua: o que muda é o marcador,
      // não os pontos. Se um dia o ponto do usuário passar a sujar a camada do
      // mapa (por exemplo, entrando dentro do RepaintBoundary dos pontos), é
      // este teste que quebra.
      final completer = Completer<UserLocation>();
      await pumpScreen(tester, completer);

      expect(
        find.descendant(
          of: find.byType(UserMarker),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
        reason: 'sem resposta ainda, a tela não desenha ponto',
      );
      final before = mapPainter(tester);

      await deliver(tester, completer, here);

      final dotFinder = find.descendant(
        of: find.byType(UserMarker),
        matching: find.byType(CustomPaint),
      );
      expect(dotFinder, findsOneWidget);
      expect(tester.takeException(), isNull);

      final mapRect = tester.getRect(find.byType(WorldDotMap));
      final expected =
          mapRect.topLeft + UserMarker.offsetFor(here, mapRect.size)!;
      expect(tester.getRect(dotFinder).center.dx, closeTo(expected.dx, 0.5));
      expect(tester.getRect(dotFinder).center.dy, closeTo(expected.dy, 0.5));

      final after = mapPainter(tester);
      expect(
        after.shouldRepaint(before),
        isFalse,
        reason: 'a posição chegando não pode sujar os pontos do mapa',
      );

      // Desmonta para o ticker de 15 min da tela ser cancelado.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sem posição, a bandeja diz o motivo', (tester) async {
      final completer = Completer<UserLocation>();
      await pumpScreen(tester, completer);

      await deliver(
        tester,
        completer,
        const UserLocation.failed(UserLocationFailure.permissionDenied),
      );

      // A bandeja fecha até ser clicada; a linha do motivo vive no painel.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('Localização: sem permissão'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('com posição, a bandeja não fala de localização', (
      tester,
    ) async {
      final completer = Completer<UserLocation>();
      await pumpScreen(tester, completer);

      await deliver(tester, completer, here);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.textContaining('Localização'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
