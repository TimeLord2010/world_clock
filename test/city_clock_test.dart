import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:world_clock/city.dart';
import 'package:world_clock/city_catalog.dart';
import 'package:world_clock/city_clock.dart';

/// O relógio de uma cidade: a hora de parede no fuso certo, o horário de verão
/// vindo da tzdb e a diferença de dia em relação a quem olha.
///
/// As cidades dos testes são as do CATÁLOGO de verdade (nada de `City`
/// inventada): se o gerador do catálogo trocar o fuso de Fortaleza ou de
/// Sydney, é aqui que quebra.
void main() {
  // O binding é o que dá acesso ao asset bundle: sem ele, `CityCatalog.load()`
  // não consegue ler `assets/cities.json`.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tzdata.initializeTimeZones);

  /// A cidade do catálogo, pelo nome — e por região quando há homônimas
  /// (existem duas "Sydney").
  Future<City> cityNamed(String name, {String? region}) async {
    final cities = await CityCatalog.load();
    return cities.firstWhere(
      (city) => city.name == name && (region == null || city.region == region),
    );
  }

  Future<CityClock> clockNamed(String name, {String? region}) async =>
      CityClock(await cityNamed(name, region: region));

  group('hora de parede', () {
    test(
      'Fortaleza às 12:00 UTC são 09:00 (UTC-03, sem horário de verão)',
      () async {
        final fortaleza = await clockNamed('Fortaleza', region: 'Ceará');
        final reading = ClockReading.at(
          fortaleza,
          DateTime.utc(2026, 1, 15, 12),
          here: DateTime.utc(2026, 1, 15, 12),
        );

        expect(fortaleza.wallClock(DateTime.utc(2026, 1, 15, 12)).hour, 9);
        expect(reading.time, '09:00');
        expect(reading.offset, 'UTC-03');
        expect(reading.dayOffset, '');
      },
    );

    test('Tóquio às 12:00 UTC são 21:00 (UTC+09)', () async {
      final tokyo = await clockNamed('Tóquio');
      final reading = ClockReading.at(
        tokyo,
        DateTime.utc(2026, 1, 15, 12),
        here: DateTime.utc(2026, 1, 15, 12),
      );

      expect(reading.time, '21:00');
      expect(reading.offset, 'UTC+09');
    });

    test('o horário de verão vem da tzdb, não da longitude', () async {
      // Sydney: +11 em janeiro (verão no hemisfério sul) e +10 em julho. Uma
      // conta de longitude daria o mesmo número nos dois meses.
      final sydney = await clockNamed('Sydney', region: 'New South Wales');

      final summer = ClockReading.at(
        sydney,
        DateTime.utc(2026, 1, 15, 12),
        here: DateTime.utc(2026, 1, 15, 12),
      );
      final winter = ClockReading.at(
        sydney,
        DateTime.utc(2026, 7, 15, 12),
        here: DateTime.utc(2026, 7, 15, 12),
      );

      expect(summer.time, '23:00');
      expect(summer.offset, 'UTC+11');
      expect(winter.time, '22:00');
      expect(winter.offset, 'UTC+10');
    });

    test('fusos de 45 e de 30 minutos não viram hora cheia', () async {
      // Chatham (Waitangi): +13:45 em janeiro. Catmandu: +05:45. St. John's:
      // -03:30 e -02:30. Arredondar qualquer um deles para a hora cheia seria
      // errado por 15 a 45 minutos.
      final chatham = await clockNamed('Waitangi');
      final katmandu = await clockNamed('Catmandu');
      final stJohns = await clockNamed("St. John's");
      final noon = DateTime.utc(2026, 1, 15, 12);
      final july = DateTime.utc(2026, 7, 15, 12);

      expect(ClockReading.at(chatham, noon, here: noon).offset, 'UTC+13:45');
      expect(ClockReading.at(chatham, noon, here: noon).time, '01:45');
      expect(ClockReading.at(katmandu, noon, here: noon).offset, 'UTC+05:45');
      expect(ClockReading.at(katmandu, noon, here: noon).time, '17:45');
      expect(ClockReading.at(stJohns, noon, here: noon).offset, 'UTC-03:30');
      expect(ClockReading.at(stJohns, july, here: july).offset, 'UTC-02:30');
    });
  });

  group('deslocamento do fuso', () {
    test('zero é só "UTC", sem sinal', () {
      expect(formatUtcOffset(Duration.zero), 'UTC');
    });

    test('hora cheia com dois dígitos e sinal', () {
      expect(formatUtcOffset(const Duration(hours: -3)), 'UTC-03');
      expect(formatUtcOffset(const Duration(hours: 9)), 'UTC+09');
      expect(formatUtcOffset(const Duration(hours: 13)), 'UTC+13');
      expect(formatUtcOffset(const Duration(hours: -11)), 'UTC-11');
    });

    test('meia hora e um quarto de hora aparecem', () {
      expect(
        formatUtcOffset(const Duration(hours: 5, minutes: 30)),
        'UTC+05:30',
      );
      expect(
        formatUtcOffset(const Duration(hours: -9, minutes: -30)),
        'UTC-09:30',
      );
      expect(
        formatUtcOffset(const Duration(hours: 13, minutes: 45)),
        'UTC+13:45',
      );
    });
  });

  group('diferença de dia', () {
    test('mesmo dia não escreve nada', () {
      expect(
        formatDayOffset(DateTime(2026, 10, 3, 9), DateTime(2026, 10, 3, 23)),
        '',
      );
    });

    test('dia seguinte e dia anterior, com plural certo', () {
      final here = DateTime(2026, 10, 3, 23);

      expect(formatDayOffset(DateTime(2026, 10, 4, 11), here), '+1 dia');
      expect(formatDayOffset(DateTime(2026, 10, 5, 11), here), '+2 dias');
      expect(formatDayOffset(DateTime(2026, 10, 2, 11), here), '-1 dia');
      expect(formatDayOffset(DateTime(2026, 10, 1, 11), here), '-2 dias');
    });

    test('conta DIA de calendário, não duração', () {
      // Vinte minutos de diferença e um dia de calendário: é o dia que
      // interessa a quem lê um relógio mundial.
      expect(
        formatDayOffset(
          DateTime(2026, 10, 4, 0, 10),
          DateTime(2026, 10, 3, 23, 50),
        ),
        '+1 dia',
      );
    });

    test('atravessa a virada de mês e de ano', () {
      expect(
        formatDayOffset(DateTime(2027, 1, 1, 2), DateTime(2026, 12, 31, 23)),
        '+1 dia',
      );
      expect(
        formatDayOffset(DateTime(2026, 3, 1, 2), DateTime(2026, 2, 28, 23)),
        '+1 dia',
      );
    });
  });

  group('leitura do relógio', () {
    test('o "aqui" é o que define o +1 dia', () async {
      final tokyo = await clockNamed('Tóquio');

      // 23:00 UTC: em Tóquio já é 08:00 do dia seguinte.
      final now = DateTime.utc(2026, 10, 3, 23);
      final fromSaoPaulo = ClockReading.at(
        tokyo,
        now,
        here: DateTime(2026, 10, 3, 20),
      );
      final fromTokyo = ClockReading.at(
        tokyo,
        now,
        here: DateTime(2026, 10, 4, 8),
      );

      expect(fromSaoPaulo.time, '08:00');
      expect(fromSaoPaulo.dayOffset, '+1 dia');
      expect(fromTokyo.dayOffset, '');
    });

    test('segundos só quando pedidos', () {
      final when = DateTime.utc(2026, 10, 3, 12, 5, 9);

      expect(formatHourMinute(when), '12:05');
      expect(formatHourMinuteSecond(when), '12:05:09');
    });
  });
}
