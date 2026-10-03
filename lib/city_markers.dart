import 'package:flutter/material.dart';

import 'city.dart';
import 'city_clock.dart';
import 'clicked_point.dart';
import 'map_overlay.dart';
import 'panel_card.dart';
import 'place_lookup.dart';
import 'world_dot_map.dart';

/// Os pontos das cidades salvas no mapa, com o overlay do relógio.
///
/// É um WIDGET irmão do `RepaintBoundary` dos pontos — como o `UserMarker` e o
/// `MoonMarker`, e não uma pintura por cima deles. Assim um tique do relógio,
/// um clique num disco ou a chegada do catálogo reconstrói SÓ esta camada: o
/// mapa de dezenas de milhares de pontos não repinta (há teste travando isso,
/// no mesmo molde do teste do `UserMarker`).
///
/// **Tem de ser filho direto de um `Stack`** (é ele quem posiciona a si mesmo e
/// aos overlays), e esse `Stack` precisa de `clipBehavior: Clip.none` para um
/// overlay poder passar da borda do mapa sem ser recortado.
class CityMarkers extends StatelessWidget {
  const CityMarkers({
    super.key,
    required this.cities,
    required this.mapSize,
    required this.now,
    required this.here,
    required this.land,
    required this.background,
    this.selectedId,
    this.pinnedIds = const <String>{},
    this.onSelect,
    this.clickedPoint,
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

  /// O relógio de QUEM OLHA, para o "+1 dia" do overlay.
  final DateTime here;

  /// A cidade com o overlay aberto por clique. Nulo quando nenhuma foi clicada.
  final String? selectedId;

  /// As cidades com o overlay preso aberto ("sempre visível"), independente de
  /// clique. São os ids do catálogo (`City.id`).
  final Set<String> pinnedIds;

  /// Chamado com o id da cidade quando o disco dela é clicado. Nulo desliga o
  /// clique (os testes de desenho montam sem ele).
  final ValueChanged<String>? onSelect;

  /// O ponto que o usuário clicou no mapa, quando há um.
  ///
  /// É um marcador DIFERENTE das cidades: ele não está salvo em lugar nenhum, o
  /// nome pode não existir e a posição vem do clique, não do catálogo. Por isso
  /// o desenho dele é outro (um alvo) e o cartão diz o que se sabe — inclusive
  /// quando não se sabe o nome.
  final ClickedPoint? clickedPoint;

  /// Cor de TERRA do tema em uso: o anel de cada cidade acompanha o tema em vez
  /// de introduzir uma cor que o tema não tem.
  final Color land;

  /// Fundo do tema: o cartão do overlay, o mesmo dos painéis do menu.
  final Color background;

  /// Diâmetro total do disco, em pontos.
  ///
  /// Fixo pelo mesmo motivo do disco da Lua e do ponto do usuário: a escala dos
  /// PONTOS do mapa encolhe com a janela, este objeto não — ele precisa
  /// continuar achável em qualquer tamanho de janela.
  static const double diameter = 14;

  /// Alvo de clique, maior que o disco: 14 pt é pequeno demais para o mouse.
  /// O mesmo valor do alvo do disco da Lua.
  static const double hitSize = 24;

  /// Distância entre o disco e o overlay, em pontos.
  static const double gap = 12;

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

  /// Se a cidade aparece com o overlay aberto: clicada ou presa.
  bool _isOpen(City city) =>
      city.id == selectedId || pinnedIds.contains(city.id);

  @override
  Widget build(BuildContext context) {
    final clicked = clickedPoint;
    if (cities.isEmpty && clicked == null) {
      return const SizedBox.shrink();
    }

    // Discos e overlays em listas separadas de propósito: TODOS os discos vão
    // antes de TODOS os overlays no Stack. Intercalados, o disco de uma cidade
    // poderia ser desenhado por cima do cartão de outra e "comer" um pedaço do
    // painel aberto.
    final discs = <Widget>[];
    final overlays = <Widget>[];
    for (final clock in cities) {
      final center = offsetFor(clock.city, mapSize);
      discs.add(_disc(clock, center));
      if (_isOpen(clock.city)) {
        overlays.add(_overlay(clock, center));
      }
    }

    if (clicked != null) {
      final center = clicked.point.offsetIn(mapSize);
      discs.add(_clickedDisc(clicked, center));
      // Sem resposta ainda, só o alvo: o cartão entra quando houver o que dizer.
      // Mostrar um cartão vazio por um quadro piscaria à toa.
      if (clicked.isResolved) {
        overlays.add(_clickedOverlay(clicked, center));
      }
    }

    return Stack(clipBehavior: Clip.none, children: [...discs, ...overlays]);
  }

  /// O disco clicável de uma cidade.
  Widget _disc(CityClock clock, Offset center) {
    final city = clock.city;
    final reading = ClockReading.at(clock, now, here: here);
    final label = [
      city.name,
      if (city.countryName.isNotEmpty) city.countryName,
    ].join(', ');

    final disc = SizedBox.square(
      dimension: hitSize,
      child: Center(
        child: SizedBox.square(
          dimension: diameter,
          child: CustomPaint(painter: _CityDotPainter(land: land)),
        ),
      ),
    );

    return Positioned(
      left: center.dx - hitSize / 2,
      top: center.dy - hitSize / 2,
      child: Semantics(
        // O leitor de tela recebe o horário junto: só o nome da cidade não
        // responde à pergunta que o mapa está ali para responder.
        label:
            '$label: ${reading.time}'
            '${reading.dayOffset.isEmpty ? '' : ' (${reading.dayOffset})'}',
        button: onSelect != null,
        child: onSelect == null
            ? disc
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect!(city.id),
                  child: disc,
                ),
              ),
      ),
    );
  }

