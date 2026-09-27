import 'dart:async';

import 'package:flutter/material.dart';

import 'map_theme.dart';
import 'settings_menu.dart';
import 'world_dot_map.dart';

void main() {
  runApp(const WorldClockApp());
}

class WorldClockApp extends StatelessWidget {
  const WorldClockApp({super.key});

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
      home: const WorldMapScreen(),
    );
  }
}

class WorldMapScreen extends StatefulWidget {
  const WorldMapScreen({super.key});

  @override
  State<WorldMapScreen> createState() => _WorldMapScreenState();
}

class _WorldMapScreenState extends State<WorldMapScreen> {
  DateTime _now = DateTime.now();
  Timer? _ticker;

  /// Tema em uso. Só o menu o muda; a escolha vive na sessão (não é
  /// persistida entre execuções ainda).
  MapTheme _theme = MapThemes.standard;

  @override
  void initState() {
    super.initState();
    // Keep the day/night boundary moving: refresh the reference instant
    // every 30 minutes (the sun moves ~7.5° of longitude in that window,
    // clearly visible on screen; per-minute updates are imperceptible).
    _ticker = Timer.periodic(const Duration(minutes: 30), (_) {
      setState(() => _now = DateTime.now());
    });
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
            // RepaintBoundary: o mapa tem dezenas de milhares de pontos e é
            // irmão do menu na mesma Stack. Sem esta fronteira, CADA rebuild do
            // menu (abrir, trocar de opção, destacar uma linha) invalida a
            // camada e repinta o mapa inteiro — era isso que travava a tela no
            // hover. Com ela, o menu repinta só a si mesmo.
            Positioned.fill(
              child: RepaintBoundary(
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
                        child: WorldDotMap(
                          now: _now,
                          backgroundColor: _theme.background,
                          dotColor: _theme.land,
                          oceanColor: _theme.ocean,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // O menu fica por cima do mapa: ele mesmo desenha a barreira de
            // "clicou fora, fechou".
            Positioned.fill(
              child: SettingsMenu(
                theme: _theme,
                onThemeSelected: (theme) => setState(() => _theme = theme),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
