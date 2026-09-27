/// Posição da Lua na superfície da Terra — o subponto lunar — e a sua fase.
///
/// Mesma família de `world_sun.dart`: uma aproximação analítica de baixa
/// precisão, sem arquivo de efeméride e sem dependência nova. A Lua sai de uma
/// série de Meeus (*Astronomical Algorithms*, cap. 47) truncada nos termos
/// maiores (34 em longitude, 12 em latitude, 18 em distância), e o Sol do
/// cap. 25 entra porque a **fase certa** é geometria, não fórmula: a fração
/// iluminada é o ângulo Sol–Lua–Terra, e a fórmula simplificada do cap. 48
/// errava até 1,2% na borda do crescente.
///
/// Precisão medida contra a efeméride **DE441 do JPL** (API Horizons), 61
/// amostras cobrindo um mês: subponto dentro de **0,013° (≈1 km** na
/// superfície) e iluminação dentro de **0,01%**; as sizígias (cheia e nova)
/// ficam dentro de **3 min** do ELP. `test/moon_position_test.dart` trava esses
/// números — se alguém trocar a teoria por uma mais grosseira, o teste cai.
///
/// Nota de referencial (foi bug de verdade na investigação): as coordenadas
/// saem **eclípticas de data** e são convertidas para equatoriais **de data**
/// antes de subtrair o GMST. Misturar uma RA em J2000 com o GMST erra o
/// subponto em 0,37° (≈40 km) em 2026 — a precessão desde 2000.
///
/// A latitude do subponto é **geocêntrica** (igual à declinação). A geodésica
/// difere até 0,19° por causa do achatamento da Terra — um quinto de ponto no
/// grid de 1° do mapa, e o que a validação contra o JPL mede é esta aqui.
library;

import 'dart:math';

/// Fase da Lua pela elongação geocêntrica Sol–Lua: 0° é lua nova, 180° é cheia.
enum MoonPhase {
  newMoon('Nova'),
  waxingCrescent('Crescente côncava'),
  firstQuarter('Quarto crescente'),
  waxingGibbous('Crescente gibosa'),
  fullMoon('Cheia'),
  waningGibbous('Minguante gibosa'),
  lastQuarter('Quarto minguante'),
  waningCrescent('Minguante côncava');

  const MoonPhase(this.label);

  /// Nome mostrado na interface.
  final String label;
}

/// Onde a Lua está e como ela está, num instante.
class MoonStatus {
  const MoonStatus({
    required this.subLatDeg,
    required this.subLonDeg,
    required this.illumination,
    required this.elongationDeg,
    required this.distanceKm,
    required this.ageDays,
    required this.phase,
    required this.sunSubLatDeg,
    required this.sunSubLonDeg,
    required this.nextFullMoon,
    required this.nextNewMoon,
    required this.lastNewMoon,
    required this.nextHalfMoons,
  });

  /// Latitude do ponto onde a Lua está a pino, em graus (+N).
  final double subLatDeg;

  /// Longitude do mesmo ponto, em graus (−180..180, +E).
  final double subLonDeg;

  /// Fração iluminada do disco, 0..1.
  final double illumination;

  /// Elongação geocêntrica Sol–Lua em graus: 0 = nova, 180 = cheia, e o valor
  /// **cresce** de 0 a 360 ao longo do mês sinódico (lua crescente é 0..180).
  final double elongationDeg;

  /// Distância entre os centros da Terra e da Lua, em km.
  final double distanceKm;

  /// Dias desde a última lua nova.
  final double ageDays;

  /// Fase corrente.
  final MoonPhase phase;

  /// Latitude do subponto do Sol (graus, +N).
  ///
  /// Existe para o marcador do mapa: a parte iluminada do disco aponta para
  /// onde o Sol está no mapa naquele instante.
  final double sunSubLatDeg;

  /// Longitude do subponto do Sol (graus, −180..180).
  final double sunSubLonDeg;

  /// Próximas sizígias (UTC).
  final DateTime nextFullMoon;
  final DateTime nextNewMoon;

  /// Última lua nova (UTC) — a idade sinódica conta a partir dela.
  final DateTime lastNewMoon;

  /// As DUAS próximas passagens por **50% de iluminação** (UTC), em ordem
  /// cronológica, cada uma com o lado por onde a Lua passa: `waxing` =
  /// crescente (quarto crescente); senão minguante.
  ///
  /// São duas por mês sinódico — uma entre a nova e a cheia, outra entre a
  /// cheia e a nova —, sempre a ~14,8 dias uma da outra; o painel mostra as
  /// duas para não sobrar um vão de duas semanas entre a nova e a cheia.
  final List<({DateTime when, bool waxing})> nextHalfMoons;

