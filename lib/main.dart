import 'dart:async';

import 'package:flutter/material.dart';

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
          seedColor: const Color(0xFFFE6D34),
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
      body: SafeArea(
        // The map keeps its 2:1 equirectangular aspect: it fills the width
        // in portrait and the height in landscape.
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
                child: WorldDotMap(now: _now),
              ),
            );
          },
        ),
      ),
    );
  }
}
