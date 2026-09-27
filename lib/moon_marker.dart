import 'dart:math';

import 'package:flutter/material.dart';

import 'moon_position.dart';
import 'panel_card.dart';
import 'world_dot_map.dart';

/// A Lua desenhada no mapa como um objeto à parte — um disco simples, e não
/// uma camada de pontos como o mapa em si.
///
/// O marcador é um WIDGET posicionado dentro do `Stack` do mapa (ver
/// `main.dart`), não uma pintura por cima dos pontos: assim ele fica acima do
/// `RepaintBoundary` do mapa e redesenhar a Lua não repinta as dezenas de
/// milhares de pontos do mapa.
///
/// O overlay com os números abre com o ponteiro EM CIMA do disco e fecha quando
/// ele sai: o estado do hover mora aqui, e o rebuild que ele provoca não suja o
/// mapa — o pintor dos pontos continua recebendo os mesmos dados, então
/// `shouldRepaint` devolve falso e o mapa não repinta (é o oposto do hover do
/// menu, que vivia na mesma camada do mapa e por isso foi removido).
///
/// **Tem de ser filho direto de um `Stack`** (é ele quem posiciona a si mesmo e
/// ao overlay), e esse `Stack` precisa de `clipBehavior: Clip.none` para o
/// overlay poder passar da borda do mapa quando a Lua está colada no limite.
class MoonMarker extends StatefulWidget {
  const MoonMarker({
    super.key,
    required this.status,
    required this.mapSize,
    required this.background,
    this.diameter = 14,
  });

  /// Onde e como a Lua está no instante atual.
  final MoonStatus status;

  /// Tamanho do retângulo do mapa, em pontos — o mesmo `SizedBox` que envolve
  /// o `WorldDotMap`.
  final Size mapSize;

  /// Fundo do tema em uso: o overlay usa o mesmo cartão dos painéis do menu.
  final Color background;

  /// Diâmetro do disco, em pontos. Fixo de propósito: a escala dos PONTOS do
  /// mapa encolhe com a janela, mas a Lua é outro objeto e não vira poeira.
  final double diameter;

  /// Centro do disco, em pontos, dentro do retângulo do mapa.
  ///
  /// Usa a MESMA projeção equirretangular do dataset
  /// ([WorldDotMap.normalize]), então a Lua cai no lugar exato da grade.
  static Offset offsetFor(double lonDeg, double latDeg, Size mapSize) {
    final unit = WorldDotMap.normalize(lonDeg, latDeg);
    return Offset(unit.dx * mapSize.width, unit.dy * mapSize.height);
  }

  /// Direção da luz, em radianos no eixo da tela: aponta do subponto lunar para
  /// o subponto do Sol, no espaço do mapa.
  ///
  /// A diferença de longitude é normalizada a ±180° antes de virar pixel — sem
  /// isso, Lua em −179° e Sol em +179° (vizinhos no mapa) dariam meia volta de
  /// erro no lado iluminado.
  static double litTurnRad(MoonStatus status, Size mapSize) {
    final deltaLon = (status.sunSubLonDeg - status.subLonDeg + 540) % 360 - 180;
    final dx = deltaLon * mapSize.width / 360;
    final dy = (status.subLatDeg - status.sunSubLatDeg) * mapSize.height / 180;
    return atan2(dy, dx);
  }

  /// Distância entre o disco e o overlay, em pontos.
  static const double gap = 12;

  @override
  State<MoonMarker> createState() => _MoonMarkerState();
}