  /// Fração iluminada como porcentagem, para a interface.
  double get illuminationPercent => illumination * 100;

  /// Lua crescendo (nova → cheia) ou minguando (cheia → nova)?
  bool get waxing => elongationDeg < 180;
}

/// Cálculo da posição da Lua: uma função pura do instante.
abstract final class MoonPosition {
  static const double _deg = pi / 180;
  static const double _auKm = 149597870.7;

  /// Subponto lunar, fase e sizígias para o instante [when].
  static MoonStatus at(DateTime when) {
    final utc = when.toUtc();
    final t = _centuries(utc);
    final obliquity = _obliquity(t);

    final moon = _moonEcliptic(t);
    final sun = _sunEcliptic(t);

    final (ra, dec) = _toEquatorial(moon, obliquity);
    final gmst = _gmstDeg(utc);

    // Subponto do Sol: só a direção interessa (é a direção da luz no mapa).
    final sunDec = asin(sin(obliquity) * sin(sun.lonRad)) / _deg;
    final sunLon = _wrapLon(sun.lonRad / _deg - gmst);

    final (illumination, elongation) = _phase(moon, sun);

    final nextFull = _crossing(180, utc, forward: true);
    final nextNew = _crossing(0, utc, forward: true);
    final lastNew = _crossing(0, utc, forward: false);
    // A SEGUNDA passagem de 50% sai da busca reiniciada um minuto depois da
    // primeira: no instante exato do cruzamento o desvio é ~0 e a busca precisa
    // de um ponto já do outro lado para achar a troca de sinal seguinte.
    final firstHalf = _halfMoon(utc);
    final secondHalf = _halfMoon(
      firstHalf.when.add(const Duration(minutes: 1)),
    );

    return MoonStatus(
      subLatDeg: dec / _deg,
      subLonDeg: _wrapLon(ra / _deg - gmst),
      illumination: illumination,
      elongationDeg: elongation,
      distanceKm: moon.distKm,
      ageDays: utc.difference(lastNew).inMilliseconds / 86400000,
      phase: phaseForElongation(elongation),
      sunSubLatDeg: sunDec,
      sunSubLonDeg: sunLon,
      nextFullMoon: nextFull,
      nextNewMoon: nextNew,
      lastNewMoon: lastNew,
      nextHalfMoons: [firstHalf, secondHalf],
    );
  }

  /// Nome da fase pela elongação: oito setores de 45°, centrados nas quatro
  /// fases principais (nova em 0°, cheia em 180°).
  static MoonPhase phaseForElongation(double elongationDeg) {
    final sector = ((elongationDeg / 45) + 0.5).floor() % 8;
    return MoonPhase.values[sector];
  }

  // ---------------------------------------------------------------- a Lua

  /// Série de Meeus cap. 47 truncada: (D, M, M', F, coeficiente) em 1e-6 grau
  /// (os de longitude e latitude) ou 1e-3 km (os de distância). O corte foi
  /// escolhido pelo tamanho do termo — o resto da tabela 47.A soma menos de
  /// 0,001° no intervalo validado.
  static const List<(int, int, int, int, int)> _lonTerms = [
    (0, 0, 1, 0, 6288774),
    (2, 0, -1, 0, 1274027),
    (2, 0, 0, 0, 658314),
    (0, 0, 2, 0, 213618),
    (0, 1, 0, 0, -185116),
    (0, 0, 0, 2, -114332),
    (2, 0, -2, 0, 58793),
    (2, -1, -1, 0, 57066),
    (2, 0, 1, 0, 53322),
    (2, -1, 0, 0, 45758),
    (0, 1, -1, 0, -40923),
    (1, 0, 0, 0, -34720),
    (0, 1, 1, 0, -30383),
    (2, 0, 0, -2, 15327),
    (0, 0, 1, 2, -12528),
    (0, 0, 1, -2, 10980),
    (4, 0, -1, 0, 10675),
    (0, 0, 3, 0, 10034),
    (4, 0, -2, 0, 8548),
    (2, 1, -1, 0, -7888),
    (2, 1, 0, 0, -6766),
    (1, 0, -1, 0, -5163),
    (1, 1, 0, 0, 4987),
    (2, -1, 1, 0, 4036),
    (2, 0, 2, 0, 3994),
    (4, 0, 0, 0, 3861),
    (2, 0, -3, 0, 3665),
    (0, 1, -2, 0, -2689),
    (2, 0, -1, 2, -2602),
    (2, -1, -2, 0, 2390),
    (1, 0, 1, 0, -2348),
    (2, -2, 0, 0, 2236),
    (0, 1, 2, 0, -2120),
    (0, 2, 0, 0, -2069),
  ];

