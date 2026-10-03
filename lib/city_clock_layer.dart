import 'dart:async';

import 'package:flutter/material.dart';

import 'city_clock.dart';
import 'clicked_point.dart';
import 'city_markers.dart';

/// A camada das cidades: segura o instante e o ticker do relógio.
///
/// O estado do relógio mora AQUI, e não no `WorldMapScreen`, de propósito: um
/// tique de minuto não pode reconstruir a tela inteira (o mapa, o menu e o
/// resto) só para trocar dois dígitos num cartão. É a mesma razão pela qual o
/// hover do `MoonMarker` vive dentro dele — e, como a camada é irmã do
/// `RepaintBoundary` dos pontos, o tique nem chega perto dos pontos do mapa.
///
/// **Tem de ser filho direto de um `Stack`** com `clipBehavior: Clip.none`:
/// quem se posiciona é o [CityMarkers] daqui de dentro, e o overlay pode passar
/// da borda do mapa.
class CityClockLayer extends StatefulWidget {
  const CityClockLayer({
    super.key,
    required this.cities,
    required this.mapSize,
    required this.land,
    required this.background,
    this.selectedId,
    this.pinnedIds = const <String>{},
    this.onSelect,
    this.clickedPoint,
    this.clock = DateTime.now,
  });

  /// As cidades a desenhar, com o fuso de cada uma já resolvido.
  final List<CityClock> cities;

  /// Tamanho do retângulo do mapa, em pontos.
  final Size mapSize;

  final Color land;
  final Color background;

  /// A cidade com o overlay aberto por clique.
  final String? selectedId;

  /// As cidades com o overlay preso aberto ("sempre visível").
  final Set<String> pinnedIds;

  /// Chamado com o id da cidade quando o disco dela é clicado.
  final ValueChanged<String>? onSelect;

  /// O ponto consultado no mapa (ver [ClickedPoint]), quando há um. A camada só
  /// o repassa: quem resolve o ponto é a tela, que tem o resolver e a geração do
  /// clique.
  final ClickedPoint? clickedPoint;

  /// De onde vem "agora". Injetável pelos mesmos motivos de
  /// `WorldDotMap(now:)`: um widget que lê o relógio do sistema por conta
  /// própria não tem como ser testado numa hora fixa.
  ///
  /// Devolve a hora LOCAL do aparelho — e é o mesmo valor que serve de
  /// referência para o "+1 dia" do overlay, porque um `DateTime` local É um
  /// instante e É o relógio de parede de quem olha.
  final DateTime Function() clock;

  /// Folga depois da virada do minuto, em milissegundos.
  ///
  /// Um timer pode disparar um fio ANTES do instante pedido. Sem folga, o tique
  /// cairia ainda dentro do minuto velho, o texto não mudaria e o relógio
  /// ficaria UM MINUTO INTEIRO atrasado — o pior tipo de erro num relógio,
  /// porque parece funcionar.
  static const int tickCushionMs = 50;

  @override
  State<CityClockLayer> createState() => _CityClockLayerState();
}

/// Quanto falta para a próxima virada de minuto, com a folga de
/// [CityClockLayer.tickCushionMs].
Duration untilNextMinute(DateTime now) => Duration(
  seconds: 60 - now.second,
  milliseconds: CityClockLayer.tickCushionMs - now.millisecond,
);

class _CityClockLayerState extends State<CityClockLayer> {
  /// O instante mostrado. Não é `widget.clock()` chamado no `build`: o
  /// `build` tem de desenhar sempre o MESMO instante, e não um novo a cada
  /// reconstrução (o que faria o minuto mudar no meio de um frame).
  late DateTime _now;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _now = widget.clock();
    _scheduleTick();
  }

  /// Reagenda para a próxima virada de minuto.
  ///
  /// Auto-reagendado em vez de `Timer.periodic(1 s)`: assim há UM rebuild por
  /// minuto (e não 60), e ele cai no instante em que o minuto vira — não até 59
  /// segundos depois, que é o atraso visível de um `periodic` de um minuto.
  void _scheduleTick() {
    _ticker = Timer(untilNextMinute(_now), _tick);
  }

  void _tick() {
    if (!mounted) {
      return;
    }
    setState(() => _now = widget.clock());
    _scheduleTick();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CityMarkers(
      cities: widget.cities,
      mapSize: widget.mapSize,
      now: _now,
      // O mesmo instante: um `DateTime` local já É o relógio de parede de quem
      // olha, e é dele que sai o "+1 dia".
      here: _now,
      land: widget.land,
      background: widget.background,
      selectedId: widget.selectedId,
      pinnedIds: widget.pinnedIds,
      onSelect: widget.onSelect,
      clickedPoint: widget.clickedPoint,
    );
  }
}
