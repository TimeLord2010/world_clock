import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:world_clock/nautical_zone.dart';

/// O fuso de mar aberto: a faixa de 15° em volta da longitude — e o sinal
/// invertido que a convenção POSIX das zonas `Etc/GMT` impõe.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  /// O deslocamento real da zona, pela tzdb (não pelo nome).
  Duration offsetOf(String zoneId) =>
      tz.TZDateTime(tz.getLocation(zoneId), 2026, 1, 15, 12).timeZoneOffset;

  group('faixa náutica', () {
    test('cada faixa existe na tzdb com o deslocamento certo', () {
      // O sinal: `Etc/GMT+2` é UTC−2. Trocar isso deixaria o relógio errado em
      // DUAS VEZES o deslocamento — e o resultado pareceria plausível.
      //
      // Só as faixas cujo centro cai dentro de [-180, 180): as de ±12 têm o
      // centro exatamente no antimeridiano, e esse caso tem teste próprio.
      for (var band = -11; band <= 11; band++) {
        final longitude = band * 15.0;
        final id = nauticalZoneId(longitude);

        expect(
          offsetOf(id),
          Duration(hours: band),
          reason:
              'lon $longitude devia ser UTC${band >= 0 ? '+' : ''}$band '
              '(id $id)',
        );
      }
    });

    test('Greenwich é a faixa sem número', () {
      expect(nauticalZoneId(0), 'Etc/GMT');
      expect(offsetOf('Etc/GMT'), Duration.zero);
    });

    test('os extremos são as faixas de 12 horas', () {
      expect(nauticalZoneId(-179), 'Etc/GMT+12');
      expect(offsetOf(nauticalZoneId(-179)), const Duration(hours: -12));
      expect(nauticalZoneId(179), 'Etc/GMT-12');
      expect(offsetOf(nauticalZoneId(179)), const Duration(hours: 12));
    });

    test('o antimeridiano exato cai na faixa de −12 (e é documentado)', () {
      // A longitude é normalizada para [-180, 180), então 180 vira −180. A
      // faixa náutica é descontínua de 24 h exatamente NA linha: é inerente ao
      // esquema, e não há terra ali para o caso de mar aberto.
      expect(nauticalZoneId(180), 'Etc/GMT+12');
      expect(nauticalZoneId(-180), 'Etc/GMT+12');
      expect(offsetOf(nauticalZoneId(179.9)), const Duration(hours: 12));
    });

    test('a virada de faixa acontece a 7,5° de distância', () {
      expect(nauticalZoneId(7.4), 'Etc/GMT');
      expect(nauticalZoneId(7.6), 'Etc/GMT-1');
      expect(nauticalZoneId(-7.4), 'Etc/GMT');
      expect(nauticalZoneId(-7.6), 'Etc/GMT+1');
    });

    test('longitude fora do intervalo é normalizada', () {
      // Um clique preso à borda do mapa pode chegar aqui como 180,0 e não pode
      // produzir um id inexistente (que faria tz.getLocation lançar).
      expect(nauticalZoneId(190), nauticalZoneId(-170));
      expect(nauticalZoneId(370), nauticalZoneId(10));
      expect(nauticalZoneId(-190), nauticalZoneId(170));
      for (final lon in [-540.0, -180.0, 0.0, 180.0, 540.0]) {
        expect(() => tz.getLocation(nauticalZoneId(lon)), returnsNormally);
      }
    });
  });
}