  static const List<(int, int, int, int, int)> _latTerms = [
    (0, 0, 0, 1, 5128122),
    (0, 0, 1, 1, 280602),
    (0, 0, 1, -1, 277693),
    (2, 0, 0, -1, 173237),
    (2, 0, -1, 1, 55413),
    (2, 0, -1, -1, 46271),
    (2, 0, 0, 1, 32573),
    (0, 0, 2, 1, 17198),
    (2, 0, 1, -1, 9266),
    (0, 0, 2, -1, 8822),
    (2, -1, 0, -1, 8216),
    (2, 0, -2, -1, 4324),
  ];

  static const List<(int, int, int, int, int)> _distTerms = [
    (0, 0, 1, 0, -20905355),
    (2, 0, -1, 0, -3699111),
    (2, 0, 0, 0, -2955968),
    (0, 0, 2, 0, -569925),
    (0, 1, 0, 0, 48888),
    (0, 0, 0, 2, -3149),
    (2, 0, -2, 0, 246158),
    (2, -1, -1, 0, -152138),
    (2, 0, 1, 0, -170733),
    (2, -1, 0, 0, -204586),
    (0, 1, -1, 0, -129620),
    (1, 0, 0, 0, 108743),
    (0, 1, 1, 0, 104755),
    (2, 0, 0, -2, 10321),
    (4, 0, -1, 0, 79661),
    (0, 0, 3, 0, -34782),
    (4, 0, -2, 0, -23210),
    (2, 1, -1, 0, -21636),
  ];

  /// Posição geocêntrica da Lua em coordenadas eclípticas de data.
  static _Ecliptic _moonEcliptic(double t) {
    final lp = _meanLongitude(t);
    final d = _meanElongation(t);
    final m = _meanAnomalySun(t);
    final mp = _meanAnomalyMoon(t);
    final f = _argumentOfLatitude(t);
    final e = 1 - 0.002516 * t - 0.0000074 * t * t;
    final a1 = 119.75 + 131.849 * t;
    final a2 = 53.09 + 479264.290 * t;

    double series(
      List<(int, int, int, int, int)> terms, {
      required bool cosine,
    }) {
      var total = 0.0;
      for (final (cd, cm, cmp, cf, coef) in terms) {
        final angle = (cd * d + cm * m + cmp * mp + cf * f) * _deg;
        final eccentricityFactor = switch (cm.abs()) {
          2 => e * e,
          1 => e,
          _ => 1.0,
        };
        total += coef * eccentricityFactor * (cosine ? cos(angle) : sin(angle));
      }
      return total;
    }

    // As três somas aditivas da longitude (Vênus, Júpiter e o termo de A2).
    final lonSum =
        series(_lonTerms, cosine: false) +
        3958 * sin(a1 * _deg) +
        1962 * sin((lp - f) * _deg) +
        318 * sin(a2 * _deg);
    final latSum = series(_latTerms, cosine: false);
    final distSum = series(_distTerms, cosine: true);

    return _Ecliptic(
      lonRad: ((lp % 360) + lonSum / 1e6) * _deg,
      latRad: latSum / 1e6 * _deg,
      distKm: 385000.56 + distSum / 1000,
    );
  }

  // ---------------------------------------------------------------- o Sol

