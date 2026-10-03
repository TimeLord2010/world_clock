/// O fuso de um ponto em MAR ABERTO, pela longitude.
///
/// Os polígonos do Timezone Boundary Builder cobrem terra (com uma faixa
/// costeira de ~22 km para fora): em oceano aberto não existe zona política para
/// consultar, e `findLocation` devolve nulo. A convenção náutica é dividir a
/// longitude em 24 faixas de 15° — uma hora cada —, que é o que a tzdb publica
/// como `Etc/GMT±n`.
///
/// **ATENÇÃO AO SINAL.** As zonas `Etc/GMT` seguem a convenção POSIX, que é
/// INVERTIDA em relação ao uso comum: `Etc/GMT+2` é UTC−2. Medido contra o
/// Open-Meteo em (0, −30), que responde exatamente `Etc/GMT+2` com
/// `utc_offset_seconds = -7200`. Trocar isso deixa o relógio errado em duas
/// vezes o deslocamento — 4 horas, no caso de −2 —, e o erro parece plausível.
library;

/// O id IANA do fuso náutico que contém [longitude].
///
/// A longitude é normalizada para [-180, 180) antes da conta: uma coordenada
/// fora do intervalo (vinda de um clique preso à borda, por exemplo) cairia numa
/// faixa inexistente e `tz.getLocation` lançaria.
String nauticalZoneId(double longitude) {
  var lon = longitude;
  while (lon < -180) {
    lon += 360;
  }
  while (lon >= 180) {
    lon -= 360;
  }
  // Faixas de 15°: -12..12. O zero é a faixa de Greenwich, que a tzdb chama só
  // de `Etc/GMT` (sem número).
  final band = (lon / 15).round();
  if (band == 0) {
    return 'Etc/GMT';
  }
  // O sinal do ID é o inverso do deslocamento (convenção POSIX).
  return 'Etc/GMT${band > 0 ? '-' : '+'}${band.abs()}';
}
