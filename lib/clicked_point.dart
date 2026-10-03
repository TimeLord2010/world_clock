import 'package:flutter/foundation.dart' show immutable;

import 'map_geometry.dart';
import 'place_lookup.dart';

/// Um ponto que o usuário clicou no mapa, e o que já se sabe dele.
///
/// Nasce só com a coordenada — que é imediata — e ganha o [place] quando a
/// consulta volta. Essa ordem é o ponto: a HORA não espera por nome nem por
/// rede, então o cartão nunca fica "carregando" a resposta que o usuário pediu.
@immutable
class ClickedPoint {
  const ClickedPoint({required this.point, this.place});

  /// A coordenada clicada.
  final MapPoint point;

  /// O que o resolver devolveu. Nulo enquanto a consulta não volta.
  final PlaceInfo? place;

  /// Se a consulta já respondeu (nem que seja para dizer que não há nome).
  bool get isResolved => place != null;

  ClickedPoint withPlace(PlaceInfo place) =>
      ClickedPoint(point: point, place: place);

  @override
  String toString() =>
      'ClickedPoint($point, ${place == null ? 'sem resposta' : '$place'})';
}