class _MoonMarkerState extends State<MoonMarker> {
  /// Ponteiro em cima do disco.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final center = MoonMarker.offsetFor(
      status.subLonDeg,
      status.subLatDeg,
      widget.mapSize,
    );
    final radius = widget.diameter / 2;
    // Área de hover um pouco maior que o disco: 14 pt é alvo pequeno demais
    // para acertar com o mouse, e nada embaixo é clicável (o mapa é só pintura).
    const hitSize = 24.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: center.dx - hitSize / 2,
          top: center.dy - hitSize / 2,
          child: MouseRegion(
            // O cursor de interrogação é a convenção do macOS para "pare aqui e
            // veja a informação" — o disco não clica, só revela o overlay.
            cursor: SystemMouseCursors.help,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: SizedBox(
              width: hitSize,
              height: hitSize,
              child: Center(
                child: MoonDisc(
                  illumination: status.illumination,
                  diameter: widget.diameter,
                  litDirectionRad: MoonMarker.litTurnRad(
                    status,
                    widget.mapSize,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_hovered) _overlay(center, radius),
      ],
    );
  }

  /// O painel de informações, encostado no disco do lado que tem espaço: se a
  /// Lua está na metade direita do mapa, o painel abre para a esquerda (e vice
  /// versa); idem para cima/baixo. Ancorar pelo lado — `right`/`bottom` — evita
  /// ter que adivinhar a largura do painel antes do layout, que é o que
  /// aconteceria se ele fosse posicionado por `left`/`top` fixos.
  Widget _overlay(Offset center, double radius) {
    final status = widget.status;
    final toRight = center.dx <= widget.mapSize.width / 2;
    final below = center.dy <= widget.mapSize.height / 2;

    return Positioned(
      left: toRight ? center.dx + radius + MoonMarker.gap : null,
      right: toRight
          ? null
          : widget.mapSize.width - center.dx + radius + MoonMarker.gap,
      top: below ? center.dy + MoonMarker.gap : null,
      bottom: below ? null : widget.mapSize.height - center.dy + MoonMarker.gap,
      // IgnorePointer: o overlay nunca pode roubar o ponteiro do mapa — sem
      // isso, ele apareceria e no mesmo instante o MouseRegion de baixo perderia
      // o hover, e o painel ficaria piscando.
      child: IgnorePointer(
        child: PanelCard(
          background: widget.background,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MoonDisc(
                    illumination: status.illumination,
                    diameter: 22,
                    litDirectionRad: status.waxing ? 0 : pi,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${formatDecimal(status.illuminationPercent)}% iluminada',
                    style: TextStyle(fontSize: 13, color: PanelCard.textColor),
                  ),
                ],
              ),
            ),
            PanelInfoRow(label: 'Fase', value: status.phase.label),
            PanelInfoRow(
              label: 'Distância',
              value: '${formatThousands(status.distanceKm.round())} km',
            ),
            // As próximas datas saem em ordem CRONOLÓGICA, e só com a data: são
            // "o que vem depois", e a ordem fixa (nova, 50%, cheia) faria a
            // linha do meio aparecer ANTES da de cima na metade minguante do mês
            // — o 50% minguante acontece antes da próxima nova. A hora
            // ("04:13 UTC") não muda nada para quem olha o painel.
            for (final (label, date) in _upcoming(status))
              PanelInfoRow(
                label: label,
                value: formatDate(date),
                dimValue: true,
              ),
          ],
        ),
      ),
    );
  }

  /// As três próximas datas — nova, 50% e cheia — em ordem cronológica.
  ///
  /// O rótulo do 50% diz o lado da passagem porque são DUAS por mês sinódico:
  /// crescente (entre a nova e a cheia) e minguante (entre a cheia e a nova).
  static List<(String, DateTime)> _upcoming(MoonStatus status) {
    final events = [
      ('Próxima nova', status.nextNewMoon),
      ('Próxima cheia', status.nextFullMoon),
      (
        status.nextHalfMoon.waxing ? '50% crescente' : '50% minguante',
        status.nextHalfMoon.when,
      ),
    ];
    events.sort((a, b) => a.$2.compareTo(b.$2));
    return events;
  }
}

/// O disco da Lua com a fase desenhada: a parte iluminada é branca, a escura é
/// só um véu claro sobre o que está atrás, e um anel escuro separa o disco do
/// mapa em qualquer tema.
class MoonDisc extends StatelessWidget {
  const MoonDisc({
    super.key,
    required this.illumination,
    this.diameter = 14,
    this.litDirectionRad,
  });

  /// Fração iluminada, 0..1 ([MoonStatus.illumination]).
  final double illumination;

  /// Diâmetro do disco, em pontos.
  final double diameter;

  /// Para onde a parte iluminada aponta, em radianos (0 = direita). Nulo deixa
  /// o lado iluminado na convenção de ícone: à direita.
  final double? litDirectionRad;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: diameter,
      child: CustomPaint(
        painter: _MoonDiscPainter(
          illumination: illumination,
          litDirectionRad: litDirectionRad,
        ),
      ),
    );
  }
}

class _MoonDiscPainter extends CustomPainter {
  const _MoonDiscPainter({
    required this.illumination,
    required this.litDirectionRad,
  });

  final double illumination;
  final double? litDirectionRad;

  /// A parte iluminada: branco quente, o mesmo dos temas claros.
  static const Color litColor = Color(0xFFF5F5F5);

  /// A parte escura: um véu claro em vez de preto — assim o lado noturno do
  /// disco continua visível sobre o fundo escuro do mapa.
  static final Color darkColor = Colors.white.withValues(alpha: 0.16);

  /// Anel de contorno: sem ele o disco some sobre os pontos em pleno dia.
  static final Color ringColor = Colors.black.withValues(alpha: 0.55);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Meio ponto de folga: o anel fica DENTRO da caixa, sem ser recortado.
    final radius = size.shortestSide / 2 - 0.5;
    final paint = Paint()..isAntiAlias = true;

    canvas.drawCircle(center, radius, paint..color = darkColor);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(litDirectionRad ?? 0);
    canvas.drawPath(_litPath(radius), paint..color = litColor);
    canvas.restore();

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ringColor,
    );
  }

  /// A região iluminada, com o limbo à direita (+x) antes da rotação.
  ///
  /// O terminador é uma semi-elipse de semi-eixo `r·|cos i|` (i = ângulo de
  /// fase, `cos i = 2k − 1`): estreita no quarto, larga na cheia e na nova. O
  /// lado para onde ela boja é o que separa crescente de gibosa — e nos
  /// extremos a elipse encosta no limbo, então a área vai a zero na lua nova,
  /// sem caso especial.
  Path _litPath(double radius) {
    final cosPhase = (2 * illumination - 1).clamp(-1.0, 1.0);
    final limb = Rect.fromCircle(center: Offset.zero, radius: radius);
    final terminator = Rect.fromCenter(
      center: Offset.zero,
      width: 2 * radius * cosPhase.abs(),
      height: 2 * radius,
    );
    return Path()
      ..addArc(limb, -pi / 2, pi)
      ..arcTo(terminator, pi / 2, cosPhase >= 0 ? pi : -pi, false)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _MoonDiscPainter oldDelegate) =>
      oldDelegate.illumination != illumination ||
      oldDelegate.litDirectionRad != litDirectionRad;
}
