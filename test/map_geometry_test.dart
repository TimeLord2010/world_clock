import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/city.dart';
import 'package:world_clock/city_markers.dart';
import 'package:world_clock/map_geometry.dart';
import 'package:world_clock/world_dot_map.dart';

/// A ida e a volta entre o pixel do mapa e a coordenada do mundo: é o que faz um
/// clique significar um lugar.
void main() {
  const mapSize = Size(1200, 600);

  group('unproject', () {
    test('é a inversa exata de normalize', () {
      for (var lon = -180.0; lon <= 180.0; lon += 7.5) {
        for (var lat = -90.0; lat <= 90.0; lat += 7.5) {
          final back = WorldDotMap.unproject(WorldDotMap.normalize(lon, lat));
          expect(back.dx, closeTo(lon, 1e-9), reason: 'lon $lon');
          expect(back.dy, closeTo(lat, 1e-9), reason: 'lat $lat');
        }
      }
    });

    test('o centro do mapa é o ponto (0, 0)', () {
      final geo = WorldDotMap.unproject(const Offset(0.5, 0.5));

      expect(geo.dx, closeTo(0, 1e-9));
      expect(geo.dy, closeTo(0, 1e-9));
    });

    test('os cantos do quadrado unitário são os cantos do mundo', () {
      expect(WorldDotMap.unproject(Offset.zero), const Offset(-180, 90));
      expect(WorldDotMap.unproject(const Offset(1, 0)), const Offset(180, 90));
      expect(
        WorldDotMap.unproject(const Offset(0, 1)),
        const Offset(-180, -90),
      );
      expect(WorldDotMap.unproject(const Offset(1, 1)), const Offset(180, -90));
    });

    test('fora do quadrado, a coordenada é presa ao mundo', () {
      // Um clique meio ponto fora da borda não pode virar lon 180,03.
      final past = WorldDotMap.unproject(const Offset(1.2, -0.3));

      expect(past.dx, 180);
      expect(past.dy, 90);
    });
  });

  group('clique vira coordenada', () {
    test('o centro do mapa é o (0, 0)', () {
      final point = MapPoint.at(const Offset(600, 300), mapSize);

      expect(point.latitude, closeTo(0, 1e-9));
      expect(point.longitude, closeTo(0, 1e-9));
    });

    test('os cantos do mapa são os cantos do mundo', () {
      final topLeft = MapPoint.at(Offset.zero, mapSize);
      final bottomRight = MapPoint.at(
        Offset(mapSize.width, mapSize.height),
        mapSize,
      );

      expect(topLeft.latitude, closeTo(90, 1e-9));
      expect(topLeft.longitude, closeTo(-180, 1e-9));
      expect(bottomRight.latitude, closeTo(-90, 1e-9));
      expect(bottomRight.longitude, closeTo(180, 1e-9));
    });

    test('um pixel conhecido dá a coordenada conhecida', () {
      // Fortaleza, arredondada à grade de 1°: (-38,5, -3,5) cai no pixel
      // ((180-38,5)/360 · 1200, (90+3,5)/180 · 600).
      final point = MapPoint.at(const Offset(471.667, 311.667), mapSize);

      expect(point.longitude, closeTo(-38.5, 0.01));
      expect(point.latitude, closeTo(-3.5, 0.01));
    });

    test('coordenada fora do mapa é presa ao mundo', () {
      final point = MapPoint.at(const Offset(-50, 900), mapSize);

      expect(point.longitude, -180);
      expect(point.latitude, -90);
    });

    test('layout degenerado não vira NaN', () {
      // Largura/altura zero acontecem num primeiro quadro ou numa janela
      // minimizada. Sem guarda, a divisão daria NaN e o ponto iria parar em
      // lugar nenhum — muito depois, longe da causa.
      for (final size in [Size.zero, const Size(-10, 20)]) {
        final point = MapPoint.at(const Offset(5, 5), size);
        expect(point.latitude.isNaN, isFalse, reason: '$size');
        expect(point.longitude.isNaN, isFalse, reason: '$size');
        expect(point.latitude, inInclusiveRange(-90, 90));
        expect(point.longitude, inInclusiveRange(-180, 180));
      }
    });

    test('ida e volta: clicar e reprojetar cai no mesmo pixel', () {
      for (final local in const [
        Offset(0, 0),
        Offset(17, 43),
        Offset(600, 300),
        Offset(1199, 599),
        Offset(1000, 120),
      ]) {
        final point = MapPoint.at(local, mapSize);
        final back = point.offsetIn(mapSize);

        expect(back.dx, closeTo(local.dx, 0.01), reason: '$local');
        expect(back.dy, closeTo(local.dy, 0.01), reason: '$local');
      }
    });

    test('o ponto clicado cai no mesmo pixel que os outros marcadores', () {
      // Mesma coordenada, três marcadores: o ponto clicado, a cidade e o
      // usuário têm de coincidir. Se alguém trocar a projeção de um lado só, é
      // este teste que quebra.
      final fortaleza = City(
        id: '1',
        name: 'Fortaleza',
        region: 'Ceará',
        countryCode: 'BR',
        latitude: -3.748,
        longitude: -38.582,
        timeZoneId: 'America/Fortaleza',
        population: 3602319,
      );
      final point = MapPoint(
        latitude: fortaleza.latitude,
        longitude: fortaleza.longitude,
      );

      expect(
        point.offsetIn(mapSize),
        CityMarkers.offsetFor(fortaleza, mapSize),
      );
    });
  });
}
