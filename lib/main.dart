import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'map_theme.dart';
import 'moon_marker.dart';
import 'moon_position.dart';
import 'settings_menu.dart';
import 'user_location.dart';
import 'user_marker.dart';
import 'world_dot_map.dart';

void main() {
  runApp(const WorldClockApp());
}

class WorldClockApp extends StatelessWidget {
  const WorldClockApp({
    super.key,
    this.locationLookup = UserLocationResolver.resolve,
  });

  /// Como a tela descobre a posição do usuário — repassado para
  /// [WorldMapScreen.locationLookup]; os testes trocam por uma resposta fixa e
  /// assim não dependem de rede nem de permissão.
  final Future<UserLocation> Function() locationLookup;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'World Clock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF111111),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF9800),
          brightness: Brightness.dark,
        ),
      ),
      home: WorldMapScreen(locationLookup: locationLookup),
    );
  }
}

class WorldMapScreen extends StatefulWidget {
  const WorldMapScreen({
    super.key,
    this.locationLookup = UserLocationResolver.resolve,
  });

  /// Como descobrir a posição do usuário. Injetável para os testes rodarem sem
  /// rede nem permissão (o padrão é a resolução de verdade).
  final Future<UserLocation> Function() locationLookup;

  @override
  State<WorldMapScreen> createState() => _WorldMapScreenState();
}

class _WorldMapScreenState extends State<WorldMapScreen> {
  DateTime _now = DateTime.now();

  /// Lua no instante [_now]: recalculada junto com o Sol, no mesmo tique.
  MoonStatus _moon = MoonPosition.at(DateTime.now());

  Timer? _ticker;

  /// Tema em uso. Só o menu o muda; a escolha vive na sessão (não é
  /// persistida entre execuções ainda).
  MapTheme _theme = MapThemes.standard;

  /// Onde o usuário está, quando o sistema (ou o IP) responde. Nulo enquanto a
  /// consulta não voltou — a tela abre sem o ponto e ele entra quando chega,
  /// sem prender a abertura do app.
  UserLocation? _location;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshLocation());
    // Keep the day/night boundary moving: refresh the reference instant
    // every 15 minutes (the sun moves ~3.75° of longitude in that window,
    // clearly visible on screen; per-minute updates are imperceptible).
    _ticker = Timer.periodic(const Duration(minutes: 15), (_) {
      setState(() {
        _now = DateTime.now();
        // A Lua anda ~0,14° em 15 min — menos de 1 px no mapa, então o mesmo
        // tique serve para ela. Se um dia quiser movimento contínuo, o
        // marcador está FORA do RepaintBoundary do mapa: dá para atualizá-lo
        // sozinho, sem repintar os pontos.
        _moon = MoonPosition.at(_now);
      });
      // O Mac não sai do lugar, mas a RESPOSTA pode mudar: quem negou a
      // permissão e depois autorizou só ganha o ponto porque este tique
      // pergunta de novo. Uma consulta a cada 15 min é barata (a posição do
      // sistema vem do cache do Wi-Fi, o IP é uma requisição curta).
      unawaited(_refreshLocation());
    });
  }

  /// Pergunta a posição e publica o resultado. Falha não é silenciosa: o
  /// motivo vai para a linha da bandeja (ver `SettingsMenu.locationNotice`) e
  /// fica registrado no log — sem isso, "o ponto não apareceu" é indistinguível
  /// de "a consulta quebrou".
  Future<void> _refreshLocation() async {
    final location = await widget.locationLookup();
    if (kDebugMode) {
      debugPrint('[localização] $location');
    }
    if (!mounted) {
      return;
    }
    setState(() => _location = location);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _theme.background,
      body: SafeArea(
        child: Stack(
          children: [
            // The map keeps its 2:1 equirectangular aspect: it fills the width
            // in portrait and the height in landscape.
            //
            // RepaintBoundary (dentro do Stack do mapa): o mapa tem dezenas de
            // milhares de pontos e era irmão do menu na mesma camada. Sem a
            // fronteira, CADA rebuild do menu (abrir, trocar de opção, destacar
            // uma linha) invalidava a camada e repintava o mapa inteiro — era
            // isso que travava a tela no hover. Com ela, o menu repinta só a si
            // mesmo, e a Lua também.
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mapWidth =
                      constraints.maxWidth < constraints.maxHeight * 2
                      ? constraints.maxWidth
                      : constraints.maxHeight * 2;
                  return Center(
                    child: SizedBox(
                      width: mapWidth,
                      height: mapWidth / 2,
                      child: Stack(
                        // Clip.none: o overlay da Lua pode passar da borda do
                        // mapa quando ela está colada no limite (é o Stack de
                        // fora, da tela, que acaba recortando).
                        clipBehavior: Clip.none,
                        children: [
                          // O RepaintBoundary envolve SÓ os pontos do mapa. A Lua
                          // é irmã dele no Stack: um tique da Lua — ou o hover no
                          // marcador — não invalida a camada do mapa (dezenas de
                          // milhares de pontos). O pintor dos pontos segue
                          // recebendo os mesmos dados, então nem o rebuild do
                          // hover faz o mapa repintar.
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: WorldDotMap(
                                now: _now,
                                backgroundColor: _theme.background,
                                dotColor: _theme.land,
                                oceanColor: _theme.ocean,
                              ),
                            ),
                          ),
                          // Positioned.fill: o marcador se posiciona sozinho (e o
                          // overlay junto), porque a posição depende do tamanho
                          // do mapa em pontos.
                          Positioned.fill(
                            child: MoonMarker(
                              status: _moon,
                              mapSize: Size(mapWidth, mapWidth / 2),
                              background: _theme.background,
                            ),
                          ),
                          // O ponto do usuário fica DEPOIS do marcador da Lua no
                          // Stack, ou seja, por cima: se os dois caírem no mesmo
                          // lugar, quem não pode sumir é o "você está aqui".
                          // Como o marcador da Lua, ele mora fora do
                          // RepaintBoundary dos pontos.
                          Positioned.fill(
                            child: UserMarker(
                              location: _location,
                              mapSize: Size(mapWidth, mapWidth / 2),
                              land: _theme.land,
                              background: _theme.background,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // O menu fica por cima do mapa: ele mesmo desenha a barreira de
            // "clicou fora, fechou". Os dados da Lua não estão aqui — aparecem
            // no overlay do marcador, dentro do mapa. A localização aparece
            // SÓ quando não há posição: aí a linha diz o motivo (sem ela, um
            // ponto que não surge seria uma falha silenciosa).
            Positioned.fill(
              child: SettingsMenu(
                theme: _theme,
                onThemeSelected: (theme) => setState(() => _theme = theme),
                locationNotice: _location?.notice,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
