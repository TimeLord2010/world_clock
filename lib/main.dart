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
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7DD3FC),
          brightness: Brightness.dark,
        ),
      ),
      home: const WorldMapScreen(),
    );
  }
}

class WorldMapScreen extends StatelessWidget {
  const WorldMapScreen({super.key});

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
                child: const WorldDotMap(),
              ),
            );
          },
        ),
      ),
    );
  }
}
