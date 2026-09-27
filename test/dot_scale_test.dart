import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/world_dot_map.dart';

/// The dot scale: the decimation step is chosen from the legibility floor
/// ([WorldDotMap.minDotPt]), so a cramped window loses DENSITY instead of
/// shrinking the dots. Table below is the behaviour the user validated:
/// step 1 → 2 → 4 → 8 at 1080 / 540 / 270 / 135 pt of map width (dpr 2).
void main() {
  const dpr = 2.0;
  final floorPx = (WorldDotMap.minDotPt * dpr).round(); // 3 px físicos

  group('strideFor', () {
    test('the step doubles at 1080 / 540 / 270 / 135 pt (dpr-independent)', () {
      expect(
        [1920.0, 1440.0, 1080.0].map(WorldDotMap.strideFor),
        everyElement(1),
      );
      expect(
        [1079.9, 900.0, 540.0].map(WorldDotMap.strideFor),
        everyElement(2),
      );
      expect([539.9, 400.0, 270.0].map(WorldDotMap.strideFor), everyElement(4));
      expect(
        [269.9, 200.0, 135.0, 40.0].map(WorldDotMap.strideFor),
        everyElement(WorldDotMap.maxStride),
      );
    });

    test(
      'never steps past maxStride (a tiny/zero map cannot loop or divide)',
      () {
        expect(WorldDotMap.strideFor(0), WorldDotMap.maxStride);
        expect(WorldDotMap.strideFor(-10), WorldDotMap.maxStride);
        expect(WorldDotMap.strideFor(double.nan), WorldDotMap.maxStride);
        expect(WorldDotMap.strideFor(0.5), WorldDotMap.maxStride);
      },
    );
  });

  group('dotDiameterPx', () {
    test('the validated table (dpr 2)', () {
      // (largura do mapa, stride, diâmetro em px físicos)
      const table = <(double, int, int)>[
        (1920, 1, 5), // 2,5 pt — tela cheia: idêntico ao comportamento antigo
        (1440, 1, 4), // 2,0 pt
        (1200, 1, 3), // 1,5 pt
        (1080, 1, 3), // 1,5 pt — piso, fim do stride 1
        (1079, 2, 6), // 3,0 pt — virada
        (900, 2, 5), // 2,5 pt
        (540, 2, 3), // 1,5 pt — piso
        (539, 4, 6), // 3,0 pt — virada
        (360, 4, 4), // 2,0 pt
        (270, 4, 3), // 1,5 pt — piso
        (269, 8, 6), // 3,0 pt — virada
        (200, 8, 4), // 2,0 pt
        (135, 8, 3), // 1,5 pt — piso
        (100, 8, 3), // 1,5 pt — piso SEGURADO (sem novo passo disponível)
      ];
      for (final (width, expectedStride, expectedDotPx) in table) {
        final stride = WorldDotMap.strideFor(width);
        expect(stride, expectedStride, reason: 'stride em $width pt');
        expect(
          WorldDotMap.dotDiameterPx(width, dpr, stride),
          expectedDotPx,
          reason: 'diâmetro em $width pt',
        );
      }
    });

    test('a dot never renders below the floor, at any width or density', () {
      for (final density in [1.0, 2.0, 3.0]) {
        for (var w = 1.0; w <= 3000.0; w += 0.5) {
          final stride = WorldDotMap.strideFor(w);
          final dotPx = WorldDotMap.dotDiameterPx(w, density, stride);
          final floor = (WorldDotMap.minDotPt * density).round();
          expect(
            dotPx,
            greaterThanOrEqualTo(floor),
            reason: 'mapa ${w}pt, dpr $density, stride $stride',
          );
        }
      }
    });

    test('até a última virada a serra cabe em [1,5 · 3,0] pt', () {
      // Entre viradas o diâmetro vai do piso (na borda de baixo da faixa) ao
      // dobro dele (logo antes da próxima), em vez de cair a 1,0 pt com o
      // mapa na densidade máxima — o defeito que a opção 1 corrigiu.
      for (var w = 135.0; w <= 1080.0; w += 0.5) {
        final stride = WorldDotMap.strideFor(w);
        final dotPt = WorldDotMap.dotDiameterPx(w, dpr, stride) / dpr;
        expect(
          dotPt,
          inInclusiveRange(WorldDotMap.minDotPt, 2 * WorldDotMap.minDotPt),
          reason: 'mapa ${w}pt, stride $stride',
        );
      }
      // Acima da última virada o passo não sobe mais: o ponto volta a crescer
      // junto com o mapa (tela cheia: 2,5 pt em 1920 pt) — preservado.
      for (var w = 1080.0; w <= 3000.0; w += 0.5) {
        final dotPt =
            WorldDotMap.dotDiameterPx(w, dpr, WorldDotMap.strideFor(w)) / dpr;
        expect(
          dotPt,
          greaterThanOrEqualTo(WorldDotMap.minDotPt),
          reason: 'mapa ${w}pt',
        );
      }
    });

    test('dots never merge while the spacing is at least twice the floor', () {
      for (var w = 135.0; w <= 3000.0; w += 0.5) {
        final stride = WorldDotMap.strideFor(w);
        final spacingPx = w * dpr / WorldDotMap.gridColumns * stride;
        final gapPx = spacingPx - WorldDotMap.dotDiameterPx(w, dpr, stride);
        expect(
          gapPx,
          greaterThanOrEqualTo(floorPx - 1e-9),
          reason: 'mapa ${w}pt, stride $stride',
        );
      }
    });
  });
}
