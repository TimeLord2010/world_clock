import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:world_clock/city.dart';
import 'package:world_clock/city_catalog.dart';
import 'package:world_clock/city_picker.dart';
import 'package:world_clock/map_theme.dart';
import 'package:world_clock/settings_menu.dart';

/// O painel de cidades: buscar, salvar/retirar, fixar — e chegar nele pelo menu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<City> catalog;
  late City fortaleza;
  late City tokyo;

  setUpAll(() async {
    tzdata.initializeTimeZones();
    // O catálogo é lido AQUI: dentro de um `testWidgets` o relógio falso não
    // completa o I/O de verdade do asset.
    catalog = await CityCatalog.load();
    fortaleza = catalog.firstWhere(
      (city) => city.name == 'Fortaleza' && city.region == 'Ceará',
    );
    tokyo = catalog.firstWhere((city) => city.name == 'Tóquio');
  });

  /// O painel com estado de verdade, como a tela o mantém: salvar tira e põe,
  /// e o painel tem de refletir isso na hora.
  Future<_HarnessState> pumpPicker(
    WidgetTester tester, {
    Set<String> saved = const <String>{},
    Set<String> pinned = const <String>{},
    List<City>? cities,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: _Harness(
              cities: cities ?? catalog,
              saved: saved,
              pinned: pinned,
            ),
          ),
        ),
      ),
    );
    return tester.state<_HarnessState>(find.byType(_Harness));
  }

  /// Digita na busca e deixa a lista refiltrar.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump();
  }

  group('busca', () {
    testWidgets('abre mostrando as maiores cidades', (tester) async {
      await pumpPicker(tester);

      expect(find.text('Tóquio'), findsOneWidget);
      // A lista é preguiçosa e limitada em altura: não desenha 7 mil linhas.
      expect(
        find.byType(Text).evaluate().length,
        lessThan(200),
        reason: 'a lista não pode construir o catálogo inteiro',
      );
    });

    testWidgets('filtra sem acento e mostra o contexto para desambiguar', (
      tester,
    ) async {
      await pumpPicker(tester);
      await search(tester, 'fortaleza');

      expect(find.text('Fortaleza'), findsOneWidget);
      expect(find.text('Ceará, Brasil'), findsOneWidget);
      expect(find.text('Tóquio'), findsNothing);
    });

    testWidgets('acha "Tóquio" digitando "tokio"', (tester) async {
      await pumpPicker(tester);
      await search(tester, 'tokio');

      expect(find.text('Tóquio'), findsOneWidget);
    });

    testWidgets('as duas Sydney aparecem, distinguíveis pelo contexto', (
      tester,
    ) async {
      await pumpPicker(tester);
      await search(tester, 'sydney');

      expect(find.text('Sydney'), findsNWidgets(2));
      expect(find.textContaining('New South Wales'), findsOneWidget);
      expect(find.textContaining('Nova Scotia'), findsOneWidget);
    });

    testWidgets('consulta sem resultado diz isso, em vez de ficar vazia', (
      tester,
    ) async {
      await pumpPicker(tester);
      await search(tester, 'zzzzzzzz');

      expect(find.text('Nenhuma cidade encontrada'), findsOneWidget);
    });

    testWidgets('catálogo que ainda não chegou diz que está carregando', (
      tester,
    ) async {
      await pumpPicker(tester, cities: const <City>[]);

      expect(find.text('Carregando o catálogo…'), findsOneWidget);
    });

    testWidgets('nome longo é cortado com reticências, sem estourar o layout', (
      tester,
    ) async {
      // A largura do painel é fixa (é o que dá chão à caixa de busca), então o
      // corte AQUI é deliberado — ao contrário do overlay do mapa, que se
      // dimensiona pelo conteúdo e não corta nada.
      final longest = catalog.reduce(
        (a, b) => a.name.length >= b.name.length ? a : b,
      );
      expect(longest.name.length, greaterThan(20), reason: 'vale o teste');

      // Estreita a janela para forçar o corte.
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: _Harness(cities: [longest], saved: {longest.id}),
            ),
          ),
        ),
      );

      expect(find.text(longest.name), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'layout estourou');

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(longest.name),
      );
      expect(
        paragraph.didExceedMaxLines,
        isTrue,
        reason: 'num painel estreito o nome longo tem de ser cortado',
      );
    });
  });

  group('salvar, retirar e fixar', () {
    testWidgets('clicar na linha salva a cidade e avisa a tela', (
      tester,
    ) async {
      final state = await pumpPicker(tester);
      await search(tester, 'fortaleza');

      await tester.tap(find.text('Fortaleza'));
      await tester.pump();

      expect(state.toggled, [fortaleza.id]);
      expect(state.saved, {fortaleza.id});
      expect(find.text('1 salva'), findsOneWidget);
    });

    testWidgets('clicar de novo na cidade salva retira', (tester) async {
      final state = await pumpPicker(tester, saved: {fortaleza.id});
      await search(tester, 'fortaleza');

      await tester.tap(find.text('Fortaleza'));
      await tester.pump();

      expect(state.saved, isEmpty);
      expect(find.text('0 salvas'), findsOneWidget);
    });

    testWidgets('sem cidade salva não há controle de fixar', (tester) async {
      await pumpPicker(tester);
      await search(tester, 'tokyo');

      expect(find.byIcon(Icons.visibility), findsNothing);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    });

    testWidgets('o olho só aparece na cidade salva, e fixa o horário', (
      tester,
    ) async {
      final state = await pumpPicker(tester, saved: {fortaleza.id});
      await search(tester, 'fortaleza');

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();

      expect(state.pinned, {fortaleza.id});
      expect(find.byIcon(Icons.visibility), findsOneWidget);

      // E desfixa.
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();

      expect(state.pinned, isEmpty);
    });

    testWidgets('a contagem no cabeçalho acompanha o que está salvo', (
      tester,
    ) async {
      await pumpPicker(tester);
      expect(find.text('0 salvas'), findsOneWidget);

      // Salvar pela própria lista, e não remontando o painel com outro estado:
      // remontar o MESMO widget reaproveita o `State` (o `late` só inicializa
      // uma vez), então remontar não provaria nada sobre a contagem.
      await search(tester, 'fortaleza');
      await tester.tap(find.text('Fortaleza'));
      await tester.pump();
      expect(find.text('1 salva'), findsOneWidget);

      await search(tester, 'tokyo');
      await tester.tap(find.text('Tóquio'));
      await tester.pump();
      expect(find.text('2 salvas'), findsOneWidget);
    });

    testWidgets('a seta de voltar avisa quem montou o painel', (tester) async {
      var backs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CityPicker(
              cities: catalog,
              savedIds: const <String>{},
              pinnedIds: const <String>{},
              onToggleSaved: (_) {},
              onTogglePinned: (_) {},
              onBack: () => backs++,
              background: MapThemes.standard.background,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();

      expect(backs, 1);
    });
  });

  group('chegando pelo menu', () {
    Future<void> pumpMenu(
      WidgetTester tester, {
      Set<String> saved = const {},
    }) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsMenu(
              theme: MapThemes.standard,
              onThemeSelected: (_) {},
              includeTwilight: true,
              onTwilightChanged: (_) {},
              cities: catalog,
              savedCityIds: saved,
            ),
          ),
        ),
      );
    }

    testWidgets('a linha "Cidades" mostra a contagem e abre o painel', (
      tester,
    ) async {
      await pumpMenu(tester, saved: {fortaleza.id, tokyo.id});
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('Cidades'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.text('Cidades'));
      await tester.pumpAndSettle();

      // O painel de cidades SUBSTITUI o de opções (não abre ao lado dele).
      expect(find.byType(CityPicker), findsOneWidget);
      expect(find.text('Tema'), findsNothing);
      expect(find.text('Incluir crepúsculo'), findsNothing);
    });

    testWidgets('a seta de voltar retorna ao painel de opções', (tester) async {
      await pumpMenu(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cidades'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(CityPicker), findsNothing);
      expect(find.text('Tema'), findsOneWidget);
    });

    testWidgets('Esc fecha o menu mesmo com a busca em foco', (tester) async {
      // Decisão registrada: Esc é "fechar o menu" em todo o app, inclusive
      // enquanto se digita — o campo NÃO limpa com Esc. Sem isso, quem digitasse
      // e apertasse Esc ficaria preso no painel (ou perderia o texto sem
      // entender por quê).
      await pumpMenu(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cidades'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus ??
            true,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(CityPicker), findsNothing);
      expect(find.text('Cidades'), findsNothing);
    });
  });
}

/// O painel com estado: os testes precisam que salvar/fixar valham já no quadro
/// seguinte, como valem na tela de verdade.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.cities,
    this.saved = const <String>{},
    this.pinned = const <String>{},
  });

  final List<City> cities;
  final Set<String> saved;
  final Set<String> pinned;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late Set<String> saved = {...widget.saved};
  late Set<String> pinned = {...widget.pinned};

  /// Os ids avisados, na ordem — os testes conferem o que a tela recebeu.
  final List<String> toggled = <String>[];
  final List<String> pinnedToggled = <String>[];

  @override
  Widget build(BuildContext context) {
    return CityPicker(
      cities: widget.cities,
      savedIds: saved,
      pinnedIds: pinned,
      onToggleSaved: (id) => setState(() {
        toggled.add(id);
        if (!saved.remove(id)) {
          saved.add(id);
        }
      }),
      onTogglePinned: (id) => setState(() {
        pinnedToggled.add(id);
        if (!pinned.remove(id)) {
          pinned.add(id);
        }
      }),
      onBack: () {},
      background: MapThemes.standard.background,
    );
  }
}