  /// Posição geocêntrica do Sol (Meeus cap. 25, precisão ~0,01°).
  static ({double lonRad, double distKm}) _sunEcliptic(double t) {
    final l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
    final m = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) * _deg;
    final e = 0.016708634 - 0.000042037 * t - 0.0000001267 * t * t;
    final c =
        (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m) +
        (0.019993 - 0.000101 * t) * sin(2 * m) +
        0.000289 * sin(3 * m);
    final trueLon = (l0 + c) % 360;
    final nu = m + c * _deg;
    final distAu = 1.000001018 * (1 - e * e) / (1 + e * cos(nu));
    return (lonRad: trueLon * _deg, distKm: distAu * _auKm);
  }

  // ------------------------------------------------------- fase (geometria)

  /// Fração iluminada e elongação, pelo ângulo Sol–Lua–Terra.
  ///
  /// Vetores em km nas MESMAS coordenadas eclípticas: a Lua geocêntrica e o Sol
  /// geocêntrico. O cosseno do ângulo de fase sai do produto interno entre o
  /// vetor Sol→Lua e o vetor Lua→Terra.
  static (double illumination, double elongationDeg) _phase(
    _Ecliptic moon,
    ({double lonRad, double distKm}) sun,
  ) {
    final mx = moon.distKm * cos(moon.latRad) * cos(moon.lonRad);
    final my = moon.distKm * cos(moon.latRad) * sin(moon.lonRad);
    final mz = moon.distKm * sin(moon.latRad);
    final sx = sun.distKm * cos(sun.lonRad);
    final sy = sun.distKm * sin(sun.lonRad);

    final ux = mx - sx;
    final uy = my - sy;
    final uz = mz;
    final sunMoonKm = sqrt(ux * ux + uy * uy + uz * uz);
    final cosPhase = ((ux * mx + uy * my + uz * mz) / (sunMoonKm * moon.distKm))
        .clamp(-1.0, 1.0);

    final cosElongation = ((mx * sx + my * sy) / (moon.distKm * sun.distKm))
        .clamp(-1.0, 1.0);
    final elongation = acos(cosElongation) / _deg;
    // acos devolve 0..180: o sinal do seno da diferença diz se é crescente ou
    // minguante, fechando a volta de 0 a 360.
    final signed = sin(moon.lonRad - sun.lonRad) >= 0
        ? elongation
        : 360 - elongation;

    return ((1 + cosPhase) / 2, signed);
  }

  // ----------------------------------------------------------- sizígias

  /// Elongação (0..360) no instante [utc] — uma avaliação completa do par
  /// Lua+Sol, usada pela busca das sizígias.
  static double _elongationDeg(DateTime utc) {
    final t = _centuries(utc);
    return _phase(_moonEcliptic(t), _sunEcliptic(t)).$2;
  }

  /// Fração iluminada no instante [utc] — a mesma avaliação completa, usada
  /// pela busca dos 50%.
  static double _illuminationAt(DateTime utc) {
    final t = _centuries(utc);
    return _phase(_moonEcliptic(t), _sunEcliptic(t)).$1;
  }

  /// Instante em que a elongação cruza [targetDeg], indo para frente
  /// ([forward]) ou para trás no tempo.
  ///
  /// Varredura grossa de 6 h (a elongação anda ~12,19°/dia, então nenhum
  /// cruzamento é pulado) até achar a troca de sinal, e depois bisseção em
  /// [_bisect] — 30 passos deixam o instante bem abaixo de 1 s.
  static DateTime _crossing(
    double targetDeg,
    DateTime from, {
    required bool forward,
  }) {
    final step = Duration(hours: forward ? 6 : -6);

    double deviation(DateTime t) {
      final d = _elongationDeg(t) - targetDeg;
      return (d + 180) % 360 - 180;
    }

    var a = from;
    var fa = deviation(a);
    for (var i = 0; i < 200; i++) {
      final b = a.add(step);
      final fb = deviation(b);
      final crossed = forward ? (fa <= 0 && fb > 0) : (fa > 0 && fb <= 0);
      if (crossed) {
        return _bisect(a, fa, b, deviation);
      }
      a = b;
      fa = fb;
    }
    // Inalcançável para as sizígias (o mês sinódico cabe em 30 dias); devolve o
    // fim da varredura em vez de lançar — o desenho não depende disto.
    return a;
  }

  /// Próximo cruzamento de **50% de iluminação** depois de [from], com o lado
  /// por onde a Lua passa: `waxing` = foi de menos de 50% para mais.
  ///
  /// A condição é a iluminação de verdade, **não** a elongação em 90°: o
  /// "quarto" dos almanaques é a elongação reta e cai ~20 min DEPOIS do 50%
  /// real (no instante do meio vale `cos elong = R/dist` → 89,85°, porque o Sol
  /// não está no infinito). O painel mostra a iluminação, então é ela que a
  /// busca usa. Duas passagens por mês sinódico, sempre a ~14,8 dias uma da
  /// outra — nenhuma é pulada pela varredura de 6 h.
  static ({DateTime when, bool waxing}) _halfMoon(DateTime from) {
    double deviation(DateTime t) => _illuminationAt(t) - 0.5;

    var a = from;
    var fa = deviation(a);
    for (var i = 0; i < 200; i++) {
      final b = a.add(const Duration(hours: 6));
      final fb = deviation(b);
      if (fa <= 0 && fb > 0) {
        return (when: _bisect(a, fa, b, deviation), waxing: true);
      }
      if (fa > 0 && fb <= 0) {
        return (when: _bisect(a, fa, b, deviation), waxing: false);
      }
      a = b;
      fa = fb;
    }
    // Inalcançável: as duas passagens de 50% ficam a ~14,8 dias de distância.
    // Devolve o fim da varredura em vez de lançar, como as sizígias.
    return (when: a, waxing: true);
  }

  /// Bisseção entre [lo] (desvio [flo]) e [hi], cujo desvio tem o outro sinal:
  /// 30 passos deixam o instante bem abaixo de 1 s.
  static DateTime _bisect(
    DateTime lo,
    double flo,
    DateTime hi,
    double Function(DateTime) deviation,
  ) {
    for (var k = 0; k < 30; k++) {
      final mid = lo.add(
        Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2),
      );
      final fm = deviation(mid);
      if ((flo <= 0) == (fm <= 0)) {
        lo = mid;
        flo = fm;
      } else {
        hi = mid;
      }
    }
    return lo.add(
      Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2),
    );
  }

  // ------------------------------------------------------- tempo e esferas

  /// Séculos julianos desde J2000 **em tempo terrestre** (TT ≈ UTC + 69 s em
  /// 2026). Os 69 s mexem a Lua em ~0,01° — entram para a conta fechar com o
  /// JPL, e não por preciosismo.
  static double _centuries(DateTime utc) =>
      (_julianDay(utc) + 69.0 / 86400 - 2451545.0) / 36525;

  /// Dia juliano do instante UTC (Meeus cap. 7).
  static double _julianDay(DateTime utc) {
    var year = utc.year;
    var month = utc.month;
    final day =
        utc.day +
        (utc.hour + utc.minute / 60 + utc.second / 3600) / 24 +
        utc.millisecond / 86400000;
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = year ~/ 100;
    final b = 2 - a + a ~/ 4;
    return (365.25 * (year + 4716)).floorToDouble() +
        (30.6001 * (month + 1)).floorToDouble() +
        day +
        b -
        1524.5;
  }

  /// Obliquidade da eclíptica (_obliquity) em radianos, na era [t].
  static double _obliquity(double t) =>
      (23.4392911 - 0.0130042 * t - 1.64e-7 * t * t + 5.04e-7 * t * t * t) *
      _deg;

  /// Eclíptico de data → equatorial de data (a rotação pela obliquidade).
  static (double raRad, double decRad) _toEquatorial(
    _Ecliptic moon,
    double obliquity,
  ) {
    final x = cos(moon.latRad) * cos(moon.lonRad);
    final y = cos(moon.latRad) * sin(moon.lonRad);
    final z = sin(moon.latRad);
    final ye = y * cos(obliquity) - z * sin(obliquity);
    final ze = y * sin(obliquity) + z * cos(obliquity);
    return (atan2(ye, x), asin(ze));
  }

  /// Tempo sideral médio de Greenwich, em graus (Meeus cap. 12, em UT).
  static double _gmstDeg(DateTime utc) {
    final jd = _julianDay(utc);
    final t = (jd - 2451545.0) / 36525;
    final deg =
        280.46061837 +
        360.98564736629 * (jd - 2451545.0) +
        0.000387933 * t * t -
        t * t * t / 38710000;
    return deg % 360;
  }

  /// Longitude para −180..180.
  static double _wrapLon(double deg) => (deg + 540) % 360 - 180;

  // -------------------------------------------------- argumentos da Lua

  static double _meanLongitude(double t) =>
      218.3164477 +
      481267.88123421 * t -
      0.0015786 * t * t +
      t * t * t / 538841 -
      t * t * t * t / 65194000;

  static double _meanElongation(double t) =>
      297.8501921 +
      445267.1114034 * t -
      0.0018819 * t * t +
      t * t * t / 545868 -
      t * t * t * t / 113065000;

  static double _meanAnomalySun(double t) =>
      357.5291092 +
      35999.0502909 * t -
      0.0001536 * t * t +
      t * t * t / 24490000;

  static double _meanAnomalyMoon(double t) =>
      134.9633964 +
      477198.8675055 * t +
      0.0087414 * t * t +
      t * t * t / 69699 -
      t * t * t * t / 14712000;

  static double _argumentOfLatitude(double t) =>
      93.2720950 +
      483202.0175233 * t -
      0.0036539 * t * t -
      t * t * t / 3526000 +
      t * t * t * t / 863310000;
}

/// Posição eclíptica geocêntrica: longitude e latitude em radianos (de data) e
/// distância em km.
class _Ecliptic {
  const _Ecliptic({
    required this.lonRad,
    required this.latRad,
    required this.distKm,
  });

  final double lonRad;
  final double latRad;
  final double distKm;
}
