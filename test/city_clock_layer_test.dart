import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:world_clock/city_catalog.dart';
import 'package:world_clock/city_clock.dart';
import 'package:world_clock/city_clock_layer.dart';
import 'package:world_clock/city_markers.dart';
import 'package:world_clock/map_theme.dart';

/// O ticker do relógio: a hora anda sozinha, na virada do minuto, sem
/// reconstruir nada além da própria camada.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mapSize = Size(1200, 600);

  late CityClock tokyo;

  // O catálogo é lido no setUpAll: dentro de um `testWidgets` o relógio falso
  // do flutter_test nunca completa o I/O de verdade do asset.
  setUpAll(() async {
    tzdata.initializeTimeZones();
    final catalog = await CityCatalog.load();
    tokyo = CityClock(catalog.firstWhere((city) => city.name == 'Tóquio'));
  });

  group('até a próxima virada de minuto', () {
    test('meio do minuto espera os segundos que faltam', () {
      expect(
        untilNextMinute(DateTime(2026, 10, 3, 12, 0, 20, 0)),
        const Duration(seconds: 40, milliseconds: 50),
      );
    });

    test('na virada exata espera o minuto inteiro', () {
      expect(
        untilNextMinute(DateTime(2026, 10, 3, 12, 0, 0, 0)),
        const Duration(seconds: 60, milliseconds: 50),
      );
    });

    test('a folga cobre o timer que dispara um fio antes', () {
      // 59,999 s: sem a folga, o tique cairia dentro do minuto velho e o
      // relógio ficaria um minuto atrasado.
      final almost = untilNextMinute(DateTime(2026, 10, 3, 12, 0, 59, 999));
      expect(almost, greaterThan(Duration.zero));
      expect(almost.inMilliseconds, 51);

      // E nunca é negativo, em nenhum ponto do minuto.
      for (var second = 0; second < 60; second++) {
        for (final ms in [0, 1, 500, 998, 999]) {
          final wait = untilNextMinute(DateTime(2026, 10, 3, 12, 0, second, ms));
          expect(
            wait,
            greaterThan(Duration.zero),
            reason: 'espera não-positiva em $second s + $ms ms',
          );
        }
      }
    });
  });

  group('na tela', () {
    /// Monta a camada com um relógio controlado pelo teste.
    Future<void> pumpLayer(
      WidgetTester tester,
      DateTime Function() clock,
    ) async {
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
                    child: CityClockLayer(
                      cities: [tokyo],
                      mapSize: mapSize,
                      land: MapThemes.standard.land,
                      background: MapThemes.standard.background,
                      pinnedIds: {tokyo.city.id},
                      clock: clock,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('mostra a hora do instante em que abriu', (tester) async {
      await pumpLayer(tester, () => DateTime.utc(2026, 10, 3, 12, 0, 20));

      expect(find.text('21:00'), findsOneWidget);
    });

    testWidgets('o minuto vira sozinho, sem tocar em nada', (tester) async {
      var now = DateTime.utc(2026, 10, 3, 12, 0, 20);
      await pumpLayer(tester, () => now);

      expect(find.text('21:00'), findsOneWidget);

      // 40 s depois o minuto vira (12:01 UTC é 21:01 em Tóquio): o tique tem de
      // cair sozinho, só por o tempo passar.
      now = DateTime.utc(2026, 10, 3, 12, 1, 5);
      await tester.pump(const Duration(seconds: 45));

      expect(find.text('21:01'), findsOneWidget);
    });

    testWidgets('NÃO reconstrói antes da virada do minuto', (tester) async {
      final now = DateTime.utc(2026, 10, 3, 12, 0, 20);
      await pumpLayer(tester, () => now);

      CityClockLayer layer() =>
          tester.widget<CityClockLayer>(find.byType(CityClockLayer));
      CityMarkers markers() =>
          tester.widget<CityMarkers>(find.byType(CityMarkers));

      // Um rebuild por segundo seria 60x mais trabalho para o mesmo desenho: o
      // tique tem de ser um só, na virada.
      final before = markers();
      await tester.pump(const Duration(seconds: 20));
      expect(identical(markers(), before), isTrue, reason: 'reconstruiu cedo');

      final layerBefore = layer();
      await tester.pump(const Duration(seconds: 21));
      expect(
        identical(layer(), layerBefore),
        isTrue,
        reason: 'a própria camada não pode se reconstruir antes da hora',
      );
    });

    testWidgets('desmontar cancela o ticker', (tester) async {
      await pumpLayer(tester, () => DateTime.utc(2026, 10, 3, 12, 0, 20));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));

      // Sem o `cancel` no dispose, o timer seguiria pendente e o flutter_test
      // reprovaria o teste no fim ("A Timer is still pending").
      expect(tester.takeException(), isNull);
    });
  });
}
