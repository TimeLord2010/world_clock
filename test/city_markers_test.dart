import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:world_clock/city.dart';
import 'package:world_clock/city_catalog.dart';
import 'package:world_clock/city_clock.dart';
import 'package:world_clock/city_markers.dart';
import 'package:world_clock/map_theme.dart';
import 'package:world_clock/moon_marker.dart';
import 'package:world_clock/panel_card.dart';
import 'package:world_clock/user_location.dart';
import 'package:world_clock/user_marker.dart';
import 'package:world_clock/world_dot_map.dart';

/// Os pontos das cidades salvas: onde caem, como abrem o overlay e — o contrato
/// que mais importa — a garantia de que nada disso repinta os pontos do mapa.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mapSize = Size(1200, 600);

  /// 03/10/2026 12:00 UTC — 09:00 em Fortaleza, 21:00 em Tóquio, mesmo dia nos
  /// dois. Para o caso de dias diferentes, ver o teste do "+1 dia".
  final now = DateTime.utc(2026, 10, 3, 12);
  final here = DateTime(2026, 10, 3, 9);

  /// As duas cidades dos testes, carregadas do CATÁLOGO de verdade.
  ///
  /// O carregamento acontece no `setUpAll`, e não dentro dos testes: ler o
  /// asset é I/O de verdade, e dentro de um `testWidgets` o relógio falso do
  /// flutter_test nunca completa esse `Future` — o teste fica pendurado para
  /// sempre. `setUpAll` roda no relógio real.
  late List<CityClock> clocks;
  late City fortaleza;

  setUpAll(() async {
    tzdata.initializeTimeZones();
    final catalog = await CityCatalog.load();
    fortaleza = catalog.firstWhere(
      (city) => city.name == 'Fortaleza' && city.region == 'Ceará',
    );
    final tokyo = catalog.firstWhere((city) => city.name == 'Tóquio');
    clocks = [CityClock(fortaleza), CityClock(tokyo)];
  });

  /// Projeta uma coordenada crua com a projeção do mapa, para comparar com o
  /// ponto de uma cidade sem passar por `City`.
  Offset project(double lon, double lat) {
    final unit = WorldDotMap.normalize(lon, lat);
    return Offset(unit.dx * mapSize.width, unit.dy * mapSize.height);
  }

  group('projeção', () {
    test('cai na mesma projeção do dataset e dos outros marcadores', () {
      final offset = CityMarkers.offsetFor(fortaleza, mapSize);
      final unit = WorldDotMap.normalize(
        fortaleza.longitude,
        fortaleza.latitude,
      );

      expect(offset.dx, closeTo(unit.dx * mapSize.width, 1e-9));
      expect(offset.dy, closeTo(unit.dy * mapSize.height, 1e-9));
      expect(
        offset,
        UserMarker.offsetFor(
          UserLocation.fix(
            latitude: fortaleza.latitude,
            longitude: fortaleza.longitude,
            source: UserLocationSource.system,
          ),
          mapSize,
        ),
      );
      expect(
        offset,
        MoonMarker.offsetFor(
          fortaleza.longitude,
          fortaleza.latitude,
          mapSize,
        ),
      );
    });

    test('fica na coordenada, não no centro da célula de 1° da grade', () {
      // Fortaleza cai numa célula de OCEANO do dataset (o mar na grade de 1°,
      // coluna 141, linha 93) — e ainda assim o ponto tem de ficar na
      // coordenada dela, não no centro do quadrado: a cidade não é um dot de
      // terra, e casar o marcador com o dot mais próximo erraria o lugar em até
      // meio grau.
      final exact = CityMarkers.offsetFor(fortaleza, mapSize);
      final cell = WorldDotMap.cellCenter(141, 93);
      final snapped = project(cell.dx, cell.dy);

      expect(exact, project(-38.582, -3.748));
      expect((exact.dx - snapped.dx).abs(), greaterThan(0.2));
      expect((exact.dy - snapped.dy).abs(), greaterThan(0.2));
    });
  });

  group('desenho', () {
    Finder discFinder() => find.descendant(
      of: find.byType(CityMarkers),
      matching: find.byType(CustomPaint),
    );

    Future<void> pumpMarkers(
      WidgetTester tester, {
      required List<CityClock> cities,
      String? selectedId,
      Set<String> pinnedIds = const <String>{},
      ValueChanged<String>? onSelect,
      DateTime? at,
      DateTime? from,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: mapSize.width,
              height: mapSize.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CityMarkers(
                      cities: cities,
                      mapSize: mapSize,
                      now: at ?? now,
                      here: from ?? here,
                      land: MapThemes.standard.land,
                      background: MapThemes.standard.background,
                      selectedId: selectedId,
                      pinnedIds: pinnedIds,
                      onSelect: onSelect,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('sem cidades, nada é desenhado', (tester) async {
      await pumpMarkers(tester, cities: const []);

      expect(discFinder(), findsNothing);
    });

    testWidgets('um disco por cidade, centrado na coordenada', (tester) async {
      for (final clock in clocks) {
        await pumpMarkers(tester, cities: [clock]);

        expect(discFinder(), findsOneWidget);
        final rect = tester.getRect(discFinder());
        final mapRect = tester.getRect(find.byType(CityMarkers));
        final expected =
            mapRect.topLeft + CityMarkers.offsetFor(clock.city, mapRect.size);

        expect(rect.center.dx, closeTo(expected.dx, 0.01));
        expect(rect.center.dy, closeTo(expected.dy, 0.01));
        expect(rect.width, CityMarkers.diameter);
        expect(rect.height, CityMarkers.diameter);
      }
    });

    testWidgets('sem clique nem fixação, nenhum overlay aparece', (
      tester,
    ) async {
      await pumpMarkers(tester, cities: clocks);

      expect(find.byType(PanelCard), findsNothing);
    });

    testWidgets('a cidade clicada abre o overlay com nome, país e horário', (
      tester,
    ) async {
      await pumpMarkers(
        tester,
        cities: clocks,
        selectedId: clocks.first.city.id,
      );

      expect(find.byType(PanelCard), findsOneWidget);
      expect(find.text('Fortaleza'), findsOneWidget);
      expect(find.text('Brasil'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('UTC-03'), findsOneWidget);
      // Tóquio não foi clicada nem presa: sem cartão.
      expect(find.text('Tóquio'), findsNothing);
    });

    testWidgets('a cidade presa mantém o overlay, sem clique nenhum', (
      tester,
    ) async {
      final tokyo = clocks[1];
      await pumpMarkers(
        tester,
        cities: [tokyo],
        pinnedIds: {tokyo.city.id},
      );

      expect(find.text('Tóquio'), findsOneWidget);
      expect(find.text('Japão'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
      expect(find.text('UTC+09'), findsOneWidget);
    });

    testWidgets('o "+1 dia" aparece e some quando o dia de quem olha vira', (
      tester,
    ) async {
      final tokyo = clocks[1];
      Future<void> pumpAt(DateTime utc, DateTime viewer) => pumpMarkers(
        tester,
        cities: [tokyo],
        pinnedIds: {tokyo.city.id},
        at: utc,
        from: viewer,
      );

      // 01:00 UTC: 22:00 do dia 2 em São Paulo, 10:00 do dia 3 em Tóquio.
      await pumpAt(DateTime.utc(2026, 10, 3, 1), DateTime(2026, 10, 2, 22));
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('+1 dia'), findsOneWidget);

      // 02:00 UTC: o dia de quem olha AINDA é o 2, então o "+1 dia" fica.
      await pumpAt(DateTime.utc(2026, 10, 3, 2), DateTime(2026, 10, 2, 23));
      expect(find.text('11:00'), findsOneWidget);
      expect(find.text('+1 dia'), findsOneWidget);

      // 03:00 UTC: São Paulo vira para o dia 3 (00:00) e a diferença some —
      // exatamente no instante em que os dois calendários se encontram, e não
      // "uma hora depois" nem "quando o relógio redesenhar".
      await pumpAt(DateTime.utc(2026, 10, 3, 3), DateTime(2026, 10, 3, 0));
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('+1 dia'), findsNothing);
    });

    testWidgets('clicar no disco avisa a tela com o id da cidade', (
      tester,
    ) async {
      final city = clocks.first;
      final tapped = <String>[];
      await pumpMarkers(tester, cities: [city], onSelect: tapped.add);

      await tester.tap(discFinder());
      await tester.pump();

      expect(tapped, [city.city.id]);
    });

    testWidgets('sem handler, o disco não quebra ao ser clicado', (
      tester,
    ) async {
      await pumpMarkers(tester, cities: [clocks.first]);

      await tester.tap(discFinder());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('o overlay nunca cobre o próprio disco', (tester) async {
      for (final clock in clocks) {
        await pumpMarkers(
          tester,
          cities: [clock],
          pinnedIds: {clock.city.id},
        );

        final mapRect = tester.getRect(find.byType(CityMarkers));
        final center =
            mapRect.topLeft + CityMarkers.offsetFor(clock.city, mapRect.size);
        final disc = Rect.fromCenter(
          center: center,
          width: CityMarkers.diameter,
          height: CityMarkers.diameter,
        );

        expect(
          tester.getRect(find.byType(PanelCard)).overlaps(disc),
          isFalse,
          reason: 'overlay cobriu o disco de ${clock.city.name}',
        );
      }
    });

    testWidgets('nenhum texto do overlay sai cortado', (tester) async {
      await pumpMarkers(
        tester,
        cities: clocks,
        pinnedIds: {for (final clock in clocks) clock.city.id},
      );

      // Dois cartões, quatro textos cada (nome, país, hora, fuso).
      final texts = find.byType(Text).evaluate().toList();
      expect(texts.length, greaterThanOrEqualTo(8));
      for (final element in texts) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '"${(element.widget as Text).data}" não caberia no overlay',
        );
      }
    });
  });

  group('integração com a tela', () {
    /// O mapa de verdade com a camada de cidades por cima, na mesma relação de
    /// irmandade do `main.dart`: o teste do contrato precisa dos dois.
    ///
    /// `setSurfaceSize` fica FORA do `runAsync`: ele espera um quadro, e o
    /// `runAsync` suspende o relógio falso que produz esse quadro — dentro dele
    /// a espera nunca termina.
    Future<void> pumpScreen(
      WidgetTester tester, {
      required List<CityClock> cities,
      String? selectedId,
      Set<String> pinned = const <String>{},
    }) async {
      await tester.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: mapSize.width,
                  height: mapSize.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(child: WorldDotMap(now: now)),
                      ),
                      Positioned.fill(
                        child: CityMarkers(
                          cities: cities,
                          mapSize: mapSize,
                          now: now,
                          here: here,
                          land: MapThemes.standard.land,
                          background: MapThemes.standard.background,
                          selectedId: selectedId,
                          pinnedIds: pinned,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });
    }

    CustomPainter mapPainter(WidgetTester tester) {
      final finder = find.descendant(
        of: find.byType(WorldDotMap),
        matching: find.byType(CustomPaint),
      );
      expect(finder, findsOneWidget);
      return tester.widget<CustomPaint>(finder).painter!;
    }

    testWidgets('selecionar e fixar não repinta os pontos do mapa', (
      tester,
    ) async {
      await pumpScreen(tester, cities: clocks);

      final before = mapPainter(tester);

      // Abrir o overlay de uma cidade e prender a outra muda SÓ a camada de
      // marcadores; os pontos do mapa seguem recebendo os mesmos dados.
      await pumpScreen(
        tester,
        cities: clocks,
        selectedId: clocks.first.city.id,
        pinned: {clocks.last.city.id},
      );

      expect(find.byType(PanelCard), findsNWidgets(2));
      expect(
        mapPainter(tester).shouldRepaint(before),
        isFalse,
        reason: 'o relógio das cidades não pode sujar os pontos do mapa',
      );
    });
  });
}
