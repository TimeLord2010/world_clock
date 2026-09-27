import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/main.dart';
import 'package:world_clock/map_theme.dart';
import 'package:world_clock/settings_menu.dart';
import 'package:world_clock/world_dot_map.dart';

/// Cores do tema, e a bandeja de opções do canto superior direito: abre por
/// hover e por clique, o item "Tema" abre o submenu, e escolher um tema troca a
/// paleta do mapa.
void main() {
  group('MapThemes', () {
    test('o tema padrão é exatamente o que o mapa já usava por default', () {
      expect(MapThemes.standard.land, WorldDotMap.defaultDotColor);
      expect(MapThemes.standard.ocean, WorldDotMap.defaultOceanColor);
      expect(MapThemes.standard.background, WorldDotMap.defaultBackgroundColor);
    });

    test('monocromático branco só usa branco, preto e cinza', () {
      final mono = MapThemes.monoWhite;
      for (final color in [mono.land, mono.ocean, mono.background]) {
        expect(
          color.r,
          color.g,
          reason: 'canal R e G diferentes em $color: a cor não é neutra',
        );
        expect(color.g, color.b, reason: 'canal G e B diferentes em $color');
      }
    });

    test('o submenu mostra o padrão primeiro, e as duas cores por tema', () {
      expect(MapThemes.all.first, MapThemes.standard);
      expect(MapThemes.all, contains(MapThemes.monoWhite));
      expect(MapThemes.all.length, 2);
      for (final theme in MapThemes.all) {
        expect(theme.swatch.length, 2);
        expect(theme.swatch, [theme.land, theme.ocean]);
      }
    });
  });

  group('bandeja de opções', () {
    /// Monta só a bandeja, com um tema selecionável registrado.
    Future<List<MapTheme>> pumpMenu(
      WidgetTester tester, {
      MapTheme theme = MapThemes.standard,
      Size size = const Size(600, 400),
    }) async {
      final picked = <MapTheme>[];
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsMenu(theme: theme, onThemeSelected: picked.add),
          ),
        ),
      );
      return picked;
    }

    /// Adiciona UM ponteiro de mouse (o MouseTracker só aceita um por vez) e o
    /// deixa parado em cima de [target].
    Future<TestGesture> mouseAt(WidgetTester tester, Offset target) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(1, 1));
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pumpAndSettle();
      return gesture;
    }

    testWidgets(
      'fechada por padrão, e o ícone está no canto superior direito',
      (tester) async {
        await pumpMenu(tester);

        expect(find.text('Tema'), findsNothing);
        final topRight = tester.getTopRight(find.byIcon(Icons.menu));
        expect(topRight.dx, greaterThan(600 - 60));
        expect(topRight.dy, lessThan(60));
      },
    );

    testWidgets('mouse em cima do ícone NÃO abre o menu (só clique)', (
      tester,
    ) async {
      await pumpMenu(tester);

      final mouse = await mouseAt(
        tester,
        tester.getCenter(find.byIcon(Icons.menu)),
      );
      expect(find.text('Tema'), findsNothing);

      // …e passar o mouse por dentro do menu aberto também não abre submenu nem
      // fecha nada: quem manda é o clique.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('Tema'), findsOneWidget);

      await mouse.moveTo(tester.getCenter(find.text('Tema')));
      await tester.pumpAndSettle();
      expect(find.text('Padrão'), findsNothing); // submenu não abriu sozinho

      await mouse.moveTo(const Offset(300, 300));
      await tester.pumpAndSettle();
      expect(find.text('Tema'), findsOneWidget); // não fechou ao sair
    });

    testWidgets('aberta por clique fica aberta com o ponteiro fora, e um '
        'clique fora fecha', (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('Tema'), findsOneWidget);

      await tester.tapAt(const Offset(300, 300));
      await tester.pumpAndSettle();
      expect(find.text('Tema'), findsNothing);
    });

    testWidgets('Esc fecha o menu aberto por clique', (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('Tema'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Tema'), findsNothing);
    });

    testWidgets('clicar no item "Tema" abre o submenu com os dois temas', (
      tester,
    ) async {
      await pumpMenu(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('Padrão'), findsNothing);

      await tester.tap(find.text('Tema'));
      await tester.pumpAndSettle();
      expect(find.text('Padrão'), findsOneWidget);
      expect(find.text('Monocromático branco'), findsOneWidget);
      expect(
        find.byType(ThemeSwatch),
        findsNWidgets(3),
      ); // 2 temas + o item Tema

      // Clicar de novo em "Tema" fecha o submenu.
      await tester.tap(find.text('Tema'));
      await tester.pumpAndSettle();
      expect(find.text('Padrão'), findsNothing);

      await tester.tap(find.text('Tema'));
      await tester.pumpAndSettle();

      // Nenhum rótulo sai cortado: o painel é dimensionado pelo conteúdo, então
      // até a fonte do flutter_test (1 em por caractere, bem mais larga que a
      // fonte real) cabe inteira. Se alguém voltar a fixar a largura do painel,
      // é aqui que quebra.
      for (final label in ['Tema', 'Padrão', 'Monocromático branco']) {
        final para = tester.renderObject<RenderParagraph>(find.text(label));
        expect(
          para.didExceedMaxLines,
          isFalse,
          reason: '"$label" não caberia na largura do painel',
        );
      }
    });

    testWidgets('escolher um tema avisa a tela e fecha o menu', (tester) async {
      final picked = await pumpMenu(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tema'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monocromático branco'));
      await tester.pumpAndSettle();

      expect(picked, [MapThemes.monoWhite]);
      expect(find.text('Monocromático branco'), findsNothing);
      expect(find.text('Tema'), findsNothing);
    });
  });

  group('swatch do tema', () {
    testWidgets('as duas metades se tocam: a divisão é uma linha de largura '
        'zero, sem costura', (tester) async {
      await tester.runAsync(() async {
        const key = ValueKey('swatch');
        // Cores chapadas (não MaterialColor) para poder comparar pixel a pixel.
        const top = Color(0xFFF44336);
        const bottom = Color(0xFF2196F3);
        await tester.pumpWidget(
          const MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: ThemeSwatch(colors: [top, bottom], size: 40),
              ),
            ),
          ),
        );

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final image = await boundary.toImage();
        expect(image.width, 40);
        expect(image.height, 40);
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();

        Color at(int x, int y) {
          final i = (y * image.width + x) * 4;
          return Color.fromARGB(
            pixels[i + 3],
            pixels[i],
            pixels[i + 1],
            pixels[i + 2],
          );
        }

        bool near(Color a, Color b) =>
            (a.r - b.r).abs() < 0.02 &&
            (a.g - b.g).abs() < 0.02 &&
            (a.b - b.b).abs() < 0.02;

        // Coluna do centro: metade de cima vermelha, metade de baixo azul…
        // (as linhas 0..2 e 37..39 ficam de fora: são a borda do círculo e o
        // anel de contorno, onde a antialiasing mistura as cores de propósito)
        for (var y = 3; y <= 36; y++) {
          final expected = y < 20 ? top : bottom; // 20 = o meio
          expect(
            near(at(20, y), expected),
            isTrue,
            reason: 'linha $y deveria ser $expected e é ${at(20, y)}',
          );
        }

        // …e na linha exata da divisão (19 → 20) nada de outra cor aparece:
        // não há gap, nem linha desenhada, nem bleeding do fundo.
        expect(at(20, 19), top);
        expect(at(20, 20), bottom);
      });
    });
  });

  group('integração com a tela', () {
    testWidgets('escolher o monocromático troca a paleta do mapa', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(const WorldClockApp());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();

        expect(
          tester.widget<WorldDotMap>(find.byType(WorldDotMap)).dotColor,
          MapThemes.standard.land,
        );

        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tema'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Monocromático branco'));
        await tester.pumpAndSettle();

        final map = tester.widget<WorldDotMap>(find.byType(WorldDotMap));
        expect(map.dotColor, Colors.white);
        expect(map.oceanColor, MapThemes.monoWhite.ocean);
        expect(map.backgroundColor, MapThemes.monoWhite.background);
        expect(find.text('Tema'), findsNothing);

        // Desmonta para o timer de 30 min da tela ser cancelado.
        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}
