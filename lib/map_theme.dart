import 'package:flutter/material.dart';

import 'world_dot_map.dart';

/// Um tema do mapa: as DUAS cores que o definem — a terra e o oceano — mais o
/// fundo contra o qual as duas são sombreadas pelo sol.
///
/// A ordem dos campos é a ordem em que o menu desenha o swatch: [land] em cima,
/// [ocean] embaixo.
@immutable
class MapTheme {
  const MapTheme({
    required this.id,
    required this.label,
    required this.land,
    required this.ocean,
    required this.background,
  });

  /// Identificador estável do tema (usado pelos testes; persistência depois).
  final String id;

  /// Nome mostrado no menu.
  final String label;

  /// Cor dos pontos de terra em pleno dia.
  final Color land;

  /// Cor dos pontos de oceano em pleno dia (o brilho do mar só vai do fundo
  /// até aqui).
  final Color ocean;

  /// Fundo atrás do mapa: o sombreamento solar esmaece os pontos até ele.
  final Color background;

  /// As duas cores do tema, na ordem em que o círculo do menu as mostra.
  List<Color> get swatch => [land, ocean];

  @override
  String toString() => 'MapTheme($id)';
}

/// Os temas oferecidos pelo submenu "Tema", na ordem do menu.
abstract final class MapThemes {
  /// A paleta que o app já usava: continentes laranja, mar cinza, fundo quase
  /// preto. É o padrão, então o app abre exatamente como abria antes de o menu
  /// existir.
  static const MapTheme standard = MapTheme(
    id: 'standard',
    label: 'Padrão',
    land: WorldDotMap.defaultDotColor,
    ocean: WorldDotMap.defaultOceanColor,
    background: WorldDotMap.defaultBackgroundColor,
  );

  /// Monocromático branco: só branco, preto e cinza. A terra vira branco puro
  /// e o mar continua o mesmo cinza neutro — a cor da terra era a única cor
  /// saturada do app, então é ela que sai.
  static const MapTheme monoWhite = MapTheme(
    id: 'mono-white',
    label: 'Monocromático branco',
    land: Color(0xFFFFFFFF),
    ocean: WorldDotMap.defaultOceanColor,
    background: WorldDotMap.defaultBackgroundColor,
  );

  /// Todos os temas, na ordem do submenu.
  static const List<MapTheme> all = [standard, monoWhite];
}
