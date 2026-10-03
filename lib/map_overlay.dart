import 'package:flutter/material.dart';

/// A âncora de um cartão flutuante preso a um marcador do mapa.
///
/// O cartão NUNCA é posicionado por `left`/`top` fixos: a largura dele sai do
/// conteúdo (`IntrinsicWidth`, ver `PanelCard`), então não há como saber a
/// largura antes do layout. Ancorar pelo LADO que tem espaço — `right` quando o
/// marcador está na metade direita do mapa, `bottom` quando está na metade de
/// baixo — resolve isso sem medir o cartão e sem adivinhar.
///
/// Existe separado porque o marcador da Lua e os marcadores de cidade fazem a
/// MESMA conta: duas cópias divergiriam no dia em que uma fosse ajustada, e o
/// sintoma seria um painel saindo pela borda em um dos dois.
@immutable
class MapOverlayAnchor {
  const MapOverlayAnchor({this.left, this.right, this.top, this.bottom});

  /// Lados por onde o cartão se ancora. Exatamente um horizontal e um vertical
  /// ficam preenchidos; o outro par fica nulo.
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;

  /// A âncora de um marcador de raio [radius] centrado em [center], num mapa de
  /// [mapSize], afastada da BORDA do marcador por [gap].
  ///
  /// O afastamento é o MESMO nos dois eixos e sempre medido da borda: `radius +
  /// gap` nas quatro direções. Antes o horizontal descontava o raio e o vertical
  /// contava do centro, o que dava 3 pt de folga em cima/embaixo contra 10 pt
  /// dos lados — e impedia aproximar um rótulo do marcador, porque na vertical
  /// qualquer `gap` menor que o raio encostava no disco.
  ///
  /// Empate no meio exato do mapa vai para a direita/para baixo (`<=`).
  factory MapOverlayAnchor.forMarker({
    required Offset center,
    required double radius,
    required Size mapSize,
    required double gap,
  }) {
    final toRight = center.dx <= mapSize.width / 2;
    final below = center.dy <= mapSize.height / 2;
    final reach = radius + gap;
    return MapOverlayAnchor(
      left: toRight ? center.dx + reach : null,
      right: toRight ? null : mapSize.width - center.dx + reach,
      top: below ? center.dy + reach : null,
      bottom: below ? null : mapSize.height - center.dy + reach,
    );
  }

  /// O cartão posicionado, já protegido do ponteiro.
  ///
  /// O `IgnorePointer` mora AQUI, e não em quem chama: um overlay que captura o
  /// ponteiro faz o marcador perder o hover no mesmo instante em que o cartão
  /// aparece, e o painel fica piscando. Centralizar isso é o que impede um
  /// marcador novo de esquecer.
  Widget wrap(Widget child) => Positioned(
    left: left,
    right: right,
    top: top,
    bottom: bottom,
    child: IgnorePointer(child: child),
  );

  @override
  String toString() =>
      'MapOverlayAnchor(left: $left, right: $right, top: $top, bottom: $bottom)';
}
