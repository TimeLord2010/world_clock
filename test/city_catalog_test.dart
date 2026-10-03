import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/city.dart';
import 'package:world_clock/city_catalog.dart';
import 'package:world_clock/country_names.dart';
import 'package:world_clock/search_text.dart';

/// O catálogo de cidades: o asset carrega, vem íntegro e a busca acha o que o
/// usuário digita — inclusive sem acento.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('catálogo', () {
    test('carrega o asset uma vez só', () async {
      final first = await CityCatalog.load();
      final second = await CityCatalog.load();

      expect(first.length, greaterThan(7000), reason: 'catálogo completo');
      expect(
        identical(first, second),
        isTrue,
        reason: 'a segunda chamada não pode reler nem reparsear o asset',
      );
    });

    test('toda cidade tem id único, coordenada no mundo e fuso', () async {
      final cities = await CityCatalog.load();
      final ids = <String>{};

      for (final city in cities) {
        expect(city.id, isNotEmpty);
        expect(ids.add(city.id), isTrue, reason: 'id repetido: ${city.id}');
        expect(city.name, isNotEmpty);
        expect(city.latitude, inInclusiveRange(-90, 90));
        expect(city.longitude, inInclusiveRange(-180, 180));
        expect(
          city.timeZoneId,
          isNotEmpty,
          reason: 'fuso vazio quebraria tz.getLocation na abertura',
        );
      }
    });

    test('todo código de país do catálogo tem nome em português', () async {
      final cities = await CityCatalog.load();
      final codes = {
        for (final city in cities)
          if (city.countryCode.isNotEmpty) city.countryCode,
      };

      expect(codes.length, greaterThan(200));
      for (final code in codes) {
        expect(
          countryNamesPtBr[code],
          isNotNull,
          reason: 'sem nome pt-BR para "$code" — o overlay mostraria o código',
        );
      }
    });

    test('vem ordenado por população, do maior para o menor', () async {
      final cities = await CityCatalog.load();

      for (var i = 1; i < cities.length; i++) {
        expect(
          cities[i - 1].population,
          greaterThanOrEqualTo(cities[i].population),
          reason: 'fora de ordem em ${cities[i].name}',
        );
      }
    });

    test('a procedência e a atribuição viajam dentro do asset', () async {
      // A licença dos polígonos (ODbL) exige atribuição: ela mora no `source`
      // do próprio asset, e um asset regerado sem ela tem de quebrar aqui.
      final raw = jsonDecode(await rootBundle.loadString(CityCatalog.assetPath));
      final decoded = raw as Map<String, dynamic>;

      expect(decoded['version'], 1);
      expect(decoded['fields'], City.fields);
      final source = decoded['source'] as String;
      expect(source, contains('Natural Earth'));
      expect(source, contains('OpenStreetMap'));
      expect(source, contains('ODbL'));
    });

    test('Fortaleza está lá, com o fuso do Ceará e o país em português',
        () async {
      final cities = await CityCatalog.load();
      final fortaleza = cities.firstWhere(
        (city) => city.name == 'Fortaleza' && city.region == 'Ceará',
      );

      expect(fortaleza.countryCode, 'BR');
      expect(fortaleza.countryName, 'Brasil');
      expect(fortaleza.timeZoneId, 'America/Fortaleza');
      expect(fortaleza.contextLabel, 'Ceará, Brasil');
      expect(fortaleza.latitude, closeTo(-3.748, 0.01));
      expect(fortaleza.longitude, closeTo(-38.582, 0.01));
    });
  });

  group('dobra para busca', () {
    test('tira o acento e baixa a caixa', () {
      expect(foldForSearch('São Paulo'), 'sao paulo');
      expect(foldForSearch('Tóquio'), 'tokio');
      expect(foldForSearch('Zürich'), 'zurich');
      expect(foldForSearch('Łódź'), 'lodz');
      expect(foldForSearch('Reykjavík'), 'reykjavik');
      expect(foldForSearch('Brașov'), 'brasov');
      expect(foldForSearch('sem acento'), 'sem acento');
      expect(foldForSearch(''), '');
    });

    test('"qu" vira "k": a grafia e a pronúncia têm de casar', () {
      // Medido no catálogo: 138 nomes têm `qu` e a troca não cria colisão nova.
      expect(foldForSearch('Iorque'), 'iorke');
      expect(foldForSearch('Quebec'), foldForSearch('Kebec'));
      expect(foldForSearch('qu'), foldForSearch('k'));
    });
  });

  group('busca', () {
    late List<City> cities;

    setUp(() async {
      cities = await CityCatalog.load();
    });

    test('consulta vazia devolve o catálogo inteiro, em ordem', () {
      expect(CityCatalog.search(cities, '').length, cities.length);
      expect(CityCatalog.search(cities, '   ').length, cities.length);
      expect(CityCatalog.search(cities, '').first.id, cities.first.id);
    });

    test('acha sem acento e com acento', () {
      for (final query in ['sao paulo', 'São Paulo', 'SAO PAULO']) {
        final first = CityCatalog.search(cities, query).first;
        expect(first.name, 'São Paulo', reason: 'consulta "$query"');
      }
    });

    test('acha "Tóquio" digitando "tokio"', () {
      // O caso que a dobra de dígrafo resolve: quem digita não escreve "qu".
      for (final query in ['tóquio', 'toquio', 'tokio', 'Tokio']) {
        final found = CityCatalog.search(cities, query);
        expect(
          found.any((city) => city.name == 'Tóquio'),
          isTrue,
          reason: 'consulta "$query" devia achar Tóquio',
        );
      }
    });

    test('acha Fortaleza pelo nome, pela região e pelo país', () {
      bool hasFortaleza(List<City> found) => found.any(
        (city) => city.name == 'Fortaleza' && city.region == 'Ceará',
      );

      expect(hasFortaleza(CityCatalog.search(cities, 'fortaleza')), isTrue);
      expect(hasFortaleza(CityCatalog.search(cities, 'ceara')), isTrue);
      expect(hasFortaleza(CityCatalog.search(cities, 'brasil')), isTrue);
    });

    test('nome que COMEÇA com a consulta vem antes de um que só a contém', () {
      // Relevância, não só população: sem isso uma metrópole que apenas contém
      // as letras soterra a cidade que o usuário está digitando.
      final found = CityCatalog.search(cities, 'for');
      final firstRank0 = found.indexWhere(
        (city) => city.foldedName.startsWith('for'),
      );
      final firstOther = found.indexWhere(
        (city) => !city.foldedName.startsWith('for'),
      );

      expect(found.first.foldedName, startsWith('for'));
      if (firstRank0 >= 0 && firstOther >= 0) {
        expect(firstRank0, lessThan(firstOther));
      }
    });

    test('cidades homônimas aparecem as duas, distinguíveis pelo contexto', () {
      final found = CityCatalog.search(
        cities,
        'sydney',
      ).where((city) => city.name == 'Sydney').toList();

      expect(found.length, greaterThanOrEqualTo(2), reason: 'Austrália e Canadá');
      expect(
        found.map((city) => city.countryCode).toSet(),
        containsAll(<String>{'AU', 'CA'}),
      );
      // A maior primeiro (Austrália), e a linha de contexto é o que separa uma
      // da outra na lista.
      expect(found.first.countryCode, 'AU');
      expect(found.map((city) => city.contextLabel).toSet().length, found.length);
    });

    test('consulta que não casa com nada devolve vazio', () {
      expect(CityCatalog.search(cities, 'zzzzzzzz'), isEmpty);
    });

    test('a lista devolvida é cópia: mexer nela não corrompe o catálogo', () {
      final found = CityCatalog.search(cities, '');
      found.clear();
      expect(cities, isNotEmpty);
    });
  });

  group('linha malformada', () {
    List<Object?> row({
      Object? id = '1',
      Object? tz = 'America/Fortaleza',
      Object? lat = -3.748,
      Object? lon = -38.582,
    }) => ['Fortaleza', 'Ceará', 'BR', lat, lon, tz, 3602319, id];

    test('monta a cidade quando a linha está completa', () {
      final city = City.fromList(row());

      expect(city.id, '1');
      expect(city.name, 'Fortaleza');
      expect(city.timeZoneId, 'America/Fortaleza');
    });

    test('linha com número de campos errado falha alto', () {
      expect(() => City.fromList(['Fortaleza']), throwsFormatException);
    });

    test('id vazio falha alto (quebraria a persistência)', () {
      expect(() => City.fromList(row(id: '')), throwsFormatException);
    });

    test('fuso vazio falha alto (quebraria tz.getLocation)', () {
      expect(() => City.fromList(row(tz: '')), throwsFormatException);
    });

    test('coordenada ausente ou fora do mundo falha alto', () {
      expect(() => City.fromList(row(lat: null)), throwsFormatException);
      expect(() => City.fromList(row(lon: null)), throwsFormatException);
      expect(() => City.fromList(row(lat: 120)), throwsFormatException);
      expect(() => City.fromList(row(lon: 200)), throwsFormatException);
    });
  });
}
