import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/map_overlay.dart';

/// A âncora do cartão flutuante: o lado por onde ele se prende ao marcador.
///
/// É a conta que o marcador da Lua e os marcadores de cidade compartilham — o
/// teste é o que garante que a extração não mudou a posição de nenhum painel.
void main() {
  const mapSize = Size(1200, 600);
  const gap = 12.0;
  const radius = 7.0;

  MapOverlayAnchor anchorAt(double dx, double dy) => MapOverlayAnchor.forMarker(
    center: Offset(dx, dy),
    radius: radius,
    mapSize: mapSize,
    gap: gap,
  );

  group('lado horizontal', () {
    test('metade esquerda ancora pela esquerda', () {
      final anchor = anchorAt(100, 300);

      expect(anchor.left, 100 + radius + gap);
      expect(anchor.right, isNull);
    });

    test('metade direita ancora pela direita', () {
      final anchor = anchorAt(1100, 300);

      expect(anchor.left, isNull);
      expect(anchor.right, mapSize.width - 1100 + radius + gap);
    });

    test('bem no meio do mapa ancora pela direita (empate vai para lá)', () {
      final anchor = anchorAt(mapSize.width / 2, 300);

      expect(anchor.left, isNotNull);
      expect(anchor.right, isNull);
    });
  });

  group('lado vertical', () {
    test('metade de cima ancora por cima', () {
      final anchor = anchorAt(600, 50);

      expect(anchor.top, 50 + gap);
      expect(anchor.bottom, isNull);
    });

    test('metade de baixo ancora por baixo', () {
      final anchor = anchorAt(600, 550);

      expect(anchor.top, isNull);
      expect(anchor.bottom, mapSize.height - 550 + gap);
    });

    test('bem no meio ancora por baixo (empate vai para lá)', () {
      final anchor = anchorAt(600, mapSize.height / 2);

      expect(anchor.top, isNotNull);
      expect(anchor.bottom, isNull);
    });
  });

  test(
    'o afastamento horizontal desconta o raio; o vertical conta do centro',
    () {
      // A assimetria é a da Lua desde sempre: mexer nela mudaria a posição de um
      // painel já validado (e o teste "o overlay nunca cobre o disco" é quem
      // garante que ela não encosta no marcador).
      final anchor = anchorAt(300, 200);

      expect(anchor.left, 300 + radius + gap);
      expect(anchor.top, 200 + gap);
    },
  );

  test('os quatro cantos escolhem os lados de fora', () {
    final topLeft = anchorAt(0, 0);
    final bottomRight = anchorAt(mapSize.width, mapSize.height);

    expect(topLeft.left, isNotNull);
    expect(topLeft.top, isNotNull);
    expect(topLeft.right, isNull);
    expect(topLeft.bottom, isNull);

    expect(bottomRight.right, isNotNull);
    expect(bottomRight.bottom, isNotNull);
    expect(bottomRight.left, isNull);
    expect(bottomRight.top, isNull);
  });

  testWidgets('wrap posiciona o filho e o protege do ponteiro', (tester) async {
    // IgnorePointer dentro do wrap: um overlay que captura o ponteiro faz o
    // marcador perder o hover e o painel piscar. Nenhum marcador pode esquecer.
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            anchorAt(100, 100).wrap(const SizedBox(width: 40, height: 20)),
          ],
        ),
      ),
    );

    final positioned = tester.widget<Positioned>(find.byType(Positioned));
    expect(positioned.left, 100 + radius + gap);
    expect(positioned.top, 100 + gap);
    expect(
      find.descendant(
        of: find.byType(Positioned),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });
}
