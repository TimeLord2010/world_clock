import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:world_clock/city.dart';
import 'package:world_clock/city_catalog.dart';
import 'package:world_clock/city_markers.dart';
import 'package:world_clock/city_store.dart';
import 'package:world_clock/main.dart';
import 'package:world_clock/map_geometry.dart';
import 'package:world_clock/panel_card.dart';
import 'package:world_clock/place_lookup.dart';
import 'package:world_clock/user_location.dart';
import 'package:world_clock/world_dot_map.dart';

/// Clicar em qualquer ponto do mapa: o alvo aparece, a HORA sai offline na hora
/// e o nome exato entra depois, se entrar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<UserLocation> noLocation() async =>
      const UserLocation.failed(UserLocationFailure.unavailable);

  late List<City> catalog;
  late City fortaleza;

  setUpAll(() async {
    tzdata.initializeTimeZones();
    catalog = await CityCatalog.load();
    fortaleza = catalog.firstWhere(
      (city) => city.name == 'Fortaleza' && city.region == 'Ceará',
    );
  });

  /// Fortaleza: fuso do polígono, cidade do catálogo em cima.
  const atFortaleza = MapPoint(latitude: -3.748, longitude: -38.582);

  /// Mar aberto no Atlântico: fuso náutico, sem nome nenhum.
  const atSea = MapPoint(latitude: 0, longitude: -30);

  /// Interior da Austrália: sem cidade por perto, e o nome mais próximo
  /// (Kaltukatjara) está a 411 km — fora do raio, então sem nome.
  const atOutback = MapPoint(latitude: -25, longitude: 125);

  Finder targets() => find.descendant(
    of: find.byType(CityMarkers),
    matching: find.byType(CustomPaint),
  );

  /// Monta a tela de verdade e devolve um clique em [point].
  Future<void> pumpScreen(
    WidgetTester tester, {
    PlaceNameLookup? nameLookup,
    Set<String> savedCities = const <String>{},
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorldMapScreen(
            locationLookup: noLocation,
            cityStore: MemoryCityStore(SavedCities(selected: savedCities)),
            nameLookup: nameLookup,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    await tester.pump();
  }

  Future<void> tearDownScreen(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  /// Clica no ponto [point] do mapa.
  Future<void> clickAt(WidgetTester tester, MapPoint point) async {
    final mapRect = tester.getRect(find.byType(WorldDotMap));
    await tester.tapAt(mapRect.topLeft + point.offsetIn(mapRect.size));
    // Um quadro para o alvo e a resposta offline; a lista de microtasks da
    // consulta escoa no mesmo pump.
    await tester.pump();
    await tester.pump();
  }

  group('clique no mapa', () {
    testWidgets('marca o ponto e mostra a hora, sem esperar por nome', (
      tester,
    ) async {
      final names = _ControlledNames();
      await pumpScreen(tester, nameLookup: names);

      // Num ponto sem cidade por perto, a fase 2 É consultada — e fica pendurada
      // até o teste mandar responder.
      await clickAt(tester, atOutback);

      // O ALVO aparece no ponto exato.
      final mapRect = tester.getRect(find.byType(WorldDotMap));
      final expected = mapRect.topLeft + atOutback.offsetIn(mapRect.size);
      final target = tester.getRect(targets());
      expect(target.center.dx, closeTo(expected.dx, 0.01));
      expect(target.center.dy, closeTo(expected.dy, 0.01));

      // A HORA já está no cartão, com a fonte de nomes ainda PENDURADA — é o
      // ponto do desenho em duas fases: um relógio não pode esperar rede.
      expect(find.byType(PanelCard), findsOneWidget);
      expect(find.text('UTC+08'), findsOneWidget);
      expect(find.text('Sem cidade por perto'), findsOneWidget);
      expect(names.calls, 1, reason: 'a fase 2 foi disparada');

      await tearDownScreen(tester);
    });

    testWidgets('o nome exato substitui o aproximado quando chega', (
      tester,
    ) async {
      final names = _ControlledNames();
      await pumpScreen(tester, nameLookup: names);

      await clickAt(tester, atOutback);
      // Sem cidade por perto: sem nome, e o cartão diz por quê de forma honesta.
      expect(find.text('Sem cidade por perto'), findsOneWidget);
      expect(find.text('UTC+08'), findsOneWidget);

      // A fonte responde: o nome entra por cima, sem tocar no fuso.
      names.answer(
        const PlaceName(
          locality: 'Kaltukatjara',
          region: 'Northern Territory',
          country: 'Austrália',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Kaltukatjara'), findsOneWidget);
      expect(find.text('Austrália'), findsOneWidget);
      expect(find.text('Sem cidade por perto'), findsNothing);
      expect(find.text('UTC+08'), findsOneWidget);

      await tearDownScreen(tester);
    });

    testWidgets('resposta atrasada NÃO sobrescreve o clique seguinte', (
      tester,
    ) async {
      final names = _ControlledNames();
      await pumpScreen(tester, nameLookup: names);

      await clickAt(tester, atOutback);
      await clickAt(tester, atSea);
      expect(find.text('Mar aberto'), findsOneWidget);
      expect(names.calls, 2);

      // A resposta do PRIMEIRO ponto chega agora, depois de o usuário já ter
      // clicado noutro lugar. Ela não pode pintar o cartão do ponto novo com o
      // nome do antigo.
      names.answerAt(
        0,
        const PlaceName(locality: 'Lugar antigo', country: 'Austrália'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Lugar antigo'), findsNothing);
      expect(find.text('Mar aberto'), findsOneWidget);

      // E a do ponto atual continua valendo.
      names.answerAt(
        1,
        const PlaceName(locality: 'Meio do Atlântico', country: 'Brasil'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Meio do Atlântico'), findsOneWidget);

      await tearDownScreen(tester);
    });

    testWidgets('fonte de nomes que falha não derruba a hora', (tester) async {
      await pumpScreen(tester, nameLookup: _FailingNames());

      await clickAt(tester, atOutback);

      expect(find.text('Sem cidade por perto'), findsOneWidget);
      expect(find.text('UTC+08'), findsOneWidget);
      expect(find.text('nome exato indisponível'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tearDownScreen(tester);
    });

    testWidgets('em terra firme com cidade perto, mostra cidade e país', (
      tester,
    ) async {
      // Sem fonte de nomes: o catálogo já resolve, e a fonte nem é consultada.
      await pumpScreen(tester);

      await clickAt(tester, atFortaleza);

      expect(find.text('Fortaleza'), findsOneWidget);
      expect(find.text('Brasil'), findsOneWidget);
      expect(find.text('UTC-03'), findsOneWidget);

      await tearDownScreen(tester);
    });

    testWidgets('nome aproximado sai com "≈" e com a distância', (
      tester,
    ) async {
      await pumpScreen(tester);

      // 180,6 km de Djanet: dentro do raio de nome, longe demais para passar
      // por "o lugar do clique".
      await clickAt(tester, const MapPoint(latitude: 23, longitude: 10));

      expect(find.text('≈ Djanet'), findsOneWidget);
      expect(find.textContaining('a 18'), findsOneWidget);
      expect(find.textContaining('Argélia'), findsOneWidget);

      await tearDownScreen(tester);
    });

    testWidgets('em oceano aberto diz "Mar aberto" e mostra o fuso náutico', (
      tester,
    ) async {
      await pumpScreen(tester);

      await clickAt(tester, atSea);

      expect(find.text('Mar aberto'), findsOneWidget);
      expect(find.text('UTC-02'), findsOneWidget);

      await tearDownScreen(tester);
    });

    testWidgets('o cartão do ponto clicado não cobre o alvo', (tester) async {
      await pumpScreen(tester);

      await clickAt(tester, atFortaleza);

      final mapRect = tester.getRect(find.byType(WorldDotMap));
      final center = mapRect.topLeft + atFortaleza.offsetIn(mapRect.size);
      final disc = Rect.fromCenter(
        center: center,
        width: CityMarkers.diameter,
        height: CityMarkers.diameter,
      );

      expect(tester.getRect(find.byType(PanelCard)).overlaps(disc), isFalse);

      await tearDownScreen(tester);
    });

    testWidgets('clicar no mapa não repinta os pontos do mapa', (tester) async {
      await pumpScreen(tester);

      CustomPainter mapPainter() {
        final finder = find.descendant(
          of: find.byType(WorldDotMap),
          matching: find.byType(CustomPaint),
        );
        return tester.widget<CustomPaint>(finder).painter!;
      }

      final before = mapPainter();
      await clickAt(tester, atFortaleza);

      expect(
        mapPainter().shouldRepaint(before),
        isFalse,
        reason: 'um clique não pode sujar os pontos do mapa',
      );

      await tearDownScreen(tester);
    });
  });

  group('clique convive com as cidades salvas', () {
    testWidgets('clicar no disco da cidade seleciona, e não marca o ponto', (
      tester,
    ) async {
      // A arena de gestos resolve pelo reconhecedor mais INTERNO: o disco da
      // cidade vence o detector do mapa. Sem isso, clicar numa cidade salva
      // abriria dois cartões ao mesmo tempo.
      await pumpScreen(tester, savedCities: {fortaleza.id});

      final mapRect = tester.getRect(find.byType(WorldDotMap));
      final discCenter = mapRect.topLeft + atFortaleza.offsetIn(mapRect.size);
      await tester.tapAt(discCenter);
      await tester.pump();

      expect(find.text('Fortaleza'), findsWidgets);
      expect(
        find.byType(PanelCard),
        findsOneWidget,
        reason: 'só o cartão da cidade — o ponto clicado não foi marcado',
      );
      expect(
        targets(),
        findsOneWidget,
        reason: 'só o anel da cidade, nenhum alvo',
      );

      await tearDownScreen(tester);
    });

    testWidgets('clicar no mapa fecha o cartão da cidade aberto', (
      tester,
    ) async {
      await pumpScreen(tester, savedCities: {fortaleza.id});

      final mapRect = tester.getRect(find.byType(WorldDotMap));
      await tester.tapAt(mapRect.topLeft + atFortaleza.offsetIn(mapRect.size));
      await tester.pump();
      expect(find.byType(PanelCard), findsOneWidget);

      // Um clique longe: a atenção vai para onde o usuário clicou.
      await tester.tapAt(mapRect.topLeft + atSea.offsetIn(mapRect.size));
      await tester.pump();
      await tester.pump();

      expect(find.byType(PanelCard), findsOneWidget);
      expect(find.text('Mar aberto'), findsOneWidget);

      await tearDownScreen(tester);
    });
  });
}

/// Uma fonte de nomes que fica PENDURADA até o teste mandar responder.
///
/// É o que permite provar o essencial: a hora aparece com a consulta ainda em
/// curso.
class _ControlledNames implements PlaceNameLookup {
  final List<Completer<PlaceName?>> _pending = <Completer<PlaceName?>>[];

  int get calls => _pending.length;

  @override
  Future<PlaceName?> lookup(MapPoint point) {
    final completer = Completer<PlaceName?>();
    _pending.add(completer);
    return completer.future;
  }

  /// Responde a consulta mais recente, se houver uma pendente.
  void answer(PlaceName? name) => answerAt(_pending.length - 1, name);

  void answerAt(int index, PlaceName? name) {
    final completer = _pending[index];
    if (!completer.isCompleted) {
      completer.complete(name);
    }
  }
}

/// Uma fonte de nomes que sempre falha.
class _FailingNames implements PlaceNameLookup {
  @override
  Future<PlaceName?> lookup(MapPoint point) async =>
      throw const SocketException('sem rede');
}
