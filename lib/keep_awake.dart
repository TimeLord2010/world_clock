import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quem impede a TELA de dormir enquanto o relógio está à vista.
///
/// O macOS apaga o monitor por ociosidade do **usuário**, não do app: o mapa
/// pode estar redesenhando a cada 5 minutos e mesmo assim o monitor apaga. Quem
/// segura a tela acesa é uma *power assertion* do IOKit, e o Dart não alcança o
/// IOKit — o lado nativo do app cria e libera a assertion (ver
/// `macos/Runner/AppDelegate.swift`), e esta interface é a ponte.
///
/// A escolha é do usuário e **sobrevive ao fechamento do app**: é uma opção que
/// ele liga uma vez e espera encontrar ligada na próxima abertura, por isso
/// [setEnabled] grava além de aplicar. Só grava o que de fato entrou em vigor —
/// uma assertion que falhou **não** vira uma preferência que o app tentaria
/// reaplicar (e falhar de novo) a cada abertura.
abstract interface class KeepAwake {
  /// A escolha guardada da execução anterior — falso quando não há nenhuma.
  Future<bool> savedChoice();

  /// Mantém a tela ligada (ou libera) AGORA e guarda a escolha.
  Future<void> setEnabled(bool enabled);
}

/// Implementação de verdade: canal de plataforma + `shared_preferences`.
///
/// **Não é o default da tela**, e nem poderia: é plugin nativo, e num teste de
/// widget sem preparo derruba o teste com `MissingPluginException` (mesma
/// razão pela qual `SharedPreferencesCityStore` também não é default). Quem
/// monta o app de verdade (`main`) passa este; os testes passam
/// [MemoryKeepAwake] — ou nada, e aí a opção nem aparece no menu.
class SystemKeepAwake implements KeepAwake {
  const SystemKeepAwake();

  /// O canal que o `AppDelegate` atende. O método é `setEnabled` e o argumento
  /// é o bool direto (`invokeMethod`), não um mapa — o contrato é este e o
  /// teste `test/keep_awake_test.dart` o trava dos dois lados do canal.
  static const MethodChannel channel = MethodChannel('world_clock/keep_awake');

  /// Chave da escolha no `NSUserDefaults` (o `shared_preferences` prefixa com
  /// `flutter.` no macOS). Prefixada como as chaves de cidade: o
  /// `NSUserDefaults` é compartilhado com qualquer outra coisa que o app venha
  /// a guardar.
  static const String enabledKey = 'screen.keepAwake';

  @override
  Future<bool> savedChoice() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(enabledKey) ?? false;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    // Aplicar ANTES de gravar: uma assertion negada tem de subir como erro para
    // a tela poder voltar a caixinha e dizer o motivo, em vez de deixar no disco
    // uma escolha que não está valendo.
    await channel.invokeMethod<void>('setEnabled', enabled);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(enabledKey, enabled);
  }
}

/// Implementação de memória: os testes injetam esta, e ela é a documentação
/// viva do contrato (aplica e guarda o que recebeu).
class MemoryKeepAwake implements KeepAwake {
  MemoryKeepAwake({this.choice = false, this.failure});

  /// A escolha "guardada" que [savedChoice] devolve — é assim que um teste
  /// monta a tela como se o usuário tivesse ligado a opção na execução
  /// anterior.
  bool choice;

  /// Quando não-nulo, [setEnabled] lança ISTO em vez de aplicar. É como os
  /// testes cobrem a assertion negada pelo nativo sem depender de plugin.
  Object? failure;

  /// Os valores que a tela pediu, na ordem em que pediu (o `false` de desligar
  /// conta: o que o teste quer saber é o que chegou ao nativo).
  final List<bool> applied = <bool>[];

  /// O que está em vigor agora, do ponto de vista do "nativo".
  bool get enabled => applied.isEmpty ? false : applied.last;

  @override
  Future<bool> savedChoice() async => choice;

  @override
  Future<void> setEnabled(bool enabled) async {
    final error = failure;
    if (error != null) {
      throw error;
    }
    applied.add(enabled);
    choice = enabled;
  }
}
