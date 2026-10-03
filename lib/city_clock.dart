import 'package:flutter/foundation.dart' show immutable;
import 'package:timezone/timezone.dart' as tz;

import 'city.dart';

/// O relógio de uma cidade: a cidade e o fuso dela, já resolvido.
///
/// `tz.getLocation` é chamado UMA vez, na construção — não a cada quadro. O
/// `Location` é imutável e pode ser guardado.
///
/// O fuso vem do `timeZoneId` da cidade, que o catálogo entrega resolvido e
/// conferido na geração (ver `tool/build_cities.dart`): o id existe na tzdb
/// carregada, então [location] não pode lançar por dado ruim do asset.
@immutable
class CityClock {
  CityClock(this.city) : location = tz.getLocation(city.timeZoneId);

  final City city;

  /// O fuso da cidade na tzdb carregada.
  final tz.Location location;

  /// O instante [when] no relógio de parede desta cidade.
  ///
  /// `TZDateTime` É um `DateTime`: os getters (`hour`, `minute`, `day`) leem a
  /// hora de parede do fuso, e é isso que os formatadores consomem. O horário
  /// de verão sai daqui — da tzdb —, nunca de uma conta de longitude.
  tz.TZDateTime wallClock(DateTime when) => tz.TZDateTime.from(when, location);

  @override
  String toString() => 'CityClock(${city.name} @ ${city.timeZoneId})';
}

/// O que o overlay de uma cidade mostra, para um instante.
///
/// Existe para o widget ficar burro: toda a aritmética de fuso e a formatação
/// acontecem aqui, num lugar só, testável sem montar a tela.
@immutable
class ClockReading {
  const ClockReading({
    required this.time,
    required this.dayOffset,
    required this.offset,
  });

  /// A hora no relógio de parede da cidade: `14:05`.
  final String time;

  /// Se o dia lá é outro dia: `''`, `'+1 dia'`, `'-2 dias'`.
  ///
  /// É o detalhe que faz um relógio mundial valer a pena — "Tóquio, 02:05" sem
  /// o "+1 dia" ao lado parece simplesmente errado para quem está em São Paulo.
  final String dayOffset;

  /// O deslocamento do fuso NAQUELE instante: `UTC-03`, `UTC+05:30`, `UTC`.
  ///
  /// É sensível ao horário de verão POR CONSTRUÇÃO (o offset é lido do instante
  /// convertido), e por isso o overlay não precisa de um rótulo "BRT"/"BRST"
  /// que a tzdb às vezes devolve em forma numérica (`-03`) e às vezes não.
  final String offset;

  /// A leitura do relógio de [clock] no instante [now], comparando com o dia
  /// de [here] (o relógio do usuário) para o [dayOffset].
  factory ClockReading.at(
    CityClock clock,
    DateTime now, {
    required DateTime here,
  }) => ClockReading.forLocation(clock.location, now, here: here);

  /// A leitura de um fuso qualquer — não só o de uma cidade salva.
  ///
  /// É o que o ponto CLICADO usa: ele tem um `tz.Location` (do polígono, da
  /// faixa náutica) e mais nada, e a hora dele é a mesma conta.
  factory ClockReading.forLocation(
    tz.Location location,
    DateTime now, {
    required DateTime here,
  }) {
    final there = tz.TZDateTime.from(now, location);
    return ClockReading(
      time: formatHourMinute(there),
      dayOffset: formatDayOffset(there, here),
      offset: formatUtcOffset(there.timeZoneOffset),
    );
  }

  @override
  String toString() => '$time$offset${dayOffset.isEmpty ? '' : ' $dayOffset'}';
}

/// `14:05`.
String formatHourMinute(DateTime when) =>
    '${_two(when.hour)}:${_two(when.minute)}';

/// `14:05:09`.
String formatHourMinuteSecond(DateTime when) =>
    '${formatHourMinute(when)}:${_two(when.second)}';

/// `UTC-03`, `UTC+05:30`, `UTC`.
///
/// O zero é só `UTC` (sem `+00`): é como as pessoas escrevem, e o sinal de mais
/// no zero não informa nada.
String formatUtcOffset(Duration offset) {
  final totalMinutes = offset.inMinutes;
  if (totalMinutes == 0) {
    return 'UTC';
  }
  final sign = totalMinutes < 0 ? '-' : '+';
  final absolute = totalMinutes.abs();
  final hours = _two(absolute ~/ 60);
  final minutes = absolute % 60;
  return minutes == 0
      ? 'UTC$sign$hours'
      : 'UTC$sign$hours:${_two(minutes)}';
}

/// A diferença de DIA entre dois relógios de parede: `''`, `'+1 dia'`,
/// `'-2 dias'`.
///
/// Compara DIA DE CALENDÁRIO, não duração: 23:50 em São Paulo e 11:50 em Tóquio
/// do dia seguinte são 12 horas de diferença e um dia de calendário, e é o dia
/// que o usuário precisa ver. A conta passa por `DateTime.utc`, então não há
/// como o fuso do próprio aparelho se meter no meio.
String formatDayOffset(DateTime there, DateTime here) {
  final days = _dayNumber(there) - _dayNumber(here);
  if (days == 0) {
    return '';
  }
  final magnitude = days.abs();
  final plural = magnitude == 1 ? 'dia' : 'dias';
  return '${days > 0 ? '+' : '-'}$magnitude $plural';
}

/// Número de dias de calendário desde a época, ignorando o horário.
int _dayNumber(DateTime when) =>
    DateTime.utc(when.year, when.month, when.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

String _two(int value) => value.toString().padLeft(2, '0');
