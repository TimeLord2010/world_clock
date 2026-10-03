import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show Offset, Size;

import 'world_dot_map.dart';

/// Um ponto do mundo (latitude/longitude) e a sua ida e volta para o mapa.
///
/// Existe separado do `WorldDotMap` porque responde a outra pergunta: o mapa
/// projeta coordenada em pixel (dado → tela), isto faz o caminho de volta a
/// partir de um clique (tela → dado) — e é o único lugar que sabe que o
/// retângulo do mapa É o mundo inteiro, sem zoom nem rolagem.
@immutable
class MapPoint {
  const MapPoint({required this.latitude, required this.longitude});

  /// O ponto do mundo sob [local], num mapa de [mapSize] pontos.
  ///
  /// [local] é a posição JÁ RELATIVA ao retângulo do mapa (o
  /// `TapUpDetails.localPosition` de um detector que envolve exatamente o
  /// `SizedBox` do mapa), então não há conversão global→local aqui.
  factory MapPoint.at(Offset local, Size mapSize) {
    // Guarda contra layout degenerado (largura/altura zero ou negativa): sem
    // isso a divisão dá NaN/Infinity e a coordenada vira lixo que só aparece
    // muito depois, como um ponto em lugar nenhum.
    final unit = Offset(
      mapSize.width <= 0 ? 0 : (local.dx / mapSize.width).clamp(0.0, 1.0),
      mapSize.height <= 0 ? 0 : (local.dy / mapSize.height).clamp(0.0, 1.0),
    );
    final geo = WorldDotMap.unproject(unit);
    return MapPoint(longitude: geo.dx, latitude: geo.dy);
  }

  final double latitude;
  final double longitude;

  /// Onde este ponto cai num mapa de [mapSize] pontos.
  ///
  /// Usa a MESMA projeção do dataset ([WorldDotMap.normalize]), então o ponto
  /// clicado, o ponto do usuário e as cidades caem todos no mesmo pixel para a
  /// mesma coordenada.
  Offset offsetIn(Size mapSize) {
    final unit = WorldDotMap.normalize(longitude, latitude);
    return Offset(unit.dx * mapSize.width, unit.dy * mapSize.height);
  }

  @override
  String toString() =>
      'MapPoint(${latitude.toStringAsFixed(3)}, '
      '${longitude.toStringAsFixed(3)})';

  @override
  bool operator ==(Object other) =>
      other is MapPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}
