import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'city.dart';
import 'city_catalog.dart';
import 'panel_card.dart';

/// O painel de cidades: buscar no catálogo, salvar/retirar e fixar o horário.
///
/// Substitui o painel de opções enquanto está aberto (ver `SettingsMenu`), em
/// vez de abrir ao lado dele: são 300 pt de painel, e manter as opções visíveis
/// ao lado empurraria os dois para fora da janela numa janela estreita. O
/// cabeçalho tem a seta de voltar.
///
/// **A largura aqui é FIXA, ao contrário do resto dos painéis.** O `PanelCard`
/// dimensiona pelo conteúdo (`IntrinsicWidth`), o que funciona para rótulos mas
/// não para uma caixa de texto: vazia, ela tem largura intrínseca quase nula e o
/// painel colapsaria a cada busca. A largura fixa é o que dá à `TextField` e à
/// lista um chão. O preço é o corte por reticências nos nomes longos — corte
/// DELIBERADO, e por isso o painel do mapa (que se dimensiona pelo conteúdo)
/// continua sem cortar nada.
class CityPicker extends StatefulWidget {
  const CityPicker({
    super.key,
    required this.cities,
    required this.savedIds,
    required this.onToggleSaved,
    required this.onBack,
    required this.background,
  });

  /// O catálogo inteiro. Vazio enquanto ele não chegou (a busca espera).
  final List<City> cities;

  /// Ids das cidades salvas hoje (aparecem com o check).
  final Set<String> savedIds;

  /// Chamado com o id da cidade quando ela deve ser salva ou retirada.
  final ValueChanged<String> onToggleSaved;

  /// Fecha o painel e volta para o painel de opções.
  final VoidCallback onBack;

  /// Fundo do TEMA em uso: o cartão é esse fundo um degrau mais claro, como
  /// todos os outros painéis (ver [PanelCard.cardColor]).
  final Color background;

  /// Largura do painel, em pontos.
  static const double panelWidth = 300;

  /// Altura da lista, em pontos.
  ///
  /// A lista PRECISA de altura limitada: o `PanelCard` é uma `Column` dentro de
  /// um `IntrinsicWidth`, e uma `ListView` sem altura definida ali é erro de
  /// layout em tempo de execução.
  static const double listHeight = 260;

  /// Altura de cada linha da lista. Fixa porque as duas linhas de texto (nome e
  /// contexto) são sempre duas, com ou sem acento e em qualquer cidade — e uma
  /// lista de 7 mil itens com altura fixa é bem mais barata de rolar.
  static const double rowHeight = 46;

  @override
  State<CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<CityPicker> {
  final TextEditingController _controller = TextEditingController();

  List<City> _results = const <City>[];

  @override
  void initState() {
    super.initState();
    _results = CityCatalog.search(widget.cities, '');
  }

  @override
  void didUpdateWidget(covariant CityPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // O catálogo chega DEPOIS do painel abrir (é assíncrono). Sem isto, quem
    // abrisse o painel antes da hora ficaria com a lista vazia para sempre.
    if (!identical(oldWidget.cities, widget.cities)) {
      _results = CityCatalog.search(widget.cities, _controller.text);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Refaz a busca. Roda uma vez por TECLA, e não a cada quadro: a lista de
  /// resultados fica guardada no estado, então o `build` não varre 7.341
  /// cidades toda vez que o menu se redesenha.
  void _search(String query) {
    setState(() => _results = CityCatalog.search(widget.cities, query));
  }

  @override
  Widget build(BuildContext context) {
    // A janela pode ser mais estreita que o painel (janela pequena, tela de
    // celular): encolhe em vez de estourar o layout.
    final width = math.min(
      CityPicker.panelWidth,
      MediaQuery.sizeOf(context).width - 32,
    );

    return PanelCard(
      background: widget.background,
      children: [
        SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              _field(),
              Divider(height: 1, thickness: 1, color: PanelCard.hairline),
              SizedBox(height: CityPicker.listHeight, child: _list()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            color: PanelCard.textColor,
            tooltip: 'Voltar',
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              'Cidades',
              style: TextStyle(fontSize: 13, color: PanelCard.textColor),
            ),
          ),
          Text(
            '${widget.savedIds.length} salva'
            '${widget.savedIds.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, color: PanelCard.dimTextColor),
          ),
        ],
      ),
    );
  }

  Widget _field() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        controller: _controller,
        onChanged: _search,
        style: TextStyle(fontSize: 13, color: PanelCard.textColor),
        cursorColor: PanelCard.textColor,
        cursorWidth: 1,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'Buscar cidade',
          hintStyle: TextStyle(fontSize: 13, color: PanelCard.dimTextColor),
          prefixIcon: Icon(
            Icons.search,
            size: 16,
            color: PanelCard.dimTextColor,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 22),
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
        ),
      ),
    );
  }

  Widget _list() {
    // Três estados diferentes, e cada um diz a verdade: o catálogo ainda não
    // chegou, a busca não achou nada, ou aqui estão os resultados.
    if (widget.cities.isEmpty) {
      return _emptyState('Carregando o catálogo…');
    }
    if (_results.isEmpty) {
      return _emptyState('Nenhuma cidade encontrada');
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemExtent: CityPicker.rowHeight,
      itemBuilder: (context, index) => _row(_results[index]),
    );
  }

  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: PanelCard.dimTextColor),
      ),
    );
  }

  /// Uma cidade na lista: nome e contexto à esquerda, o check à direita.
  ///
  /// A LINHA INTEIRA salva/retira (é o gesto óbvio e o alvo grande). O
  /// `Expanded` no meio é o que faz o nome longo ser cortado com reticências em
  /// vez de empurrar o check para fora do painel.
  Widget _row(City city) {
    final saved = widget.savedIds.contains(city.id);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onToggleSaved(city.id),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(
                saved ? Icons.check_circle : Icons.add_circle_outline,
                size: 16,
                color: saved ? PanelCard.textColor : PanelCard.dimTextColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      city.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: PanelCard.textColor,
                      ),
                    ),
                    if (city.contextLabel.isNotEmpty)
                      Text(
                        city.contextLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: PanelCard.dimTextColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
