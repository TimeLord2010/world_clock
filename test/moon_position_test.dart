import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/moon_position.dart';

/// Posição e fase da Lua: os valores de referência são da efeméride **DE441 do
/// JPL** (API Horizons, geocêntrica) — subponto tirado da longitude/latitude
/// eclíptica de data e da iluminação que o próprio JPL publica.
///
/// As tolerâncias são folgadas de propósito (a série truncada acerta o JPL em
/// 0,013° e 0,01%): 0,02° e 0,2% de folga dão espaço para arredondamento do
/// Dart, e ainda assim quebram se alguém trocar a teoria por uma mais grosseira
/// — a fórmula simplificada de fase errava 1,2%, dez vezes a tolerância.
void main() {
  group('MoonPosition.at contra a efeméride DE441 do JPL', () {
    final jpl = <(DateTime, double, double, double)>[
      (DateTime.utc(2026, 9, 1, 0), 13.8829, 41.7581, 0.8418),
      (DateTime.utc(2026, 9, 6, 0), 27.5850, 111.2634, 0.3125),
      (DateTime.utc(2026, 9, 11, 0), 3.9545, 176.9211, 0.0004),
      (DateTime.utc(2026, 9, 16, 0), -23.1355, -127.3320, 0.2397),
      (DateTime.utc(2026, 9, 21, 0), -24.9390, -66.2454, 0.6987),
      (DateTime.utc(2026, 9, 26, 0), -0.3102, -10.9948, 0.9939),
    ];

    test('subponto dentro de 0,02° e iluminação dentro de 0,2%', () {
      for (final (instant, lat, lon, illumination) in jpl) {
        final moon = MoonPosition.at(instant);
        expect(moon.subLatDeg, closeTo(lat, 0.02), reason: 'lat em $instant');
        expect(moon.subLonDeg, closeTo(lon, 0.02), reason: 'lon em $instant');
        expect(
          moon.illumination,
          closeTo(illumination, 0.002),
          reason: 'iluminação em $instant',
        );
      }
    });

    test('invariantes num mês inteiro de amostras (a cada 12 h)', () {
      // Amostra a cada 12 h: o pior erro da teoria não pode aparecer numa
      // amostra só — se aparecer, o desenho da Lua sai do lugar no mapa.
      var checked = 0;
      for (var hour = 0; hour < 24 * 30; hour += 12) {
        final moon = MoonPosition.at(
          DateTime.utc(2026, 9, 1).add(Duration(hours: hour)),
        );
        expect(moon.subLatDeg.abs(), lessThan(30), reason: 'declinação da Lua');
        expect(moon.subLonDeg, inInclusiveRange(-180, 180));
        expect(
          moon.distanceKm,
          inInclusiveRange(356000, 407000),
          reason: 'perigeu/apogeu em $hour h',
        );
        expect(moon.illumination, inInclusiveRange(0.0, 1.0));
        checked++;
      }
      expect(checked, 60);
    });
  });

  group('sizígias', () {
    final now = DateTime.utc(2026, 9, 27, 19);

    test('a próxima cheia é 2026-10-26 04:13 UTC (tol. 15 min)', () {
      // Referência: ELP (`ephem.next_full_moon`) = 04:11:45 UTC.
      final full = MoonPosition.at(now).nextFullMoon;
      expect(
        full.difference(DateTime.utc(2026, 10, 26, 4, 13)).inMinutes.abs(),
        lessThan(15),
        reason: 'cheia em $full',
      );
    });

    test('a próxima nova é 2026-10-10 15:53 UTC (tol. 15 min)', () {
      // Referência: `ephem.next_new_moon` = 15:50:01 UTC.
      final newMoon = MoonPosition.at(now).nextNewMoon;
      expect(
        newMoon.difference(DateTime.utc(2026, 10, 10, 15, 53)).inMinutes.abs(),
        lessThan(15),
        reason: 'nova em $newMoon',
      );
    });

    test('a idade sinódica fecha com o mês sinódico', () {
      // idade (desde a última nova) + o que falta até a próxima nova = um mês
      // sinódico. Trava a busca para trás sem precisar de outra referência.
      final moon = MoonPosition.at(now);
      final untilNextNew =
          moon.nextNewMoon.difference(now).inMinutes / (60 * 24);
      expect(moon.ageDays + untilNextNew, closeTo(29.53, 0.05));
      expect(moon.lastNewMoon.isBefore(now), isTrue);
    });

    test('logo depois da cheia a elongação passa de 180°', () {
      // A cheia de setembro de 2026 foi em 26/09 ~20:00 UTC: às 19:00 do dia
      // 27 a elongação já passou de 180° e a Lua minguou de 99,9% para 98,7%.
      final moon = MoonPosition.at(now);
      expect(moon.elongationDeg, inInclusiveRange(181, 205));
      expect(moon.illumination, inInclusiveRange(0.98, 0.99));
      expect(moon.phase, MoonPhase.fullMoon);
    });
  });

  group('metade iluminada (50%)', () {
    // Referências: JPL Horizons (`QUANTITIES='1,10'` = Illu%, passos de 1 min,
    // cruzamento interpolado) — NÃO o "quarto" dos almanaques, que é a elongação
    // em 90°/270° e cai ~20 min depois do 50% exato (o Sol não está no infinito:
    // no meio vale `cos elong = R/dist` → 89,85°).
    final crosses = <(String, DateTime, DateTime, bool, MoonPhase)>[
      // rótulo, instante de partida, referência do JPL, crescente?, fase
      (
        'minguante',
        DateTime.utc(2026, 9, 27, 19),
        DateTime.utc(2026, 10, 3, 13, 40, 35),
        false,
        MoonPhase.lastQuarter,
      ),
      (
        'crescente',
        DateTime.utc(2026, 10, 4),
        DateTime.utc(2026, 10, 18, 15, 52, 12),
        true,
        MoonPhase.firstQuarter,
      ),
    ];

    test('as duas passagens batem com o JPL (tol. 15 min)', () {
      for (final (label, from, reference, waxing, phase) in crosses) {
        final half = MoonPosition.at(from).nextHalfMoon;
        expect(half.waxing, waxing, reason: 'lado da passagem $label');
        expect(
          half.when.difference(reference).inMinutes.abs(),
          lessThan(15),
          reason: '50% $label em ${half.when}',
        );
        // A fase no instante da passagem é o quarto correspondente.
        expect(MoonPosition.at(half.when).phase, phase, reason: label);
      }
    });

    test('no instante devolvido a iluminação é 50%', () {
      // A busca é pela iluminação de verdade, então o ponto de chegada tem de
      // dar 1/2 — é o que separa esta busca da elongação em 90°.
      for (final (label, from, _, _, _) in crosses) {
        final half = MoonPosition.at(from).nextHalfMoon;
        expect(
          MoonPosition.at(half.when).illumination,
          closeTo(0.5, 1e-6),
          reason: label,
        );
      }
    });

    test('a passagem vem sempre depois do instante de partida', () {
      for (final hour in [0, 3, 6, 9, 12, 15, 18, 21]) {
        final from = DateTime.utc(2026, 10, 1).add(Duration(hours: hour));
        final half = MoonPosition.at(from).nextHalfMoon;
        expect(half.when.isAfter(from), isTrue, reason: 'partindo de $from');
        // E nunca longe demais: as passagens ficam a ~14,8 dias uma da outra.
        expect(half.when.difference(from).inDays, lessThan(15));
      }
    });

    test('no meio do mês sinódico a próxima passagem é a do outro lado', () {
      // 27/09 → 50% minguante (03/10); 04/10 → 50% crescente (18/10). O lado
      // não é "sempre minguante": é o lado da próxima passagem, seja qual for.
      expect(MoonPosition.at(crosses[0].$2).nextHalfMoon.waxing, isFalse);
      expect(MoonPosition.at(crosses[1].$2).nextHalfMoon.waxing, isTrue);
    });
  });

  group('fase', () {
    test('os oito setores de 45° com os nomes em português', () {
      const cases = <(double, MoonPhase)>[
        (0, MoonPhase.newMoon),
        (20, MoonPhase.newMoon),
        (45, MoonPhase.waxingCrescent),
        (90, MoonPhase.firstQuarter),
        (135, MoonPhase.waxingGibbous),
        (180, MoonPhase.fullMoon),
        (225, MoonPhase.waningGibbous),
        (270, MoonPhase.lastQuarter),
        (315, MoonPhase.waningCrescent),
        (359, MoonPhase.newMoon),
      ];
      for (final (elongation, expected) in cases) {
        // A fase sai da elongação; a iluminação correspondente é a do ângulo de
        // fase, então dá para testar o rótulo por instantes reais.
        expect(
          MoonPosition.phaseForElongation(elongation),
          expected,
          reason: 'elongação $elongation°',
        );
      }
    });

    test('lua nova quase não ilumina e cheia ilumina tudo', () {
      final newMoon = MoonPosition.at(DateTime.utc(2026, 9, 11, 0));
      expect(newMoon.illumination, lessThan(0.01));
      expect(newMoon.phase, MoonPhase.newMoon);
      // A nova de 11/09/2026 é às ~03:30 UTC: à meia-noite a idade ainda é a
      // do fim do ciclo anterior — a idade vai de 0 a 29,5 e volta.
      expect(newMoon.ageDays, inInclusiveRange(28.5, 29.6));

      final fullMoon = MoonPosition.at(DateTime.utc(2026, 9, 26, 12));
      expect(fullMoon.illumination, greaterThan(0.99));
      expect(fullMoon.phase, MoonPhase.fullMoon);
    });

    test('no equinócio o Sol está a pino perto de (0, 0)', () {
      // Sanidade do GMST e da longitude do Sol: em 20/03/2026 (~equinócio) às
      // 12:00 UTC o subponto do Sol cai perto do ponto (0, 0) — a folga de 4°
      // de longitude cobre a equação do tempo (até 16 min = 4°).
      final moon = MoonPosition.at(DateTime.utc(2026, 3, 20, 12));
      expect(moon.sunSubLonDeg, closeTo(0, 4.0));
      expect(moon.sunSubLatDeg, closeTo(0, 0.5));
    });
  });
}
