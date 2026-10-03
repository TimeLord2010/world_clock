import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, debugPrint, kDebugMode;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone_finder/timezone_finder.dart' as tzf;

import 'city.dart';
import 'map_geometry.dart';
import 'nautical_zone.dart';

/// O nome de um lugar, quando alguma fonte soube dizer qual é.
@immutable
class PlaceName {
  const PlaceName({required this.locality, this.region, this.country});

  /// A localidade: "Fortaleza".
  final String locality;

  /// Estado/região, quando a fonte informa ("Ceará").
  final String? region;

  /// País, quando a fonte informa ("Brasil").
  final String? country;

  @override
  String toString() => 'PlaceName($locality)';
}

/// O que se sabe de um ponto do mapa clicado.
@immutable
class PlaceInfo {
  const PlaceInfo({
    required this.point,
    required this.location,
    this.name,
    this.country,
    this.distanceKm,
    this.approximate = false,
    this.notice,
  });

  /// A coordenada clicada.
  final MapPoint point;

  /// O fuso do ponto. **Nunca é nulo**: é a resposta que o usuário pediu, e há
  /// sempre uma (polígono, cidade próxima ou faixa náutica).
  final tz.Location location;

  /// O nome do lugar, quando alguma fonte soube. Nulo em mar aberto e em terra
  /// longe de qualquer cidade do catálogo — e aí o overlay mostra só o fuso e a
  /// hora, em vez de inventar um vizinho.
  final String? name;

  /// O país do [name], quando a fonte informa.
  final String? country;

  /// A distância até a cidade que deu o nome, quando o nome veio do catálogo.
  /// Nula quando o nome veio de uma fonte de verdade (aí ele é o lugar).
  final double? distanceKm;

  /// Se o nome é APROXIMADO (a cidade mais próxima, e não o lugar exato do
  /// clique). O overlay diz isso ao usuário — apresentar "Fortaleza" para um
  /// ponto a 200 km dela seria mentira.
  final bool approximate;

  /// Por que o nome não veio, quando ele foi buscado e falhou. Nulo quando não
  /// houve o que falhar. O TEMPO nunca depende disso.
  final String? notice;

  /// O rótulo do lugar: o nome quando há, e uma descrição HONESTA quando não há.
  ///
  /// "Mar aberto" e "sem cidade por perto" são a verdade, e são melhores do que
  /// um nome de vizinho a 400 km ou um identificador interno como `Etc/GMT+2`.
  /// A distinção sai do próprio fuso: as zonas `Etc/*` são as faixas náuticas,
  /// que só existem onde não há terra com zona política.
  String get label {
    if (name != null) {
      return name!;
    }
    return location.name.startsWith('Etc/')
        ? 'Mar aberto'
        : 'Sem cidade por perto';
  }

  /// A mesma informação, com o nome exato que uma fonte de nomes devolveu.
  ///
  /// Zera [distanceKm] e [approximate]: o nome deixou de ser "a cidade mais
  /// próxima" e passou a ser o lugar do clique.
  PlaceInfo withExactName(PlaceName name) => PlaceInfo(
    point: point,
    location: location,
    name: name.locality,
    country: name.country,
  );

  /// A mesma informação, com o motivo de um nome exato não ter vindo.
  PlaceInfo withNotice(String notice) => PlaceInfo(
    point: point,
    location: location,
    name: name,
    country: country,
    distanceKm: distanceKm,
    approximate: approximate,
    notice: notice,
  );

  @override
  String toString() =>
      'PlaceInfo(${point.latitude.toStringAsFixed(2)}, '
      '${point.longitude.toStringAsFixed(2)} @ ${location.name}'
      '${name == null ? '' : ', $name'})';
}

/// Resolve o que há num ponto do mapa.
abstract interface class PlaceLookup {
  Future<PlaceInfo> resolve(MapPoint point);
}

/// Uma fonte de NOME para um ponto. Separada do [PlaceLookup] porque nome é
/// opcional e fuso não: assim uma fonte de nome pode falhar, ou nem existir, sem
/// nunca ameaçar a hora.
abstract interface class PlaceNameLookup {
  /// O nome do lugar, ou nulo quando não há (mar aberto, área sem nome).
  Future<PlaceName?> lookup(MapPoint point);
}

/// O fuso vem SEMPRE daqui, offline: polígono do TZBB quando o ponto é terra,
/// faixa náutica quando é mar. O nome sai do catálogo de cidades (a mais
/// próxima, marcada como aproximada) e nunca de rede.
///
/// O `tz.getLocation` é o único ponto que pode lançar, e só se o id não existir
/// na tzdb carregada — o que não acontece com os ids dos polígonos nem com as
/// faixas náuticas (`Etc/GMT` e `Etc/GMT±1..12`).
class OfflinePlaceLookup implements PlaceLookup {
  const OfflinePlaceLookup({required this.catalog});

  /// O catálogo de cidades, para o nome de terra firme.
  final List<City> catalog;

  /// Raio em que a cidade mais próxima ainda dá nome ao ponto.
  ///
  /// Generoso de propósito: o catálogo tem 7.341 lugares e grandes vazios
  /// (Saara, Sibéria, Amazônia), então um raio curto deixaria a maior parte da
  /// terra sem nome nenhum. O que impede isso de virar mentira é o
  /// [PlaceInfo.approximate] junto com a distância: o overlay diz "a 120 km de
  /// X", e não "X".
  static const double nameRadiusKm = 250;

  /// Até esta distância o nome é apresentado como o lugar do clique, sem
  /// ressalva. Acima dela, é aproximado — e a distância vai junto.
  static const double exactRadiusKm = 50;