  /// O cartão do relógio: nome e país em cima, horário embaixo.
  Widget _overlay(CityClock clock, Offset center) {
    final city = clock.city;
    final reading = ClockReading.at(clock, now, here: here);

    return MapOverlayAnchor.forMarker(
      center: center,
      radius: diameter / 2,
      mapSize: mapSize,
      gap: gap,
    ).wrap(
      PanelCard(
        background: background,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  city.name,
                  style: TextStyle(fontSize: 13, color: PanelCard.textColor),
                ),
                if (city.countryName.isNotEmpty)
                  Text(
                    city.countryName,
                    style: TextStyle(
                      fontSize: 12,
                      color: PanelCard.dimTextColor,
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      reading.time,
                      style: TextStyle(
                        fontSize: 22,
                        color: PanelCard.textColor,
                        // Dígitos de largura fixa: sem isso o relógio inteiro
                        // se mexe um pixel a cada minuto, quando um "1" entra no
                        // lugar de um "8".
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (reading.dayOffset.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        reading.dayOffset,
                        style: TextStyle(
                          fontSize: 12,
                          color: PanelCard.dimTextColor,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  reading.offset,
                  style: TextStyle(fontSize: 11, color: PanelCard.dimTextColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// O alvo do ponto clicado.
  ///
  /// `IgnorePointer`: ele é informação, não um controle. Um clique em cima dele
  /// atravessa e recai no mapa, que resolve o mesmo ponto outra vez —
  /// inofensivo, e mais previsível do que um alvo que engole o clique.
  Widget _clickedDisc(ClickedPoint clicked, Offset center) {
    final place = clicked.place;
    return Positioned(
      left: center.dx - hitSize / 2,
      top: center.dy - hitSize / 2,
      child: IgnorePointer(
        child: Semantics(
          label: place == null
              ? 'Ponto consultado no mapa'
              : '${place.label}: '
                    '${ClockReading.forLocation(place.location, now, here: here).time}',
          child: SizedBox.square(
            dimension: hitSize,
            child: Center(
              child: SizedBox.square(
                dimension: diameter,
                child: CustomPaint(painter: _ClickedPointPainter(land: land)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// O cartão do ponto clicado: o que se sabe do lugar, e a hora.
  Widget _clickedOverlay(ClickedPoint clicked, Offset center) {
    final place = clicked.place!;
    final reading = ClockReading.forLocation(place.location, now, here: here);
    final title = place.name == null
        ? place.label
        : (place.approximate ? '≈ ${place.name}' : place.name!);
    final detail = _detailOf(place);

    return MapOverlayAnchor.forMarker(
      center: center,
      radius: diameter / 2,
      mapSize: mapSize,
      gap: gap,
    ).wrap(
      PanelCard(
        background: background,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 13, color: PanelCard.textColor),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: PanelCard.dimTextColor,
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      reading.time,
                      style: TextStyle(
                        fontSize: 22,
                        color: PanelCard.textColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (reading.dayOffset.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        reading.dayOffset,
                        style: TextStyle(
                          fontSize: 12,
                          color: PanelCard.dimTextColor,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  reading.offset,
                  style: TextStyle(fontSize: 11, color: PanelCard.dimTextColor),
                ),
                // Só quando NÃO há nome: aí o motivo explica a ausência, em vez
                // de deixar o cartão sem título e sem explicação.
                if (place.notice case final notice? when place.name == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      notice,
                      style: TextStyle(
                        fontSize: 11,
                        color: PanelCard.dimTextColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A linha de baixo do título de um ponto clicado: o país e, quando o nome é o
/// da cidade mais próxima, a que distância ela está.
///
/// A ressalva não é enfeite: "≈ Djanet · a 181 km" é a diferença entre informar
/// e enganar quem clicou no meio do Saara.
String? _detailOf(PlaceInfo place) {
  final country = place.country;
  final parts = <String>[
    if (country != null && country.isNotEmpty) country,
    if (place.approximate && place.distanceKm != null)
      'a ${place.distanceKm!.round()} km',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// O alvo do ponto consultado: um anel com um ponto no meio.
///
/// A forma separa os quatro marcadores do mapa de relance: o ponto do usuário e
/// a Lua são discos CHEIOS, a cidade é um anel VAZADO e o ponto consultado é um
/// alvo (anel com miolo).
class _ClickedPointPainter extends CustomPainter {
  const _ClickedPointPainter({required this.land});

  final Color land;

  /// Largura do anel claro externo, em pontos.
  static const double haloWidth = 1.4;

  /// Largura do anel do tema, em pontos.
  static const double ringWidth = 1.6;

  /// Raio do miolo, em pontos.
  static const double dotRadius = 1.6;

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
    canvas.drawCircle(
      center,
      dotRadius,
      paint
        ..style = PaintingStyle.fill
        ..color = _halo,
    );
  }

  @override
  bool shouldRepaint(covariant _ClickedPointPainter oldDelegate) =>
      oldDelegate.land != land;
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
