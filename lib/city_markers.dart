import 'package:flutter/material.dart';

import 'city.dart';
import 'city_clock.dart';
import 'map_overlay.dart';
import 'world_dot_map.dart';

/// Os pontos das cidades salvas no mapa, cada um com o NOME e a HORA ao lado.
///
/// O rótulo aparece para toda cidade salva, sempre — não há clique para abrir
/// nem opção para ligar: uma cidade que está no mapa está no mapa com o horário
/// dela à vista.
///
/// É um WIDGET irmão do `RepaintBoundary` dos pontos — como o `UserMarker` e o
/// `MoonMarker`, e não uma pintura por cima deles. Assim o tique do relógio ou a
/// chegada do catálogo reconstrói SÓ esta camada: o mapa de dezenas de milhares
/// de pontos não repinta (há teste travando isso).
///
/// **Tem de ser filho direto de um `Stack`** (é ele quem posiciona a si mesmo e
/// aos rótulos), e esse `Stack` precisa de `clipBehavior: Clip.none` para um
/// rótulo poder passar da borda do mapa sem ser recortado.
class CityMarkers extends StatelessWidget {
  const CityMarkers({
    super.key,
    required this.cities,
    required this.mapSize,
    required this.now,
    required this.here,
    required this.land,
  });

  /// As cidades a desenhar, com o fuso de cada uma já resolvido.
  final List<CityClock> cities;

  /// Tamanho do retângulo do mapa, em pontos — o mesmo `SizedBox` que envolve
  /// o `WorldDotMap`.
  final Size mapSize;

  /// O instante que os relógios mostram.
  ///
  /// Vem de fora (do ticker da camada, ver `CityClockLayer`) em vez de sair de
  /// um `DateTime.now()` aqui dentro: um widget que lê o relógio do sistema não
  /// tem como ser testado numa hora fixa, e este projeto testa hora fixa em
  /// todo lugar (`WorldDotMap(now:)`, `MoonMarker(status:)`).
  final DateTime now;

  /// O relógio de QUEM OLHA, para o "+1 dia" do rótulo.
  final DateTime here;

  /// Cor de TERRA do tema em uso: o anel de cada cidade acompanha o tema em vez
  /// de introduzir uma cor que o tema não tem.
  final Color land;

  /// Diâmetro total do disco, em pontos.
  ///
  /// Fixo pelo mesmo motivo do disco da Lua e do ponto do usuário: a escala dos
  /// PONTOS do mapa encolhe com a janela, este objeto não — ele precisa
  /// continuar visível em qualquer tamanho de janela.
  static const double diameter = 14;

  /// Distância entre o disco e o rótulo, em pontos.
  static const double gap = 10;

  /// Corpo do nome da cidade.
  static const double nameFontSize = 11;

  /// Corpo do horário. Maior que o do nome porque o número é a informação; os
  /// dois bem menores do que eram quando isto era um cartão — sem caixa em
  /// volta, o texto tem de se dissolver no mapa em vez de competir com ele.
  static const double timeFontSize = 15;

  /// Corpo do "+1 dia".
  static const double dayOffsetFontSize = 9;

  /// Cor do nome: um branco levemente apagado, para o horário ficar por cima
  /// na hierarquia.
  static final Color nameColor = Colors.white.withValues(alpha: 0.78);

  /// Cor do horário: branco quase puro.
  static final Color timeColor = Colors.white.withValues(alpha: 0.97);

  /// Halo escuro em volta do texto.
  ///
  /// Sem caixa, é ISTO que mantém o rótulo legível — tanto sobre os pontos
  /// laranja de terra quanto sobre o cinza do mar, e em qualquer tema. Duas
  /// camadas de desfoque dão uma borda macia, que se lê bem sem desenhar um
  /// contorno duro brigando com a malha de pontos.
  static const List<Shadow> halo = [
    Shadow(blurRadius: 3, color: Color(0xE6000000)),
    Shadow(blurRadius: 7, color: Color(0x99000000)),
  ];

  /// Centro do disco, em pontos, dentro do retângulo do mapa.
  ///
  /// Usa a MESMA projeção do dataset ([WorldDotMap.normalize]) e de
  /// `UserMarker.offsetFor`/`MoonMarker.offsetFor`: a mesma coordenada tem de
  /// cair no mesmo pixel nos três marcadores, e há teste comparando os três.
  /// Repare que é a projeção CONTÍNUA, não a célula de 1°: a cidade fica na
  /// coordenada dela, não no centro do quadrado da grade que a contém.
  static Offset offsetFor(City city, Size mapSize) {
    final unit = WorldDotMap.normalize(city.longitude, city.latitude);
    return Offset(unit.dx * mapSize.width, unit.dy * mapSize.height);
  }

