import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/user_location.dart';

/// A posição do usuário: ordem das fontes (sistema primeiro, IP como reserva),
/// motivo da falha e leitura da resposta do serviço de IP.
void main() {
  const systemFix = UserLocation.fix(
    latitude: -27.586252,
    longitude: -48.542783,
    accuracyM: 40,
    source: UserLocationSource.system,
  );
  const ipFix = UserLocation.fix(
    latitude: -27.5966712,
    longitude: -48.5491699,
    source: UserLocationSource.ip,
  );
  const denied = UserLocation.failed(UserLocationFailure.permissionDenied);

  group('resolução', () {
    test('usa a posição do sistema quando ela vem', () async {
      var askedForIp = false;
      final location = await UserLocationResolver.resolve(
        systemLookup: () async => systemFix,
        ipLookup: () async {
          askedForIp = true;
          return ipFix;
        },
      );

      expect(location.hasFix, isTrue);
      expect(location.source, UserLocationSource.system);
      expect(location.latitude, systemFix.latitude);
      expect(
        askedForIp,
        isFalse,
        reason: 'com posição do sistema, o IP nem é consultado',
      );
    });

    test('cai no IP quando o sistema não responde', () async {
      final location = await UserLocationResolver.resolve(
        systemLookup: () async => denied,
        ipLookup: () async => ipFix,
      );

      expect(location.hasFix, isTrue);
      expect(location.source, UserLocationSource.ip);
      expect(location.latitude, ipFix.latitude);
    });

    test('falhando as duas, o motivo mostrado é o do sistema', () async {
      final location = await UserLocationResolver.resolve(
        systemLookup: () async => denied,
        ipLookup: () async =>
            const UserLocation.failed(UserLocationFailure.unavailable),
      );

      expect(location.hasFix, isFalse);
      expect(
        location.failure,
        UserLocationFailure.permissionDenied,
        reason: 'permissão negada é o motivo que o usuário pode resolver',
      );
      expect(location.notice, 'Localização: sem permissão');
    });

    test('posição sem coordenada não conta como posição', () {
      expect(denied.hasFix, isFalse);
      expect(denied.latitude, isNull);
      expect(
        systemFix.notice,
        isNull,
        reason: 'com posição não há o que dizer',
      );
    });
  });

  group('resposta do serviço de IP', () {
    // Corpo real do ipwho.is, capturado fora do teste.
    const realBody =
        '{"ip":"2804:14d:ba4a:8609:1007:95a9:e7a5:f0b1","success":true,'
        '"type":"IPv6","continent":"South America","country":"Brazil",'
        '"region":"Santa Catarina","city":"Florianopolis",'
        '"latitude":-27.5966712,"longitude":-48.5491699}';

    test('lê latitude e longitude', () {
      final location = UserLocationResolver.parseIpResponse(realBody);

      expect(location.hasFix, isTrue);
      expect(location.latitude, closeTo(-27.5966712, 1e-7));
      expect(location.longitude, closeTo(-48.5491699, 1e-7));
      expect(location.source, UserLocationSource.ip);
    });

    test('recusa quando o serviço diz que não achou (success=false)', () {
      final location = UserLocationResolver.parseIpResponse(
        '{"success":false,"message":"Reserved range"}',
      );

      expect(location.hasFix, isFalse);
      expect(location.failure, UserLocationFailure.unavailable);
    });

    test('recusa resposta incompleta ou ilegível', () {
      for (final body in <String>[
        '{"success":true,"city":"Florianopolis"}',
        '{"success":true,"latitude":-27.5}',
        '{"success":true,"latitude":"-27.5","longitude":"-48.5"}',
        'nao e json',
        '[]',
        '',
      ]) {
        final location = UserLocationResolver.parseIpResponse(body);
        expect(
          location.hasFix,
          isFalse,
          reason: 'corpo aceito indevidamente: $body',
        );
      }
    });
  });
}
