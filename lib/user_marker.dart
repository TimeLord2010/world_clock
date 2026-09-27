import 'package:flutter/material.dart';

import 'user_location.dart';
import 'world_dot_map.dart';

/// O ponto do usuário no mapa: um disco único, do tamanho do disco da Lua.
///
/// É um WIDGET colocado dentro do `Stack` do mapa (ver `main.dart`), irmão do
/// `RepaintBoundary` dos pontos — não uma pintura por cima deles. Assim um
/// tique que move o ponto (ou a chegada da posição, que é assíncrona) não
/// invalida a camada dos pontos, e o mapa não repinta as dezenas de milhares de
/// pontos por causa disso.
///
/// Sem hover, sem clique e sem texto: o ponto é sinalização. Nada aqui revela
/// coordenada — o número não agrega para quem olha o mapa ("é aqui" é a
/// informação), e é a mesma linha que o painel da Lua seguiu.
class UserMarker extends StatelessWidget {
  const UserMarker({
    super.key,
    required this.location,
    required this.mapSize,
    required this.land,
    required this.background,
  });

  /// A posição a marcar. Nula (consulta ainda em curso) ou sem coordenada
  /// (falhou): nada é desenhado — e o motivo aparece na bandeja de opções.
  final UserLocation? location;

  /// Tamanho do retângulo do mapa, em pontos — o mesmo `SizedBox` que envolve
  /// o `WorldDotMap`.
  final Size mapSize;

  /// Cor de TERRA do tema em uso: o miolo do disco acompanha o tema, em vez de
  /// introduzir uma cor que o tema não tem.
  final Color land;

  /// Fundo do tema: o anel escuro que separa o disco do mapa.
  final Color background;

  /// Diâmetro total do disco, em pontos. Fixo pelo mesmo motivo do disco da
  /// Lua: a escala dos PONTOS encolhe com a janela, este objeto não — ele
  /// precisa continuar achável em qualquer tamanho de janela.
  static const double diameter = 14;

  /// Centro do disco, em pontos, dentro do retângulo do mapa; nulo sem posição.
  ///
  /// Usa a MESMA projeção do dataset ([WorldDotMap.normalize]), então o ponto
  /// cai no lugar exato da grade — é o que faz o disco significar a coordenada
  /// e não um enfeite por perto.
  static Offset? offsetFor(UserLocation? location, Size mapSize) {
    final latitude = location?.latitude;
    final longitude = location?.longitude;
    if (latitude == null || longitude == null) {
      return null;
    }
    final unit = WorldDotMap.normalize(longitude, latitude);
    return Offset(unit.dx * mapSize.width, unit.dy * mapSize.height);
  }

  @override
  Widget build(BuildContext context) {
    final center = offsetFor(location, mapSize);
    if (center == null) {
      return const SizedBox.shrink();
    }
    final radius = diameter / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: center.dx - radius,
          top: center.dy - radius,
          // IgnorePointer: o mapa embaixo não é clicável e nada aqui responde
          // ao ponteiro — o disco não pode capturar o que passa por baixo
          // (o marcador da Lua tem hover, este não).
          child: IgnorePointer(
            child: Semantics(
              label: 'Sua posição no mapa',
              child: SizedBox.square(
                dimension: diameter,
                child: CustomPaint(
                  painter: _UserDotPainter(land: land, background: background),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// O disco: miolo na cor de terra do tema, anel escuro de separação e um anel
/// claro por fora.
///
/// O anel claro é o que faz o ponto saltar tanto sobre a terra (pontos claros)
/// quanto sobre o mar (pontos escuros) em QUALQUER tema, sem precisar de uma cor
/// nova no tema — o escuro sozinho some sobre o mar, o claro sozinho some sobre
/// a terra.
class _UserDotPainter extends CustomPainter {
  const _UserDotPainter({required this.land, required this.background});

  final Color land;
  final Color background;

  /// Largura do anel claro externo, em pontos.
  static const double haloWidth = 2.2;

  /// Largura do anel escuro intermediário, em pontos.
  static const double separatorWidth = 1.4;

  static final Color _halo = Colors.white.withValues(alpha: 0.92);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()..isAntiAlias = true;

    // Anel claro: ocupa a borda do disco.
    canvas.drawCircle(
      center,
      radius - haloWidth / 2,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = haloWidth
        ..color = _halo,
    );

    // Anel escuro: encostado por dentro do claro. Sem ele, o miolo claro do
    // tema monocromático encostaria no anel claro e o disco viraria uma bolha.
    final separatorRadius = radius - haloWidth - separatorWidth / 2;
    canvas.drawCircle(
      center,
      separatorRadius,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = separatorWidth
        ..color = background,
    );

    // Miolo.
    canvas.drawCircle(
      center,
      separatorRadius - separatorWidth / 2,
      paint
        ..style = PaintingStyle.fill
        ..color = land,
    );
  }

  @override
  bool shouldRepaint(covariant _UserDotPainter oldDelegate) =>
      oldDelegate.land != land || oldDelegate.background != background;
}
