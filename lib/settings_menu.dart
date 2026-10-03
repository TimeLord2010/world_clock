import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'city.dart';
import 'city_picker.dart';
import 'map_theme.dart';
import 'panel_card.dart';

/// Bandeja de opções fixada no canto superior direito da tela.
///
/// Ocupa a tela inteira para poder desenhar a barreira que fecha o menu (um
/// clique fora dele), mas só o ícone no canto e os painéis que abre recebem
/// clique. A bandeja tem a opção "Tema" — que abre o submenu com os temas
/// disponíveis —, a opção "Incluir crepúsculo" (uma caixinha que liga/desliga a
/// espera pelo crepúsculo no mapa, ver [WorldDotMap.includeTwilight]), a opção
/// "Manter tela ligada" (outra caixinha: segura a tela acesa enquanto o app
/// está aberto, ver `KeepAwake`), a opção "Cidades" (que abre o [CityPicker]) e,
/// quando não há posição do usuário, uma LINHA DE MOTIVO (ver
/// [locationNotice]). Os dados da Lua NÃO moram aqui: eles aparecem no overlay
/// que abre com o ponteiro em cima do marcador no mapa (`MoonMarker`).
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
    required this.includeTwilight,
    required this.onTwilightChanged,
    this.keepScreenOn = false,
    this.onKeepScreenOnChanged,
    this.keepAwakeNotice,
    this.themes = MapThemes.all,
    this.locationNotice,
    this.cities = const <City>[],
    this.savedCityIds = const <String>{},
    this.pinnedCityIds = const <String>{},
    this.onCityToggled,
    this.onCityPinToggled,
  });

  /// Tema em uso hoje: marca a opção selecionada e aparece no item "Tema".
  final MapTheme theme;

  /// Temas oferecidos pelo submenu.
  final List<MapTheme> themes;

  /// Chamado quando o usuário escolhe um tema no submenu.
  final ValueChanged<MapTheme> onThemeSelected;

  /// Estado da opção "Incluir crepúsculo": com ela ligada, a noite do mapa
  /// só chega no fim do crepúsculo civil (ver [WorldDotMap.includeTwilight]).
  /// O estado mora na tela ([WorldMapScreen]) — a bandeja só mostra a
  /// caixinha e avisa o clique.
  final bool includeTwilight;

  /// Chamado com o NOVO valor quando o usuário clica na linha do crepúsculo.
  final ValueChanged<bool> onTwilightChanged;

  /// Estado da opção "Manter tela ligada": ligada = o app segura a tela acesa
  /// enquanto estiver aberto (ver `KeepAwake`). O estado mora na tela
  /// ([WorldMapScreen]).
  final bool keepScreenOn;

  /// Chamado com o NOVO valor quando o usuário clica na linha da tela.
  ///
  /// **Nulo ESCONDE a linha**, de propósito: sem uma implementação de
  /// `KeepAwake` injetada não há quem segure a tela, e uma caixinha que alterna
  /// sozinha sem efeito nenhum seria a pior das mentiras (o usuário acharia a
  /// opção ligada e o monitor apagaria do mesmo jeito).
  final ValueChanged<bool>? onKeepScreenOnChanged;

  /// Por que a tela não está sendo mantida acesa, quando o pedido falhou (o
  /// macOS pode negar a assertion). Nulo no caminho normal. É uma linha de
  /// DADOS, não de opção: sem clique, sem cursor de mão — mas ela existe, senão
  /// a falha seria indistinguível de "a opção não funciona".
  final String? keepAwakeNotice;

  /// Por que não há ponto do usuário no mapa (`UserLocation.notice`). Nulo
  /// quando há posição — e aí a bandeja não fala de localização, porque o ponto
  /// no mapa já é a resposta. É uma linha de DADOS, não uma opção: sem clique,
  /// sem cursor de mão.
  final String? locationNotice;

  /// O catálogo de cidades que o painel "Cidades" oferece. Vazio enquanto ele
  /// não chegou (o painel mostra "Carregando o catálogo…").
  final List<City> cities;

  /// Ids das cidades salvas hoje — a bandeja mostra a contagem na linha.
  final Set<String> savedCityIds;

  /// Ids das cidades com o horário sempre visível.
  final Set<String> pinnedCityIds;

  /// Chamado com o id da cidade quando ela deve ser salva ou retirada. Nulo
  /// (o padrão) desliga a ação — os testes que só olham o menu não precisam
  /// saber de cidades.
  final ValueChanged<String>? onCityToggled;

  /// Chamado com o id da cidade quando o "sempre visível" dela vira.
  final ValueChanged<String>? onCityPinToggled;

  @override
  State<SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<SettingsMenu> {
  /// Menu de primeiro nível visível.
  bool _open = false;

  /// Submenu de "Tema" visível.
  bool _themeSubmenu = false;

  /// Painel de "Cidades" visível.
  ///
  /// Ele SUBSTITUI o painel de opções em vez de abrir ao lado (como o submenu
  /// de tema faz): são 300 pt de painel, e manter as opções ao lado empurraria
  /// os dois para fora da janela numa janela estreita.
  bool _citiesPanel = false;

  void _toggleMenu() => setState(() {
    _open = !_open;
    _themeSubmenu = false;
    _citiesPanel = false;
  });

  void _closeAll() {
    if (!_open) {
      return;
    }
    setState(() {
      _open = false;
      _themeSubmenu = false;
      _citiesPanel = false;
    });
  }

  void _toggleSubmenu() => setState(() {
    _themeSubmenu = !_themeSubmenu;
    _citiesPanel = false;
  });

  void _toggleCitiesPanel() => setState(() {
    _citiesPanel = !_citiesPanel;
    _themeSubmenu = false;
  });

  /// Volta do painel de cidades para o de opções, sem fechar o menu.
  void _leaveCitiesPanel() => setState(() => _citiesPanel = false);

  void _pick(MapTheme theme) {
    widget.onThemeSelected(theme);
    _closeAll();
  }

  /// Cor do cartão dos painéis: o fundo do tema um degrau mais claro — assim a
  /// bandeja acompanha o tema em vez de ter cor própria.
  Color get _cardColor => PanelCard.cardColor(widget.theme.background);

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
                  if (_open && !_citiesPanel)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: _optionsPanel(),
                    ),
                  if (_open && _citiesPanel)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: _citiesPanelWidget(),
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
            border: Border.all(
              color: _open ? PanelCard.hairline : Colors.transparent,
            ),
          ),
          child: Icon(Icons.menu, size: 20, color: PanelCard.textColor),
        ),
      ),
    );
  }

  /// Menu de primeiro nível: a opção "Tema" (paletas), as caixinhas "Incluir
  /// crepúsculo" e "Manter tela ligada", a opção "Cidades" (com a contagem de
  /// salvas) e, quando a posição do usuário não veio, a linha com o motivo. Os
  /// dados da Lua não entram aqui — eles moram no overlay do marcador, no mapa.
  Widget _optionsPanel() {
    return PanelCard(
      background: widget.theme.background,
      children: [
        _row(
          onTap: _toggleSubmenu,
          highlighted: _themeSubmenu,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.palette_outlined,
                size: 16,
                color: PanelCard.textColor,
              ),
              const SizedBox(width: 10),
              Text(
                'Tema',
                style: TextStyle(fontSize: 13, color: PanelCard.textColor),
              ),
              const SizedBox(width: 24),
              // O tema em uso aparece aqui, em miniatura, para o menu dizer o
              // estado atual sem precisar abrir o submenu.
              ThemeSwatch(colors: widget.theme.swatch, size: 14),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: PanelCard.dimTextColor,
              ),
            ],
          ),
        ),
        _checkRow(
          onTap: () => widget.onTwilightChanged(!widget.includeTwilight),
          icon: Icons.wb_twilight,
          label: 'Incluir crepúsculo',
          checked: widget.includeTwilight,
        ),
        // As duas opções de liga/desliga do painel (crepúsculo e tela) têm a
        // MESMA forma: ícone, rótulo e a caixinha à direita, na coluna alinhada
        // com o rabo da linha "Tema".
        if (widget.onKeepScreenOnChanged case final onKeepScreenOnChanged?)
          _checkRow(
            onTap: () => onKeepScreenOnChanged(!widget.keepScreenOn),
            icon: Icons.lightbulb_outline,
            label: 'Manter tela ligada',
            checked: widget.keepScreenOn,
          ),
        if (widget.keepAwakeNotice case final keepAwakeNotice?)
          _noticeRow(icon: Icons.error_outline, text: keepAwakeNotice),
        _row(
          onTap: _toggleCitiesPanel,
          highlighted: _citiesPanel,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.public, size: 16, color: PanelCard.textColor),
              const SizedBox(width: 10),
              Text(
                'Cidades',
                style: TextStyle(fontSize: 13, color: PanelCard.textColor),
              ),
              const SizedBox(width: 24),
              // Contador: diz quantas cidades estão salvas sem precisar abrir o
              // painel. Mesma coluna à direita das outras linhas (o rabo do
              // "Tema" e a caixinha do crepúsculo têm 36 pt), para os controles
              // ficarem alinhados.
              SizedBox(
                width: 36,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${widget.savedCityIds.length}',
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.savedCityIds.isEmpty
                          ? PanelCard.dimTextColor
                          : PanelCard.textColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.locationNotice case final notice?)
          _noticeRow(icon: Icons.location_off_outlined, text: notice),
      ],
    );
  }

  /// Linha de opção com a caixinha de estado à direita (as duas opções de
  /// liga/desliga do painel usam esta): cheia = ligado.
  ///
  /// A coluna da direita tem a MESMA largura do rabo da linha "Tema" (swatch +
  /// seta = 36 pt), para os controles das linhas ficarem alinhados numa coluna
  /// só.
  Widget _checkRow({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required bool checked,
  }) {
    return _row(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: PanelCard.textColor),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: PanelCard.textColor),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 36,
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(
                checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16,
                color: checked ? PanelCard.textColor : PanelCard.dimTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Linha de motivo (não de opção): mesmo recuo horizontal dos itens, sem o
  /// vertical de linha clicável. Existe para nenhuma falha ficar muda — sem
  /// ela, "o ponto não apareceu" e "a tela vai apagar do mesmo jeito" são
  /// indistinguíveis de "está tudo certo".
  Widget _noticeRow({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: PanelCard.dimTextColor),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(fontSize: 13, color: PanelCard.dimTextColor),
          ),
        ],
      ),
    );
  }

  /// O painel de "Cidades": busca, salva/retira e fixa o horário.
  ///
  /// Os callbacks são repassados como opcionais porque a bandeja pode ser
  /// montada sem eles (os testes de tema e de crepúsculo não têm cidades): sem
  /// handler, clicar na linha simplesmente não faz nada, em vez de estourar.
  Widget _citiesPanelWidget() {
    return CityPicker(
      cities: widget.cities,
      savedIds: widget.savedCityIds,
      pinnedIds: widget.pinnedCityIds,
      onToggleSaved: (id) => widget.onCityToggled?.call(id),
      onTogglePinned: (id) => widget.onCityPinToggled?.call(id),
      onBack: _leaveCitiesPanel,
      background: widget.theme.background,
    );
  }

  /// Submenu do "Tema": uma linha por tema, cada uma com as duas cores do tema
  /// no círculo, e depois o nome.
  Widget _themePanel() {
    return PanelCard(
      background: widget.theme.background,
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
                  style: TextStyle(fontSize: 13, color: PanelCard.textColor),
                ),
                const SizedBox(width: 16),
                // A opção em uso fica com o check; as outras reservam o mesmo
                // espaço para os nomes ficarem alinhados.
                Icon(
                  Icons.check,
                  size: 16,
                  color: theme.id == widget.theme.id
                      ? PanelCard.textColor
                      : Colors.transparent,
                ),
              ],
            ),
          ),
      ],
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
