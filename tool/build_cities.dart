// Gerador do catálogo de cidades (`assets/cities.json`).
//
// A ENTRADA é o GeoJSON oficial do Natural Earth — `ne_10m_populated_places`,
// 7.342 lugares, DOMÍNIO PÚBLICO, da mesma família de dados de que saiu o
// `assets/world_dots.json`. A entrada NÃO é versionada (19 MB); a saída É.
//
// O Natural Earth TAMBÉM traz um campo `TIMEZONE` (id IANA) por lugar — e ele
// é a razão de este script existir. O campo está CORROMPIDO: medido contra os
// polígonos do Timezone Boundary Builder e contra a API do Open-Meteo como
// terceira fonte, ele dá `Europe/Athens` para Lagos, `America/Chicago` para
// Praga, `Australia/Sydney` para Cardiff, `America/Fortaleza` para Macau e
// `America/Sao_Paulo` para Santiago. São 86 lugares com offset REALMENTE
// errado (não só nome antigo) — inclusive cidades de milhões de habitantes.
//
// Por isso o fuso vem SEMPRE dos polígonos (Timezone Boundary Builder), que
// ganharam 13 dos 14 casos adjudicados por uma terceira fonte independente; o
// 14º era o polígono sendo mais NOVO que a terceira fonte (a zona
// `America/Coyhaique`, criada na tzdb 2025b, que o Open-Meteo ainda não tem).
// O campo do Natural Earth entra apenas como DIAGNÓSTICO no relatório, nunca
// como resposta: onde ele não concordar com o polígono, quem está certo é o
// polígono.
//
// Uso:
//   dart run tool/build_cities.dart <caminho>/ne_10m_populated_places.geojson
//
// O script é DETERMINÍSTICO (nenhum carimbo de data na saída): rodar duas vezes
// sobre a mesma entrada tem de produzir bytes idênticos.

import 'dart:convert';
import 'dart:io';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone_finder/timezone_finder.dart';

/// Procedência gravada no asset: quem consome sabe de onde veio o dado.
///
/// A versão dos polígonos entra no rótulo de propósito: ela é independente da
/// versão da tzdb (regras de offset) e é o que diz QUANDO as fronteiras dos
/// fusos foram medidas. Sem isso, um fuso errado no asset não teria como ser
/// rastreado até a versão do dado.
///
/// A atribuição dos polígonos é obrigatória pela licença ODbL deles (ver o
/// README): "© OpenStreetMap contributors, ODbL".
String _sourceLabel() =>
    'Natural Earth 5.1.2 ne_10m_populated_places (dominio publico) + '
    'Timezone Boundary Builder $boundaryDataVersion (poligonos, '
    '(c) OpenStreetMap contributors, ODbL)';

/// Ordem dos campos de cada registro em `cities`. Gravada no próprio asset
/// (`fields`), para o arquivo se explicar sem precisar deste script.
const List<String> _fields = [
  'name',
  'adm1',
  'country',
  'lat',
  'lon',
  'tz',
  'population',
  'id',
];

