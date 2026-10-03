import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:world_clock/city.dart';
import 'package:world_clock/city_catalog.dart';
import 'package:world_clock/map_geometry.dart';
import 'package:world_clock/place_lookup.dart';

/// O que se sabe de um ponto clicado: o fuso vem SEMPRE offline, o nome é um
/// extra que pode faltar — e nunca é inventado.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<City> catalog;
  late OfflinePlaceLookup offline;

  setUpAll(() async {
    tzdata.initializeTimeZones();
    catalog = await CityCatalog.load();
    offline = OfflinePlaceLookup(catalog: catalog);
  });

  /// Fortaleza, o exemplo do usuário.
  const fortaleza = MapPoint(latitude: -3.748, longitude: -38.582);

  /// Um ponto de TERRA dentro do raio de nome, mas longe o bastante para o nome
  /// ser aproximado: 180,6 km de Djanet, no sudeste da Argélia.
  const nearDjanet = MapPoint(latitude: 23, longitude: 10);

  /// Um ponto de TERRA longe de qualquer cidade do catálogo: 410,9 km de
  /// Kaltukatjara, no interior da Austrália.
  const outback = MapPoint(latitude: -25, longitude: 125);

  group('fuso (offline, sempre)', () {
    test('em terra, vem do polígono do TZBB', () async {
      final info = await offline.resolve(fortaleza);

      expect(info.location.name, 'America/Fortaleza');
    });

    test('em oceano aberto, vem da faixa náutica', () async {
      // Medido contra o Open-Meteo: em (0, −30) a resposta é `Etc/GMT+2`, que é
      // UTC−2 (o sinal POSIX invertido).
      final info = await offline.resolve(
        const MapPoint(latitude: 0, longitude: -30),
      );

      expect(info.location.name, 'Etc/GMT+2');
      expect(info.location.zones.first.offset, const Duration(hours: -2));
    });

    test('responde em qualquer canto do mapa, sem exceção', () async {
      for (final point in const [
        MapPoint(latitude: 0, longitude: 0),
        MapPoint(latitude: 89, longitude: 0),
        MapPoint(latitude: -89, longitude: 0),
        MapPoint(latitude: 90, longitude: 180),
        MapPoint(latitude: -90, longitude: -180),
        MapPoint(latitude: 35.687, longitude: 139.749),
      ]) {
        final info = await offline.resolve(point);
        expect(info.location.name, isNotEmpty, reason: '$point');
        expect(() => info.location, returnsNormally);
      }
    });
  });

  group('nome', () {
    test('em cima da cidade, o nome é o do lugar (sem ressalva)', () async {
      final info = await offline.resolve(fortaleza);

      expect(info.name, 'Fortaleza');
      expect(info.country, 'Brasil');
      expect(info.approximate, isFalse);
      expect(info.distanceKm, lessThan(1));
    });

    test('a 180 km, o nome é o da cidade mais próxima — e DIZ que é', () async {
      // Djanet (Argélia) está a 180,6 km. Apresentar "Djanet" sem ressalva para
      // um clique a 180 km seria mentira; por isso a distância e a marca de
      // aproximado saem junto, e o overlay escreve "≈ Djanet".
      final info = await offline.resolve(nearDjanet);

      expect(info.name, 'Djanet');
      expect(info.country, 'Argélia');
      expect(info.approximate, isTrue);
      expect(info.distanceKm, closeTo(180.6, 2));
    });

    test('em terra longe de qualquer cidade, NÃO inventa nome', () async {
      final info = await offline.resolve(outback);

      expect(info.name, isNull);
      expect(info.country, isNull);
      expect(info.location.name, isNotEmpty, reason: 'a hora continua saindo');
    });

    test('em oceano aberto, NÃO inventa nome', () async {
      // Medido: em (0, −30) a terra mais próxima do catálogo é Natal, a 866 km.
      final info = await offline.resolve(
        const MapPoint(latitude: 0, longitude: -30),
      );

      expect(info.name, isNull);
    });
  });

  group('resposta do serviço de nomes', () {
    test('prefere a localidade à região metropolitana', () {
      // Medido: para Fortaleza o serviço devolve `locality: "Fortaleza"` e
      // `city: "Região Metropolitana de Fortaleza"`. Preferir o segundo poria o
      // nome da região no lugar do nome da cidade.
      final name = BigDataCloudNameLookup.parseName(
        jsonEncode({
          'locality': 'Fortaleza',
          'city': 'Região Metropolitana de Fortaleza',
          'principalSubdivision': 'Ceará',
          'countryName': 'Brasil',
        }),
      );

      expect(name?.locality, 'Fortaleza');
      expect(name?.region, 'Ceará');
      expect(name?.country, 'Brasil');
    });

    test('cai na cidade quando não há localidade', () {
      final name = BigDataCloudNameLookup.parseName(
        jsonEncode({'locality': '', 'city': 'Pequim', 'countryName': 'China'}),
      );

      expect(name?.locality, 'Pequim');
      expect(name?.region, isNull);
    });

    test('país vazio significa "não sei onde é" — e não vira nome', () {
      // Medido: em oceano aberto o serviço devolve a terra mais próxima
      // (a 100 km!) com o país VAZIO. Aceitar isso batizaria o mar com o nome
      // de uma ilha.
      final name = BigDataCloudNameLookup.parseName(
        jsonEncode({
          'locality': 'Monumento Natural do Arquipélago de São Pedro',
          'countryName': '',
        }),
      );

      expect(name, isNull);
    });

    test('resposta ilegível ou sem nome não estoura', () {
      for (final body in ['', 'não é json', '[]', '{}', '{"locality":"X"}']) {
        expect(
          BigDataCloudNameLookup.parseName(body),
          isNull,
          reason: 'corpo: $body',
        );
      }
    });
  });

  group('consulta de nomes na rede', () {
    late HttpServer server;
    late int hits;
    late HttpOverrides? savedOverrides;

    setUp(() async {
      // O flutter_test instala um `HttpOverrides` que responde 400 a TUDO, para
      // nenhum teste tocar a rede de verdade. Aqui a rede É o objeto do teste —
      // e ela é um servidor LOCAL, na interface de loopback: desligar o override
      // é o que permite exercitar o caminho HTTP (montagem da URL, leitura da
      // resposta, cache) sem sair da máquina.
      savedOverrides = HttpOverrides.current;
      HttpOverrides.global = null;

      hits = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        hits++;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'locality': 'Fortaleza',
              'principalSubdivision': 'Ceará',
              'countryName': 'Brasil',
            }),
          );
        await request.response.close();
      });
    });

    tearDown(() async {
      HttpOverrides.global = savedOverrides;
      await server.close(force: true);
    });

    BigDataCloudNameLookup lookupOn() => BigDataCloudNameLookup(
      endpoint: Uri.parse(
        'http://${server.address.address}:${server.port}/reverse',
      ),
    );

    test('lê o nome pela rede de verdade', () async {
      final name = await lookupOn().lookup(fortaleza);

      expect(name?.locality, 'Fortaleza');
      expect(name?.country, 'Brasil');
      expect(hits, 1);
    });

    test('cliques vizinhos saem do cache, sem segunda requisição', () async {
      final lookup = lookupOn();

      await lookup.lookup(fortaleza);
      // 0,1° ao lado: mesma célula de 0,25°.
      await lookup.lookup(const MapPoint(latitude: -3.8, longitude: -38.6));

      expect(hits, 1, reason: 'cliques vizinhos não repetem a requisição');
      expect(lookup.requestCount, 1);
    });

    test('longe o bastante, consulta de novo', () async {
      final lookup = lookupOn();

      await lookup.lookup(fortaleza);
      await lookup.lookup(const MapPoint(latitude: 10, longitude: 10));

      expect(hits, 2);
    });

    test('servidor fora do ar devolve nulo, sem exceção', () async {
      // Porta fechada: é o que acontece sem internet.
      final lookup = BigDataCloudNameLookup(
        endpoint: Uri.parse('http://127.0.0.1:1/reverse'),
        timeout: const Duration(milliseconds: 300),
      );

      expect(await lookup.lookup(fortaleza), isNull);
    });

    test('resposta de erro HTTP devolve nulo', () async {
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        hits++;
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      });

      expect(await lookupOn().lookup(fortaleza), isNull);
    });
  });

  group('distância', () {
    test('o mesmo ponto dá zero', () {
      expect(distanceKm(-3.748, -38.582, -3.748, -38.582), 0);
    });

    test('Fortaleza–São Paulo bate com a referência (2.365,5 km)', () {
      expect(distanceKm(-3.748, -38.582, -23.55, -46.63), closeTo(2365.5, 1));
    });

    test('não usa a diferença em graus', () {
      // Dois pontos a 10° de longitude: ~1.100 km no Equador e ~550 km a 60°N.
      // Tratar grau como distância fixa erraria o nome apresentado nas
      // latitudes altas — justamente onde o catálogo tem vazios.
      final atEquator = distanceKm(0, 0, 0, 10);
      final atSixty = distanceKm(60, 0, 60, 10);

      expect(atEquator, closeTo(1112, 5));
      expect(atSixty, closeTo(556, 5));
      expect(atSixty, lessThan(atEquator / 1.9));
    });
  });
}
