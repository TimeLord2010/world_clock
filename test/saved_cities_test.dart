import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:world_clock/city.dart';
import 'package:world_clock/city_catalog.dart';
import 'package:world_clock/city_markers.dart';
import 'package:world_clock/city_store.dart';
import 'package:world_clock/main.dart';
import 'package:world_clock/panel_card.dart';
import 'package:world_clock/settings_menu.dart';
import 'package:world_clock/user_location.dart';
import 'package:world_clock/world_dot_map.dart';

/// A tela com cidades salvas de verdade: o que o disco entrega vira ponto no
/// mapa COM o horário à vista, e um id que sumiu do catálogo não derruba nada.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Posição do usuário fixa: nenhuma consulta de verdade, sem rede nem
  /// permissão (o ponto do usuário tem testes próprios).
  Future<UserLocation> noLocation() async =>
      const UserLocation.failed(UserLocationFailure.unavailable);

  late City fortaleza;

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
  });

  Finder discs() => find.descendant(
    of: find.byType(CityMarkers),
    matching: find.byType(CustomPaint),
  );

  /// Um texto com cara de horário (`09:00`), sem fixar qual é: nesta tela o
  /// relógio é o do sistema.
  Finder clockText() => find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data != null &&
        RegExp(r'^\d{2}:\d{2}$').hasMatch(widget.data!),
  );

  /// Monta a TELA de verdade — o caminho inteiro, do `WorldMapScreen` ao
  /// marcador, e não a camada isolada.
  ///
  /// O `runAsync` é obrigatório: a restauração das cidades passa por I/O de
  /// verdade (o asset do catálogo e o disco), e dentro do relógio falso do
  /// `testWidgets` essa cadeia não anda. `setSurfaceSize` fica FORA dele: ele
  /// espera um quadro, e o `runAsync` suspende quem produz esse quadro.
  Future<void> pumpScreen(WidgetTester tester, CityStore? store) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
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

  testWidgets('cidade salva vira ponto COM o horário à vista, sem clique', (
    tester,
  ) async {
    final store = MemoryCityStore(SavedCities(selected: {fortaleza.id}));
    await pumpScreen(tester, store);

    expect(discs(), findsOneWidget);
    expect(find.text('Fortaleza'), findsOneWidget);
    expect(clockText(), findsOneWidget);

    await tearDownScreen(tester);
  });

  testWidgets('o rótulo do mapa não é cartão, e não tem país nem fuso', (
    tester,
  ) async {
    final store = MemoryCityStore(SavedCities(selected: {fortaleza.id}));
    await pumpScreen(tester, store);

    // O mapa e o rótulo não desenham cartão nenhum: `PanelCard` é do menu e do
    // painel da Lua, e nenhum dos dois está aberto.
    expect(find.byType(PanelCard), findsNothing);
    expect(find.text('Brasil'), findsNothing);
    expect(find.textContaining('UTC'), findsNothing);

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

  testWidgets('escolher a cidade no menu faz o horário dela aparecer no mapa', (
    tester,
  ) async {
    // O caminho inteiro, ponta a ponta: menu → painel de cidades → busca →
    // tocar na linha → gravar → marcador com horário no mapa.
    final store = MemoryCityStore();
    await pumpScreen(tester, store);

    expect(discs(), findsNothing);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cidades'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsMenu), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'fortaleza');
    await tester.pump();
    await tester.tap(find.text('Fortaleza'));
    await tester.pumpAndSettle();

    // Gravou a escolha...
    expect(store.saveCount, 1);
    expect(store.cities.selected, {fortaleza.id});

    // ...e o mapa já mostra o ponto com o horário. Fecha o menu para o painel
    // sair da frente e sobrar só o rótulo do mapa.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Fortaleza'), findsOneWidget);
    expect(clockText(), findsOneWidget);

    await tearDownScreen(tester);
  });
}
