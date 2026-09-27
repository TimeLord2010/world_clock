import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'map_theme.dart';

/// Bandeja de opções fixada no canto superior direito da tela.
///
/// Ocupa a tela inteira para poder desenhar a barreira que fecha o menu (um
/// clique fora dele), mas só o ícone no canto e os painéis que abre recebem
/// clique. Hoje a bandeja tem uma opção só — "Tema" — que abre o submenu com
/// os temas disponíveis.
///
/// **Só clique abre**: o menu não reage a hover. Hover aqui era um tiro no pé —
/// cada movimento do ponteiro virava um `setState`, e como o mapa é irmão da
/// bandeja na mesma camada, cada rebuild repintava o mapa inteiro (dezenas de
/// mil pontos), o que na prática travava a tela e fazia o menu fechar sozinho
/// quando o layout mudava embaixo do ponteiro. Fecha ao clicar fora, ao clicar
/// no próprio ícone ou com Esc.
class SettingsMenu extends StatefulWidget {
  const SettingsMenu({
    super.key,
    required this.theme,
    required this.onThemeSelected,
    this.themes = MapThemes.all,
  });

  /// Tema em uso hoje: marca a opção selecionada e aparece no item "Tema".
  final MapTheme theme;

  /// Temas oferecidos pelo submenu.
  final List<MapTheme> themes;

  /// Chamado quando o usuário escolhe um tema no submenu.
  final ValueChanged<MapTheme> onThemeSelected;

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  /// Menu de primeiro nível visível.
  bool _open = false;

  /// Submenu de "Tema" visível.
  bool _themeSubmenu = false;

  void _toggleMenu() => setState(() {
    _open = !_open;
    _themeSubmenu = false;
  });

  void _closeAll() {
    if (!_open) {
      return;
    }
    setState(() {
      _open = false;
      _themeSubmenu = false;
    });
  }

  void _toggleSubmenu() => setState(() => _themeSubmenu = !_themeSubmenu);

  void _pick(MapTheme theme) {
    widget.onThemeSelected(theme);
    _closeAll();
  }

  /// Cor do cartão dos painéis: o fundo do tema um degrau mais claro — assim a
  /// bandeja acompanha o tema em vez de ter cor própria.
  Color get _cardColor => Color.alphaBlend(
    Colors.white.withValues(alpha: 0.07),
    widget.theme.background,
  );

