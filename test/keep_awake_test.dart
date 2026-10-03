import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_clock/keep_awake.dart';
import 'package:world_clock/main.dart';
import 'package:world_clock/settings_menu.dart';
import 'package:world_clock/user_location.dart';

/// Posição fixa nos testes: nenhuma consulta de verdade — sem rede, sem
/// permissão e sem espera (o ponto do usuário tem testes próprios).
Future<UserLocation> noLocation() async =>
    const UserLocation.failed(UserLocationFailure.unavailable);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemKeepAwake (o pedido ao `wakelock_plus`)', () {
    late List<bool> toggles;

    /// O lado do `wakelock_plus` de mentira: ele existe para o teste não
    /// depender de plugin nativo registrado (que não existe no `flutter test`)
    /// e para poder RECUSAR o pedido, que é o caso da plataforma negando.
    SystemKeepAwake keepAwake({Object? failure}) => SystemKeepAwake(
      toggle: ({required bool enable}) async {
        if (failure != null) {
          throw failure;
        }
        toggles.add(enable);
      },
    );

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      toggles = <bool>[];
    });

    test('ligar pede o wakelock ligado e guarda a escolha', () async {
      await keepAwake().setEnabled(true);

      expect(toggles, [true]);

      // Guardada: é isso que faz a opção voltar ligada na próxima abertura —
      // em vez de o usuário ter de ligá-la de novo toda vez. O `toggle` é o
      // `WakelockPlus`, o MESMO em Android, iOS, macOS, Windows, Linux e web:
      // nenhum código nativo deste projeto entra no caminho.
      expect(await keepAwake().savedChoice(), isTrue);
    });

    test('desligar pede o wakelock desligado e guarda o desligado', () async {
      await keepAwake().setEnabled(false);

      expect(toggles, [false]);
      expect(await keepAwake().savedChoice(), isFalse);
    });

    test(
      'sem escolha guardada, a leitura é desligada (e não um erro)',
      () async {
        expect(await keepAwake().savedChoice(), isFalse);
        expect(toggles, isEmpty);
      },
    );

    test(
      'pedido recusado pela plataforma: o erro sobe e NADA é gravado',
      () async {
        await expectLater(
          keepAwake(
            failure: PlatformException(code: 'assertion_failed'),
          ).setEnabled(true),
          throwsA(isA<PlatformException>()),
        );

        // Gravar uma escolha que não entrou em vigor faria o app tentar
        // reaplicá-la (e falhar de novo, agora em silêncio) a cada abertura.
        expect(await keepAwake().savedChoice(), isFalse);
      },
    );
  });

  group('a opção "Manter tela ligada" na tela', () {
    /// Abre o menu da bandeja, como o usuário faz (só clique abre).
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
    }

    /// Monta a tela e deixa as leituras assíncronas (catálogo, escolha
    /// guardada) chegarem.
    ///
    /// Chame de DENTRO do `runAsync` do teste: a espera precisa de tempo real, e
    /// `runAsync` aninhado é recusado pelo `flutter_test`.
    Future<void> pumpScreen(WidgetTester tester, {KeepAwake? keepAwake}) async {
      await tester.pumpWidget(
        WorldClockApp(locationLookup: noLocation, keepAwake: keepAwake),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }

    /// Estado da opção como a tela o publica no menu.
    bool keepScreenOn(WidgetTester tester) =>
        tester.widget<SettingsMenu>(find.byType(SettingsMenu)).keepScreenOn;

    /// Quantas caixinhas cheias o painel mostra. Contado em RELAÇÃO ao estado
    /// anterior porque o painel tem mais de uma caixinha (o crepúsculo vem
    /// ligado por padrão) — contar o ícone solto diria da linha errada.
    int checkedBoxes() => find.byIcon(Icons.check_box).evaluate().length;

    testWidgets('sem KeepAwake injetado, a linha nem aparece no menu', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await pumpScreen(tester);
        await openMenu(tester);

        // O menu abriu…
        expect(find.text('Incluir crepúsculo'), findsOneWidget);
        // …e a opção não existe, porque não há quem segure a tela: uma
        // caixinha que alterna sozinha sem efeito nenhum seria pior que a
        // ausência da opção.

        expect(find.text('Manter tela ligada'), findsNothing);

        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('a escolha guardada volta ligada na abertura', (tester) async {
      final keepAwake = MemoryKeepAwake(choice: true);

      await tester.runAsync(() async {
        await pumpScreen(tester, keepAwake: keepAwake);
        await openMenu(tester);

        // A tela pediu ao nativo assim que subiu, sem o usuário clicar…
        expect(keepAwake.applied, [true]);
        // …e a caixinha já aparece cheia.
        expect(keepScreenOn(tester), isTrue);

        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('clicar na linha liga e desliga, avisando o nativo', (
      tester,
    ) async {
      final keepAwake = MemoryKeepAwake();

      await tester.runAsync(() async {
        await pumpScreen(tester, keepAwake: keepAwake);
        await openMenu(tester);

        // Desligada por padrão e nada foi pedido ao nativo: quem não pediu não
        // tem o Mac segurando o sono da tela.
        expect(keepScreenOn(tester), isFalse);
        expect(keepAwake.applied, isEmpty);

        final before = checkedBoxes();
        await tester.tap(find.text('Manter tela ligada'));
        await tester.pumpAndSettle();

        expect(keepAwake.applied, [true]);
        expect(keepScreenOn(tester), isTrue);
        expect(checkedBoxes(), before + 1);
        // O menu continua aberto: dá para ligar e desligar sem reabrir.
        expect(find.text('Manter tela ligada'), findsOneWidget);

        await tester.tap(find.text('Manter tela ligada'));
        await tester.pumpAndSettle();

        expect(keepAwake.applied, [true, false]);
        expect(keepScreenOn(tester), isFalse);
        expect(checkedBoxes(), before);

        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('assertion recusada: a caixinha volta vazia e o motivo aparece '
        'no menu', (tester) async {
      final keepAwake = MemoryKeepAwake(
        failure: PlatformException(code: 'assertion_failed'),
      );

      await tester.runAsync(() async {
        await pumpScreen(tester, keepAwake: keepAwake);
        await openMenu(tester);

        final before = checkedBoxes();
        await tester.tap(find.text('Manter tela ligada'));
        await tester.pumpAndSettle();

        // Nada foi aplicado…
        expect(keepAwake.applied, isEmpty);
        // …a caixinha NÃO fica mentindo…
        expect(keepScreenOn(tester), isFalse);
        expect(checkedBoxes(), before);
        // …e a falha não é silenciosa: o menu diz o que aconteceu.
        expect(find.text('não deu para manter a tela ligada'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('a falha não deixa resíduo: o clique seguinte volta a tentar '
        'e o motivo some quando dá certo', (tester) async {
      final keepAwake = MemoryKeepAwake(
        failure: PlatformException(code: 'assertion_failed'),
      );

      await tester.runAsync(() async {
        await pumpScreen(tester, keepAwake: keepAwake);
        await openMenu(tester);

        await tester.tap(find.text('Manter tela ligada'));
        await tester.pumpAndSettle();
        expect(find.text('não deu para manter a tela ligada'), findsOneWidget);

        // O nativo passa a aceitar (o caso de um bloqueio temporário).
        keepAwake.failure = null;
        await tester.tap(find.text('Manter tela ligada'));
        await tester.pumpAndSettle();

        expect(keepAwake.applied, [true]);
        expect(keepScreenOn(tester), isTrue);
        expect(find.text('não deu para manter a tela ligada'), findsNothing);

        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}