  @override
  Future<PlaceInfo> resolve(MapPoint point) async {
    final location = tz.getLocation(_zoneIdAt(point));
    final nearest = _nearestCity(point);
    if (nearest == null) {
      return PlaceInfo(point: point, location: location);
    }
    final (city, distanceKm) = nearest;
    return PlaceInfo(
      point: point,
      location: location,
      name: city.name,
      country: city.countryName,
      distanceKm: distanceKm,
      approximate: distanceKm > exactRadiusKm,
    );
  }

  /// O id do fuso do ponto: o polígono quando cobre, a faixa náutica quando não.
  String _zoneIdAt(MapPoint point) {
    try {
      final fromPolygon = tzf.findLocation(point.longitude, point.latitude);
      if (fromPolygon != null) {
        return fromPolygon.name;
      }
    } catch (error) {
      // Coordenada estranha ou dado de polígono indisponível: a faixa náutica
      // ainda responde a hora. Registra porque degradar em silêncio é o que
      // torna "o horário está esquisito" impossível de investigar.
      if (kDebugMode) {
        debugPrint('[fuso] polígono falhou em $point: $error');
      }
    }
    return nauticalZoneId(point.longitude);
  }

  /// A cidade do catálogo mais próxima de [point], com a distância — ou nulo se
  /// nenhuma estiver dentro de [nameRadiusKm].
  (City, double)? _nearestCity(MapPoint point) {
    City? best;
    var bestKm = double.infinity;
    for (final city in catalog) {
      final km = distanceKm(
        point.latitude,
        point.longitude,
        city.latitude,
        city.longitude,
      );
      if (km < bestKm) {
        bestKm = km;
        best = city;
      }
    }
    if (best == null || bestKm > nameRadiusKm) {
      return null;
    }
    return (best, bestKm);
  }
}

/// O nome exato do lugar, pela internet (BigDataCloud, sem chave).
///
/// **Só o NOME.** O fuso jamais vem daqui: a hora é offline e autoritativa, e
/// uma requisição não pode ter poder de mudá-la. Assim a rede pode falhar, ficar
/// lenta ou nem existir sem afetar a resposta que o usuário pediu.
class BigDataCloudNameLookup implements PlaceNameLookup {
  BigDataCloudNameLookup({
    this.timeout = const Duration(seconds: 5),
    Uri? endpoint,
  }) : endpoint = endpoint ?? _defaultEndpoint;

  static final Uri _defaultEndpoint = Uri.parse(
    'https://api.bigdatacloud.net/data/reverse-geocode-client',
  );

  /// Quanto esperar pela resposta. Curto: o nome é um extra, e é melhor
  /// desistir do que deixar o cartão pendurado.
  final Duration timeout;

  final Uri endpoint;

  /// Cache por célula de 0,25° (≈ 28 km): cliques vizinhos — que é o que
  /// acontece quando alguém clica várias vezes no mesmo lugar — não repetem a
  /// requisição.
  final Map<String, PlaceName?> _cache = <String, PlaceName?>{};

  /// Quantas requisições foram feitas de verdade. Os testes usam para conferir
  /// que o cache funciona.
  int requestCount = 0;

  @override
  Future<PlaceName?> lookup(MapPoint point) async {
    final key = cacheKey(point);
    if (_cache.containsKey(key)) {
      return _cache[key];
    }

    final name = await _fetch(point);
    _cache[key] = name;
    return name;
  }

  /// A chave de cache de um ponto: a célula de 0,25° que o contém.
  static String cacheKey(MapPoint point) =>
      '${(point.latitude * 4).round()},${(point.longitude * 4).round()}';

  Future<PlaceName?> _fetch(MapPoint point) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      requestCount++;
      final uri = endpoint.replace(
        queryParameters: {
          'latitude': point.latitude.toString(),
          'longitude': point.longitude.toString(),
          // Nomes em português: o app inteiro está em português, e a fonte
          // devolve "Ceará" em vez de "Ceara" com este parâmetro.
          'localityLanguage': 'pt',
        },
      );
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return parseName(body);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[nome] consulta falhou: $error');
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Lê a resposta do serviço. Separado da rede de propósito: é esta parte que
  /// os testes exercitam, com corpos de resposta reais.
  ///
  /// A ORDEM importa: `locality` é a cidade ("Fortaleza") e `city` é a região
  /// metropolitana ("Região Metropolitana de Fortaleza") — medido na resposta
  /// de verdade. Preferir `city` poria um nome de região no lugar do nome da
  /// cidade. E país vazio significa que a fonte não sabe onde é o ponto (mar
  /// aberto): melhor não ter nome do que ter o vizinho mais próximo.
  static PlaceName? parseName(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) {
        return null;
      }
      final country = _text(json['countryName']);
      final locality = _text(json['locality']);
      final city = _text(json['city']);
      final chosen = locality.isNotEmpty ? locality : city;
      if (chosen.isEmpty || country.isEmpty) {
        return null;
      }
      final region = _text(json['principalSubdivision']);
      return PlaceName(
        locality: chosen,
        region: region.isEmpty ? null : region,
        country: country,
      );
    } catch (_) {
      return null;
    }
  }

  static String _text(Object? value) =>
      value is String ? value.trim() : '';
}

/// Distância em km entre dois pontos, pela fórmula do haversine.
///
/// Haversine e não a distância em graus: um grau de longitude vale 111 km no
/// Equador e quase nada perto dos polos, e é justamente nas latitudes altas que
/// o catálogo tem vazios. A diferença de distância mudaria o nome apresentado.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0088;
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.asin(math.min(1, math.sqrt(a)));
}

double _radians(double degrees) => degrees * math.pi / 180;