  static final Color _hairline = Colors.white.withValues(alpha: 0.14);
  static final Color _textColor = Colors.white.withValues(alpha: 0.92);
  static final Color _dimTextColor = Colors.white.withValues(alpha: 0.55);

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _closeAll},
      child: Focus(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Barreira: fecha o menu. Fica ANTES da bandeja no Stack, então a
            // bandeja continua recebendo os cliques por cima dela.
            if (_open)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeAll,
              ),
            Positioned(
              top: 4,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_open && _themeSubmenu)
                    Padding(
                      padding: const EdgeInsets.only(top: 14, right: 8),
                      child: _themePanel(),
                    ),
                  if (_open)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: _optionsPanel(),
                    ),
                  _menuButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleMenu,
      child: MouseRegion(
        // cursor só: nenhum estado, nenhum abre/fecha — o ponteiro vira a mão
        // sobre o ícone.
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _open ? _cardColor : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _open ? _hairline : Colors.transparent),
          ),
          child: Icon(Icons.menu, size: 20, color: _textColor),
        ),
      ),
    );
  }

  /// Menu de primeiro nível: hoje só "Tema", que abre o submenu.
  Widget _optionsPanel() {
    return _panel(
      children: [
        _row(
          onTap: _toggleSubmenu,
          highlighted: _themeSubmenu,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.palette_outlined, size: 16, color: _textColor),
              const SizedBox(width: 10),
              Text('Tema', style: TextStyle(fontSize: 13, color: _textColor)),
              const SizedBox(width: 24),
              // O tema em uso aparece aqui, em miniatura, para o menu dizer o
              // estado atual sem precisar abrir o submenu.
              ThemeSwatch(colors: widget.theme.swatch, size: 14),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 16, color: _dimTextColor),
            ],
          ),
        ),
      ],
    );
  }

  /// Submenu do "Tema": uma linha por tema, cada uma com as duas cores do tema
  /// no círculo, e depois o nome.
  Widget _themePanel() {
    return _panel(
      children: [
        for (final theme in widget.themes)
          _row(
            onTap: () => _pick(theme),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ThemeSwatch(colors: theme.swatch, size: 18),
                const SizedBox(width: 10),
                Text(
                  theme.label,
                  style: TextStyle(fontSize: 13, color: _textColor),
                ),
                const SizedBox(width: 16),
                // A opção em uso fica com o check; as outras reservam o mesmo
                // espaço para os nomes ficarem alinhados.
                Icon(
                  Icons.check,
                  size: 16,
                  color: theme.id == widget.theme.id
                      ? _textColor
                      : Colors.transparent,
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Painel: a largura sai do CONTEÚDO ([IntrinsicWidth]), nunca de uma
  /// constante — o painel fica do tamanho da linha mais larga e nenhum nome de
  /// tema é cortado, seja qual for a fonte (no `flutter test` a fonte default
  /// desenha 1 em por caractere, então largura fixa lá vira reticências).
  Widget _panel({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // Stretch: todas as linhas ficam com a largura da mais larga, então
          // os checks ficam alinhados à direita.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _row({
    required Widget child,
    VoidCallback? onTap,
    bool highlighted = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        // cursor só: nenhum estado.
        cursor: SystemMouseCursors.click,
        child: Container(
          color: highlighted ? Colors.white.withValues(alpha: 0.10) : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: child,
        ),
      ),
    );
  }
}

/// Círculo com as duas cores do tema: a primeira na metade de cima, a segunda
/// na metade de baixo, divididas por uma linha horizontal de largura
/// [dividerWidth] — no padrão 0, as duas metades simplesmente se tocam e
/// nenhuma linha é desenhada.
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({
    super.key,
    required this.colors,
    this.size = 18,
    this.dividerWidth = 0,
  });

  /// As duas cores do tema, na ordem: em cima, embaixo.
  final List<Color> colors;

  /// Diâmetro do círculo, em pontos.
  final double size;

  /// Largura da linha que divide as duas metades (0 = sem linha visível).
  final double dividerWidth;

  @override
  Widget build(BuildContext context) {
    assert(colors.length == 2, 'o swatch mostra exatamente duas cores');
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ThemeSwatchPainter(
          colors: colors,
          dividerWidth: dividerWidth,
        ),
      ),
    );
  }
}

class _ThemeSwatchPainter extends CustomPainter {
  const _ThemeSwatchPainter({required this.colors, required this.dividerWidth});

  final List<Color> colors;
  final double dividerWidth;

  /// Anel fino de contorno: sem ele o swatch some no fundo escuro do painel.
  static const double _ring = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()..isAntiAlias = true;

    // Círculo inteiro na primeira cor…
    canvas.drawCircle(center, radius, paint..color = colors.first);

    // …e a metade de baixo repintada na segunda: o mesmo círculo recortado no
    // semicírculo inferior dá exatamente a metade de baixo, sem cunha e sem
    // costura — a divisão é a linha horizontal de largura zero entre as duas.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, center.dy, size.width, size.height));
    canvas.drawCircle(center, radius, paint..color = colors.last);
    canvas.restore();

    if (dividerWidth > 0) {
      canvas.drawLine(
        Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy),
        Paint()
          ..strokeWidth = dividerWidth
          ..color = Colors.black.withValues(alpha: 0.55),
      );
    }

    canvas.drawCircle(
      center,
      radius - _ring / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _ring
        ..color = Colors.white.withValues(alpha: 0.28),
    );
  }

  @override
  bool shouldRepaint(covariant _ThemeSwatchPainter oldDelegate) {
    return oldDelegate.dividerWidth != dividerWidth ||
        !listEquals(oldDelegate.colors, colors);
  }
}
