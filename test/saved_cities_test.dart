import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:world_clock/city.dart';
import 'package:world_clock/city_catalog.dart';
import 'package:world_clock/city_markers.dart';
import 'package:world_clock/city_store.dart';
import 'package:world_clock/main.dart';
import 'package:world_clock/panel_card.dart';
import 'package:world_clock/user_location.dart';
import 'package:world_clock/world_dot_map.dart';

/// A tela com cidades salvas de verdade: o que o disco entrega vira ponto no
/// mapa, clique abre o overlay e um id que sumiu do catálogo não derruba nada.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Posição do usuário fixa: nenhuma consulta de verdade, sem rede nem
  /// permissão (o ponto do usuário tem testes próprios).
  Future<UserLocation> noLocation() async =>
      const UserLocation.failed(UserLocationFailure.unavailable);

  late City fortaleza;
  late City tokyo;

  setUpAll(() async {
    tzdata.initializeTimeZones();
    // AQUECER o catálogo aqui é o que faz a tela conseguir carregá-lo dentro
    // dos testes: ler o asset é I/O de verdade, e dentro de um `testWidgets` o
    // relógio falso não completa esse `Future`. Com o `Future` já resolvido, o
    // `await` da tela vira um microtask, que o `pump` escoa.
    final catalog = await CityCatalog.load();
    fortaleza = catalog.firstWhere(
      (city) => city.name == 'Fortaleza' && city.region == 'Ceará',
    );
    tokyo = catalog.firstWhere((city) => city.name == 'Tóquio');
  });

  Finder discs() => find.descendant(
    of: find.byType(CityMarkers),
    matching: find.byType(CustomPaint),
  );

  /// Monta a TELA de verdade — o caminho inteiro, do `WorldMapScreen` ao
  /// marcador, e não a camada isolada.
  ///
  /// O `runAsync` é obrigatório: a restauração das cidades passa por I/O de
  /// verdade (o asset do catálogo e o disco), e dentro do relógio falso do
  /// `testWidgets` essa cadeia não anda. `setSurfaceSize` fica FORA dele: ele
  /// espera um quadro, e o `runAsync` suspende quem produz esse quadro.
  Future<void> pumpScreen(WidgetTester tester, CityStore? store) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorldMapScreen(locationLookup: noLocation, cityStore: store),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    // A tela abre sem marcador e eles entram quando a leitura volta; este
    // quadro é o que desenha o resultado.
    await tester.pump();
  }

  /// Desmonta para o ticker de 5 minutos da tela ser cancelado — sem isso o
  /// flutter_test reprova o teste por timer pendente.
  Future<void> tearDownScreen(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('cidade salva vira ponto no mapa, sem overlay', (tester) async {
    final store = MemoryCityStore(SavedCities(selected: {fortaleza.id}));
    await pumpScreen(tester, store);

    expect(discs(), findsOneWidget);
    expect(find.byType(PanelCard), findsNothing);

    await tearDownScreen(tester);
  });

  testWidgets('id que sumiu do catálogo é descartado, e o resto fica', (
    tester,
  ) async {
    final store = MemoryCityStore(
      SavedCities(selected: {fortaleza.id, 'id-que-nao-existe-mais'}),
    );
    await pumpScreen(tester, store);

    expect(discs(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tearDownScreen(tester);
  });

  testWidgets('cidade fixada abre o overlay já na abertura', (tester) async {
    final store = MemoryCityStore(
      SavedCities(selected: {tokyo.id}, pinned: {tokyo.id}),
    );
    await pumpScreen(tester, store);

    expect(find.text('Tóquio'), findsOneWidget);
    expect(find.text('Japão'), findsOneWidget);
    // Nove horas à frente de quem está em UTC-3, ou seja, outra hora do dia.
    expect(find.textContaining(':'), findsWidgets);

    await tearDownScreen(tester);
  });

  testWidgets('clicar no ponto abre o overlay; clicar de novo fecha', (
    tester,
  ) async {
    final store = MemoryCityStore(SavedCities(selected: {fortaleza.id}));
    await pumpScreen(tester, store);

    expect(find.byType(PanelCard), findsNothing);

    await tester.tap(discs());
    await tester.pump();

    expect(find.byType(PanelCard), findsOneWidget);
    expect(find.text('Fortaleza'), findsOneWidget);
    expect(find.text('Brasil'), findsOneWidget);
    expect(find.text('UTC-03'), findsOneWidget);

    // Clicar de novo na MESMA cidade fecha — o disco é um interruptor, e não
    // uma porta de mão única.
    await tester.tap(discs());
    await tester.pump();

    expect(find.byType(PanelCard), findsNothing);

    await tearDownScreen(tester);
  });

  testWidgets('sem store, a tela não lê nada e abre normalmente', (
    tester,
  ) async {
    // O padrão é sem persistência (o `shared_preferences` é plugin e não
    // responde num teste sem preparo). Este teste é o que garante que a maioria
    // dos testes da tela — que não passa store nenhum — continue valendo.
    await pumpScreen(tester, null);

    expect(find.byType(WorldDotMap), findsOneWidget);
    expect(discs(), findsNothing);
    expect(tester.takeException(), isNull);

    await tearDownScreen(tester);
  });

  testWidgets('selecionar uma cidade não repinta os pontos do mapa', (
    tester,
  ) async {
    final store = MemoryCityStore(SavedCities(selected: {fortaleza.id}));
    await pumpScreen(tester, store);

    CustomPainter mapPainter() {
      final finder = find.descendant(
        of: find.byType(WorldDotMap),
        matching: find.byType(CustomPaint),
      );
      return tester.widget<CustomPaint>(finder).painter!;
    }

    final before = mapPainter();

    await tester.tap(discs());
    await tester.pump();

    expect(find.byType(PanelCard), findsOneWidget);
    expect(
      mapPainter().shouldRepaint(before),
      isFalse,
      reason: 'abrir o overlay de uma cidade não pode sujar os pontos do mapa',
    );

    await tearDownScreen(tester);
  });
}