  @override
  Widget build(BuildContext context) {
    if (cities.isEmpty) {
      return const SizedBox.shrink();
    }

    // Discos e rótulos em listas separadas de propósito: TODOS os discos vão
    // antes de TODOS os rótulos no Stack. Intercalados, o disco de uma cidade
    // poderia ser desenhado por cima do texto de outra e "comer" um pedaço do
    // nome.
    final discs = <Widget>[];
    final labels = <Widget>[];
    for (final clock in cities) {
      final center = offsetFor(clock.city, mapSize);
      discs.add(_disc(clock, center));
      labels.add(_label(clock, center));
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [...discs, ...labels],
    );
  }

  /// O disco de uma cidade, com o rótulo inteiro no `Semantics`.
  ///
  /// `IgnorePointer`: nada aqui responde ao ponteiro. O disco é sinalização, e
  /// um rótulo que captura o ponteiro só atrapalharia o que passa por baixo.
  Widget _disc(CityClock clock, Offset center) {
    final city = clock.city;
    final reading = ClockReading.at(clock, now, here: here);
    final label = [
      city.name,
      if (city.countryName.isNotEmpty) city.countryName,
    ].join(', ');

    return Positioned(
      left: center.dx - diameter / 2,
      top: center.dy - diameter / 2,
      child: IgnorePointer(
        child: Semantics(
          // O leitor de tela recebe o horário junto: só o nome da cidade não
          // responde à pergunta que o mapa está ali para responder.
          label: '$label: ${reading.time}'
              '${reading.dayOffset.isEmpty ? '' : ' (${reading.dayOffset})'}',
          child: SizedBox.square(
            dimension: diameter,
            child: CustomPaint(painter: _CityDotPainter(land: land)),
          ),
        ),
      ),
    );
  }

  /// O rótulo: nome da cidade e, embaixo, o horário.
  ///
  /// Sem cartão em volta — nem fundo, nem fio, nem sombra de caixa. O que separa
  /// o texto do mapa é o [halo], e só.
  Widget _label(CityClock clock, Offset center) {
    final city = clock.city;
    final reading = ClockReading.at(clock, now, here: here);

    return MapOverlayAnchor.forMarker(
      center: center,
      radius: diameter / 2,
      mapSize: mapSize,
      gap: gap,
    ).wrap(
      // O texto visível não é anunciado de novo: o `Semantics` do disco já diz
      // cidade e horário numa frase só, e repetir soaria como eco.
      ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              city.name,
              style: TextStyle(
                fontSize: nameFontSize,
                height: 1.15,
                color: nameColor,
                shadows: halo,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  reading.time,
                  style: TextStyle(
                    fontSize: timeFontSize,
                    height: 1.15,
                    color: timeColor,
                    shadows: halo,
                    // Dígitos de largura fixa: sem isso o relógio inteiro se
                    // mexe um pixel a cada minuto, quando um "1" entra no lugar
                    // de um "8".
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (reading.dayOffset.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Text(
                    reading.dayOffset,
                    style: TextStyle(
                      fontSize: dayOffsetFontSize,
                      height: 1.15,
                      color: nameColor,
                      shadows: halo,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// O disco de uma cidade: um ANEL, não um disco cheio.
///
/// A forma é o que separa os três marcadores do mapa de relance: o ponto do
/// usuário e a Lua são discos CHEIOS (miolo claro com anel branco), a cidade é
/// um anel vazado — o mapa aparece pelo meio.
///
/// O anel claro por fora é o que faz o marcador saltar tanto sobre a terra
/// (pontos claros) quanto sobre o mar (pontos escuros) em qualquer tema, sem
/// precisar de uma cor nova no tema.
class _CityDotPainter extends CustomPainter {
  const _CityDotPainter({required this.land});

  final Color land;

  /// Largura do anel claro externo, em pontos.
  static const double haloWidth = 1.6;

  /// Largura do anel do tema, em pontos.
  static const double ringWidth = 2.2;

  static final Color _halo = Colors.white.withValues(alpha: 0.92);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()..isAntiAlias = true;

    canvas.drawCircle(
      center,
      radius - haloWidth / 2,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = haloWidth
        ..color = _halo,
    );
    canvas.drawCircle(
      center,
      radius - haloWidth - ringWidth / 2,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..color = land,
    );
  }

  @override
  bool shouldRepaint(covariant _CityDotPainter oldDelegate) =>
      oldDelegate.land != land;
}
