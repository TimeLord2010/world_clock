import 'package:flutter/foundation.dart' show immutable;

import 'country_names.dart';
import 'search_text.dart';

/// Uma cidade do catálogo (`assets/cities.json`).
///
/// O catálogo é a FONTE DOS DADOS das cidades salvas: a persistência guarda só
/// o [id], e tudo o mais (nome, coordenada, fuso) é lido daqui. Assim, regenerar
/// o catálogo com dados melhores não exige migrar o que o usuário já escolheu.
///
/// O construtor NÃO é `const`: [foldedName] e [foldedContext] são memoizados na
/// primeira leitura, e uma classe com construtor `const` não admite campo
/// `late final`. O `const` não faria falta de qualquer forma — as cidades
/// nascem do JSON, em tempo de execução, e nunca de um literal.
@immutable
class City {
  City({
    required this.id,
    required this.name,
    required this.region,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    required this.timeZoneId,
    required this.population,
  });

  /// Ordem dos campos de cada linha de `cities` no asset.
  ///
  /// Mora AQUI, e não no catálogo, porque é o formato que [fromList] lê: assim
  /// não há como os dois lados discordarem em silêncio. `CityCatalog` confere
  /// que o `fields` declarado dentro do asset é exatamente esta lista — um
  /// asset regenerado com outra ordem falha alto, em vez de trocar latitude
  /// por longitude.
  static const List<String> fields = [
    'name',
    'adm1',
    'country',
    'lat',
    'lon',
    'tz',
    'population',
    'id',
  ];

  /// Identidade estável do lugar (o `NE_ID` do Natural Earth). É o que a
  /// persistência grava e o que reencontra a cidade depois — o nome NÃO serve:
  /// existem duas "Sydney" no catálogo (Austrália e Nova Escócia).
  final String id;

  /// Nome do lugar em português (`NAME_PT` do Natural Earth, com o `NAME` como
  /// reserva): "Tóquio", "Lisboa", "Nova Iorque".
  final String name;

  /// Estado, província ou região (`ADM1NAME`), como vem do Natural Earth —
  /// frequentemente em inglês ("New South Wales"). Serve para DESAMBIGUAR
  /// homônimas, não para exibir bonito. Vazio em 118 lugares.
  final String region;

  /// País em ISO 3166-1 alfa-2 (`ISO_A2`). Vazio nos 12 lugares que o Natural
  /// Earth marca como sem país reconhecido.
  final String countryCode;

  /// Coordenada do centro do lugar, em graus.
  final double latitude;
  final double longitude;

  /// Fuso IANA da cidade, já RESOLVIDO (ex.: `America/Fortaleza`).
  ///
  /// Vem pronto no asset: o app não tem polígonos de fuso em runtime. O valor
  /// é sempre um id que existe na tzdb que o app carrega — o gerador descarta
  /// o lugar que não conseguir resolver (ver `tool/build_cities.dart`).
  final String timeZoneId;

  /// População da área metropolitana (`POP_MAX`), usada para ordenar a busca.
  final int population;

  /// Nome do país em português ("Brasil"); vazio quando não há país, e o
  /// código cru se o código não estiver no mapa de nomes (não deveria
  /// acontecer — há teste conferindo que todo código do catálogo tem nome).
  String get countryName => countryNamesPtBr[countryCode] ?? countryCode;

  /// Linha de contexto para desambiguar na lista: "Ceará, Brasil".
  ///
  /// Sem país, sobra só a região; sem região também, string vazia — quem
  /// exibe decide o que fazer com isso (o overlay, por exemplo, não mostra
  /// linha de contexto nenhuma).
  String get contextLabel => [
    if (region.isNotEmpty) region,
    if (countryName.isNotEmpty) countryName,
  ].join(', ');

  /// [name] dobrado para busca, calculado uma vez.
  ///
  /// A busca roda a CADA TECLA sobre 7.341 cidades: dobrar os nomes a cada
  /// tecla seriam ~15 mil dobras por tecla. Como a cidade é imutável e nasce
  /// uma vez no carregamento, a dobra fica guardada nela.
  late final String foldedName = foldForSearch(name);

  /// [region] e [countryName] dobrados, na mesma ideia de [foldedName]. Os dois
  /// juntos porque separá-los não muda o casamento: quem procura "Ceará" ou
  /// "Brasil" quer a mesma coisa — a cidade que fica lá.
  late final String foldedContext = foldForSearch('$region $countryName');

  /// Cidade a partir de uma linha posicional de `cities` (ordem em [fields]).
  ///
  /// Lança [FormatException] quando a linha não tem o formato esperado. Um
  /// asset corrompido tem de falhar alto e claro: `id` vazio quebra a
  /// persistência, fuso vazio quebra `tz.getLocation` na primeira abertura, e
  /// coordenada nula põe a cidade no meio do mapa.
  factory City.fromList(List<Object?> row) {
    if (row.length != fields.length) {
      throw FormatException(
        'linha de cidade com ${row.length} campos, esperado ${fields.length}: '
        '$row',
      );
    }
    final latitude = (row[3] as num?)?.toDouble();
    final longitude = (row[4] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      throw FormatException('cidade sem coordenada: $row');
    }
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      throw FormatException('coordenada fora do mundo: $row');
    }
    final timeZoneId = (row[5] as String? ?? '').trim();
    if (timeZoneId.isEmpty) {
      throw FormatException('cidade sem fuso horário: $row');
    }
    final id = (row[7] as String? ?? '').trim();
    if (id.isEmpty) {
      throw FormatException('cidade sem identidade (id vazio): $row');
    }
    return City(
      id: id,
      name: row[0] as String? ?? '',
      region: row[1] as String? ?? '',
      countryCode: row[2] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
      timeZoneId: timeZoneId,
      population: (row[6] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() =>
      'City($name${region.isEmpty ? '' : ', $region'}, $countryCode, '
      '$timeZoneId)';
}
