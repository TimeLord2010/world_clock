import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// De onde veio a posição.
enum UserLocationSource {
  /// Posição do próprio macOS: as redes Wi-Fi por perto, consultadas no banco
  /// da Apple. É a fonte precisa (dezenas de metros) e a única que existe num
  /// Mac — não há GPS.
  system('Wi-Fi'),

  /// Estimativa pela internet: acerta a cidade, não a rua. Só entra quando a
  /// fonte do sistema não responde (permissão negada, Wi-Fi desligado).
  ip('IP');

  const UserLocationSource(this.label);

  /// Nome curto da fonte, para a interface.
  final String label;
}

/// Por que a posição não veio.
///
/// Existe para a tela poder DIZER o motivo: sem posição, o usuário não
/// distingue "não autorizei" de "não tem rede" de "quebrou" — e um ponto que
/// simplesmente não aparece é uma falha silenciosa.
enum UserLocationFailure {
  permissionDenied('sem permissão'),
  servicesDisabled('serviço desligado'),
  unavailable('indisponível');

  const UserLocationFailure(this.label);

  /// Motivo em uma linha, para a linha do menu.
  final String label;
}

/// A posição atual do usuário — ou o motivo de não haver uma.
@immutable
class UserLocation {
  /// Uma posição válida, com a fonte que a produziu.
  const UserLocation.fix({
    required this.latitude,
    required this.longitude,
    required this.source,
    this.accuracyM,
  }) : failure = null;

  /// Sem posição, com o motivo.
  const UserLocation.failed(this.failure)
    : latitude = null,
      longitude = null,
      accuracyM = null,
      source = null;

  final double? latitude;
  final double? longitude;

  /// Raio de incerteza informado pela fonte, em metros (nulo quando ela não
  /// informa — a estimativa por IP não informa).
  final double? accuracyM;

  final UserLocationSource? source;
  final UserLocationFailure? failure;

  /// Se há coordenada para desenhar no mapa.
  bool get hasFix => latitude != null && longitude != null;

  /// Linha para o menu quando NÃO há posição; nulo quando há (o ponto no mapa
  /// fala por si).
  String? get notice =>
      failure == null ? null : 'Localização: ${failure!.label}';

  @override
  String toString() => hasFix
      ? 'UserLocation(${latitude!.toStringAsFixed(4)}, '
            '${longitude!.toStringAsFixed(4)} via ${source!.label}'
            '${accuracyM == null ? '' : ' ±${accuracyM!.round()} m'})'
      : 'UserLocation(${failure ?? 'sem posição'})';
}

/// Descobre onde o usuário está: primeiro a fonte do sistema, depois o IP.
///
/// A ordem importa pelo motivo que a medição mostrou: as duas fontes caem a
/// ~1 km uma da outra (menos de 1 pt na escala deste mapa), então a escolha não
/// é por precisão visual — é por CORREÇÃO. A posição do sistema é a posição de
/// verdade da máquina; o IP é um palpite da operadora, que só entra para o
/// ponto não desaparecer quando o sistema não coopera.
abstract final class UserLocationResolver {
  /// Quanto esperar pela fonte do sistema. Generoso de propósito: a primeira
  /// consulta ao banco de Wi-Fi leva alguns segundos e o resultado vale a
  /// espera (a tela não fica bloqueada nesse tempo — o ponto entra quando
  /// chega).
  static const Duration systemTimeout = Duration(seconds: 15);

  /// Quanto esperar pela estimativa por IP. Curto: é reserva, e é melhor
  /// desistir do que deixar a resolução pendurada.
  static const Duration ipTimeout = Duration(seconds: 5);

  /// Serviço de estimativa por IP, sem chave e sem cadastro.
  static final Uri ipEndpoint = Uri.parse('https://ipwho.is/');

  /// Resolve a posição. [systemLookup] e [ipLookup] são injetáveis só para os
  /// testes — sem eles, nada aqui precisa de rede nem de permissão para ser
  /// exercitado.
  static Future<UserLocation> resolve({
    Future<UserLocation> Function()? systemLookup,
    Future<UserLocation> Function()? ipLookup,
  }) async {
    final fromSystem = await (systemLookup ?? _fromSystem)();
    if (fromSystem.hasFix) {
      return fromSystem;
    }
    final fromIp = await (ipLookup ?? _fromIp)();
    // Falhando as duas, o motivo que interessa ao usuário é o da fonte do
    // sistema (permissão negada, serviço desligado) — o IP só falha por rede.
    return fromIp.hasFix ? fromIp : fromSystem;
  }

  /// A posição do macOS, via CoreLocation.
  static Future<UserLocation> _fromSystem() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _log('o macOS diz que o serviço de localização está desligado');
        return const UserLocation.failed(UserLocationFailure.servicesDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // É aqui que o macOS mostra o pedido de permissão — uma vez na vida do
        // app; depois disso a resposta vem do sistema.
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _log('permissão de localização negada pelo sistema ($permission)');
        return const UserLocation.failed(UserLocationFailure.permissionDenied);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: systemTimeout,
        ),
      );
      return UserLocation.fix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        source: UserLocationSource.system,
      );
    } on TimeoutException {
      _log('a fonte do sistema não respondeu em ${systemTimeout.inSeconds} s');
      return const UserLocation.failed(UserLocationFailure.unavailable);
    } catch (error) {
      // Plataforma que não implementa a chamada, ou erro do próprio serviço:
      // para a tela o resultado é o mesmo — sem posição do sistema.
      _log('fonte do sistema falhou: $error');
      return const UserLocation.failed(UserLocationFailure.unavailable);
    }
  }

  /// A estimativa por IP.
  static Future<UserLocation> _fromIp() async {
    final client = HttpClient()..connectionTimeout = ipTimeout;
    try {
      final request = await client.getUrl(ipEndpoint).timeout(ipTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(ipTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return const UserLocation.failed(UserLocationFailure.unavailable);
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(ipTimeout);
      return parseIpResponse(body);
    } catch (error) {
      _log('reserva por IP falhou: $error');
      return const UserLocation.failed(UserLocationFailure.unavailable);
    } finally {
      client.close(force: true);
    }
  }

  /// Diagnóstico: por que a fonte não respondeu. Só no log de debug, e nunca no
  /// lugar do motivo que o usuário vê — o log é para quem mexe no código, a
  /// linha da bandeja é para quem usa o app.
  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('[localização] $message');
    }
  }

  /// Lê a resposta do serviço de IP. Separado da rede de propósito: é esta
  /// parte que os testes exercitam, com corpos de resposta reais no lugar de
  /// uma chamada de rede.
  static UserLocation parseIpResponse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map || json['success'] == false) {
        return const UserLocation.failed(UserLocationFailure.unavailable);
      }
      final latitude = (json['latitude'] as num?)?.toDouble();
      final longitude = (json['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) {
        return const UserLocation.failed(UserLocationFailure.unavailable);
      }
      return UserLocation.fix(
        latitude: latitude,
        longitude: longitude,
        source: UserLocationSource.ip,
      );
    } catch (_) {
      return const UserLocation.failed(UserLocationFailure.unavailable);
    }
  }
}
