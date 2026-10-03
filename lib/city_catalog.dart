import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart' show rootBundle;

import 'city.dart';
import 'search_text.dart';

/// O catálogo de cidades (`assets/cities.json`) e a busca sobre ele.
///
/// O asset é lido UMA vez por execução e o `Future` fica cacheado — mesmo
/// contrato de `WorldDotMap.loadData()`: chamar [load] de novo não relê 581 KB
/// nem reparseia 7.341 linhas.
abstract final class CityCatalog {
  /// Caminho do asset. Constante nomeada porque o teste do catálogo e o próprio
  /// carregador precisam do MESMO caminho.
  static const String assetPath = 'assets/cities.json';

  /// O catálogo, em ordem de população (a ordem já vem do asset).
  static Future<List<City>> load() => _cities;

  static final Future<List<City>> _cities = _parse();

  static Future<List<City>> _parse() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('$assetPath não é um objeto JSON');
    }

    // O asset declara a ordem dos próprios campos. Conferir contra `City.fields`
    // é o que impede um asset regenerado com outra ordem de trocar latitude por
    // longitude em silêncio — o erro aparece na primeira abertura, não num
    // ponto errado no mapa.
    final declared = (decoded['fields'] as List?)?.cast<String>() ?? const [];
    if (!listEquals(declared, City.fields)) {
      throw FormatException(
        '$assetPath declara os campos $declared, esperado ${City.fields}. '
        'Regenere com `dart run tool/build_cities.dart <geojson>`.',
      );
    }

    final rows = decoded['cities'] as List? ?? const [];
    return [
      for (final row in rows) City.fromList((row as List).cast<Object?>()),
    ];
  }

  /// As cidades que casam com [query], das mais relevantes para as menos.
  ///
  /// Consulta vazia devolve o catálogo inteiro (já em ordem de população), que
  /// é o que o picker mostra antes de o usuário digitar qualquer coisa.
  ///
  /// A ordem é por RELEVÂNCIA, não só por população: um nome que COMEÇA com a
  /// consulta vem antes de um que só a contém, e ambos antes de um que casou
  /// pela região/país. Assim "for" traz Fortaleza antes de "Sanfor" — e uma
  /// cidade pequena procurada pelo nome exato não fica soterrada por uma
  /// metrópole que só contém as letras.
  static List<City> search(List<City> cities, String query) {
    final needle = foldForSearch(query.trim());
    if (needle.isEmpty) {
      return List<City>.of(cities);
    }

    final scored = <(int, City)>[];
    for (final city in cities) {
      final int rank;
      if (city.foldedName.startsWith(needle)) {
        rank = 0;
      } else if (city.foldedName.contains(needle)) {
        rank = 1;
      } else if (city.foldedContext.contains(needle)) {
        rank = 2;
      } else {
        continue;
      }
      scored.add((rank, city));
    }
    scored.sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      return byRank != 0 ? byRank : b.$2.population.compareTo(a.$2.population);
    });
    return [for (final entry in scored) entry.$2];
  }
}