/// Casas decimais das coordenadas. Três casas ~110 m — muito abaixo da célula
/// de 1° do mapa, então não há perda visível.
const int _coordDecimals = 3;

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('uso: dart run tool/build_cities.dart <geojson>');
    exitCode = 64;
    return;
  }

  final input = File(args.single);
  if (!input.existsSync()) {
    stderr.writeln('entrada não encontrada: ${input.path}');
    exitCode = 66;
    return;
  }

  tzdata.initializeTimeZones();

  final root = jsonDecode(await input.readAsString()) as Map<String, dynamic>;
  final features = root['features'] as List<dynamic>;

  final cities = <_City>[];
  var naturalEarthEmpty = 0;
  var naturalEarthAgrees = 0;
  var skippedNoCoord = 0;
  var skippedNoZone = 0;
  final unresolved = <String>[];
  final divergences = <String, int>{};
  final seenIds = <String, String>{};
  final duplicateIds = <String>[];

  for (final feature in features) {
    final properties =
        (feature as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
    final latitude = (properties['LATITUDE'] as num?)?.toDouble();
    final longitude = (properties['LONGITUDE'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      skippedNoCoord++;
      continue;
    }

    final name = _text(properties['NAME_PT']).isEmpty
        ? _text(properties['NAME'])
        : _text(properties['NAME_PT']);
    if (name.isEmpty) {
      skippedNoZone++;
      unresolved.add('(sem nome) $latitude, $longitude');
      continue;
    }

    // O polígono responde "que zona contém ESTE ponto" — é a ÚNICA fonte da
    // resposta. O campo `TIMEZONE` do Natural Earth entra apenas como
    // diagnóstico (ver o cabeçalho): está corrompido e nunca decide nada.
    final zone = _zoneAt(longitude, latitude);
    final naturalEarthZone = _text(properties['TIMEZONE']);
    if (naturalEarthZone.isEmpty) {
      naturalEarthEmpty++;
    } else if (zone != null) {
      if (naturalEarthZone == zone) {
        naturalEarthAgrees++;
      } else {
        final key = '$naturalEarthZone -> $zone';
        divergences[key] = (divergences[key] ?? 0) + 1;
      }
    }

    if (zone == null || !_zoneExists(zone)) {
      // Nenhum polígono cobre o ponto (ilha minúscula fora da faixa costeira de
      // ~22 km), ou o id não existe na tzdb que o app vai carregar. O lugar sai
      // do catálogo: melhor faltar a cidade do que gravar um fuso vazio — no
      // app, `tz.getLocation('')` lança — ou um palpite do campo corrompido do
      // Natural Earth.
      skippedNoZone++;
      unresolved.add('$name ($latitude, $longitude)');
      continue;
    }

    final id = _text(properties['NE_ID']);
    if (id.isNotEmpty) {
      final previous = seenIds[id];
      if (previous != null) {
        duplicateIds.add('$id: $previous / $name');
        continue;
      }
      seenIds[id] = name;
    }

    cities.add(
      _City(
        name: name,
        adm1: _text(properties['ADM1NAME']),
        country: _country(properties['ISO_A2']),
        latitude: latitude,
        longitude: longitude,
        timeZoneId: zone,
        population: (properties['POP_MAX'] as num?)?.toInt() ?? 0,
        id: id,
      ),
    );
  }

  // Ordem: população desc. O picker mostra os maiores primeiro e a busca é
  // estável entre execuções.
  cities.sort((a, b) {
    final byPopulation = b.population.compareTo(a.population);
    return byPopulation != 0 ? byPopulation : a.name.compareTo(b.name);
  });

  final output = File('assets/cities.json');
  await output.writeAsString(
    jsonEncode({
      'version': 1,
      'source': _sourceLabel(),
      'fields': _fields,
      'cities': [for (final city in cities) city.toJson()],
    }),
  );

  _report(
    cities: cities.length,
    total: features.length,
    naturalEarthEmpty: naturalEarthEmpty,
    naturalEarthAgrees: naturalEarthAgrees,
    skippedNoCoord: skippedNoCoord,
    skippedNoZone: skippedNoZone,
    unresolved: unresolved,
    divergences: divergences,
    duplicateIds: duplicateIds,
    output: output,
  );
}

/// Fuso do ponto, ou nulo quando nenhum polígono cobre a coordenada (oceano
/// aberto, ilha fora da faixa costeira). Nunca lança: uma coordenada estranha
/// no dataset não pode derrubar a geração inteira.
String? _zoneAt(double longitude, double latitude) {
  try {
    return findLocation(longitude, latitude)?.name;
  } catch (error) {
    stderr.writeln('polígono falhou em $latitude, $longitude: $error');
    return null;
  }
}

/// Se o id realmente existe na tzdb que o app vai carregar (`latest_all`, com
/// os links). Sem esta checagem, um id que só existe como link poderia entrar
/// no asset e explodir em `tz.getLocation` na primeira abertura.
bool _zoneExists(String zoneId) {
  try {
    tz.getLocation(zoneId);
    return true;
  } catch (_) {
    return false;
  }
}

/// Texto de um campo do GeoJSON, já aparado (o dataset tem muitos espaços).
///
/// Aceita número além de String porque `NE_ID` — a identidade estável que o
/// app persiste — vem como inteiro no JSON, não como texto. Recusar número
/// aqui deixava o id de TODAS as cidades vazio em silêncio, e aí o catálogo
/// não tinha como ser persistido.
String _text(Object? value) => switch (value) {
  final String text => text.trim(),
  final num number => number.toString(),
  _ => '',
};

/// País em ISO 3166-1 alfa-2. O dataset marca lugares sem país reconhecido
/// (disputados, dependências) como `-99`; para esses o campo fica vazio e o
/// app sabe não mostrar país nenhum.
String _country(Object? value) {
  final code = _text(value).toUpperCase();
  return code == '-99' ? '' : code;
}

void _report({
  required int cities,
  required int total,
  required int naturalEarthEmpty,
  required int naturalEarthAgrees,
  required int skippedNoCoord,
  required int skippedNoZone,
  required List<String> unresolved,
  required Map<String, int> divergences,
  required List<String> duplicateIds,
  required File output,
}) {
  final bytes = output.lengthSync();
  stdout
    ..writeln('${output.path}: $cities cidades '
        '(${(bytes / 1024).toStringAsFixed(0)} KB)')
    ..writeln('  features na entrada        : $total')
    ..writeln('  fuso pelo polígono (TZBB)  : $cities')
    ..writeln('  descartados (sem polígono) : $skippedNoZone')
    ..writeln('  sem coordenada             : $skippedNoCoord')
    ..writeln('  --- diagnóstico do campo TIMEZONE do Natural Earth ---')
    ..writeln('  vazio                      : $naturalEarthEmpty')
    ..writeln('  concorda com o polígono    : $naturalEarthAgrees')
    ..writeln('  DIVERGE (campo não confiável, ignorado) : '
        '${divergences.values.fold(0, (sum, count) => sum + count)}');

  if (duplicateIds.isNotEmpty) {
    stderr.writeln('  IDs duplicados (${duplicateIds.length}):');
    for (final line in duplicateIds.take(20)) {
      stderr.writeln('    $line');
    }
  }

  if (unresolved.isNotEmpty) {
    stderr.writeln('  SEM FUSO (${unresolved.length}):');
    for (final line in unresolved.take(40)) {
      stderr.writeln('    $line');
    }
  }

  if (divergences.isNotEmpty) {
    final total = divergences.values.fold(0, (sum, count) => sum + count);
    stderr.writeln(
      '  onde o campo do Natural Earth divergiu do polígono '
      '($total lugares — o polígono é quem vale):',
    );
    final ordered = divergences.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in ordered.take(30)) {
      stderr.writeln('    ${entry.value.toString().padLeft(4)}  ${entry.key}');
    }
  }
}

/// Um lugar do catálogo, no formato posicional de `cities` (ver [_fields]).
class _City {
  const _City({
    required this.name,
    required this.adm1,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.timeZoneId,
    required this.population,
    required this.id,
  });

  final String name;
  final String adm1;
  final String country;
  final double latitude;
  final double longitude;
  final String timeZoneId;
  final int population;
  final String id;

  List<Object> toJson() => [
    name,
    adm1,
    country,
    double.parse(latitude.toStringAsFixed(_coordDecimals)),
    double.parse(longitude.toStringAsFixed(_coordDecimals)),
    timeZoneId,
    population,
    id,
  ];
}
