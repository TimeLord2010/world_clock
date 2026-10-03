import Cocoa
import FlutterMacOS
import IOKit.pwr_mgt

@main
class AppDelegate: FlutterAppDelegate {
  /// O canal que a tela do app usa para pedir "não deixe a tela dormir".
  ///
  /// O método é `setEnabled` e o argumento é o bool seco (o Dart manda por
  /// `invokeMethod`, não por mapa). Quem cria e quem libera a assertion é este
  /// lado: o macOS apaga o monitor por ociosidade do USUÁRIO, e o Dart não
  /// alcança o IOKit.
  private static let keepAwakeChannel = "world_clock/keep_awake"

  /// A assertion de tela em vigor (0 = nenhuma). O IOKit exige que a liberação
  /// use o MESMO id que a criação devolveu, então ele fica guardado aqui — e
  /// guardado também serve de trava: pedir duas vezes "ligar" não empilha
  /// assertions.
  private var displaySleepAssertion: IOPMAssertionID = 0

  /// Motivo que aparece no `pmset -g assertions` — é por ele que se confere, de
  /// fora, que a opção está valendo.
  private static let assertionReason = "World Clock: manter a tela ligada"

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController
      as? FlutterViewController
    {
      let channel = FlutterMethodChannel(
        name: Self.keepAwakeChannel,
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "setEnabled":
          guard let enabled = call.arguments as? Bool else {
            result(
              FlutterError(
                code: "bad_arguments",
                message: "setEnabled espera um bool",
                details: nil
              )
            )
            return
          }
          // `nil` é o sucesso do canal; o erro, quando há, é a razão.
          result(self?.setDisplaySleepPrevented(enabled))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    super.applicationDidFinishLaunching(notification)
  }

  /// Fechar a janela já encerra o app
  /// (`applicationShouldTerminateAfterLastWindowClosed`) e a assertion cairia
  /// com o processo de qualquer jeito; liberar aqui só torna a intenção
  /// explícita.
  override func applicationWillTerminate(_ notification: Notification) {
    displaySleepAssertion = releaseDisplaySleepPrevention()
    super.applicationWillTerminate(notification)
  }

  /// Liga (ou desliga) a prevenção do sono da TELA. Devolve `nil` quando deu
  /// certo — o que o `FlutterMethodChannel` entende como sucesso — ou o
  /// `FlutterError` com o motivo, para a falha chegar na interface em vez de
  /// morrer aqui dentro.
  ///
  /// A assertion é `kIOPMAssertionTypePreventUserIdleDisplaySleep`: a MESMA que
  /// o `caffeinate -d` segura. Ela impede a TELA de apagar por ociosidade — o
  /// que foi pedido é "manter a tela ligada", não "manter o Mac trabalhando".
  private func setDisplaySleepPrevented(_ enabled: Bool) -> FlutterError? {
    if !enabled {
      displaySleepAssertion = releaseDisplaySleepPrevention()
      return nil
    }

    guard displaySleepAssertion == 0 else {
      return nil  // já está ligada, e uma assertion só basta
    }

    var id: IOPMAssertionID = 0
    let status = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      Self.assertionReason as CFString,
      &id
    )
    guard status == kIOReturnSuccess else {
      return FlutterError(
        code: "assertion_failed",
        message: "IOPMAssertionCreateWithName devolveu \(status)",
        details: nil
      )
    }
    displaySleepAssertion = id
    return nil
  }

  /// Libera a assertion em vigor e devolve 0 (nenhuma).
  private func releaseDisplaySleepPrevention() -> IOPMAssertionID {
    guard displaySleepAssertion != 0 else {
      return 0
    }
    IOPMAssertionRelease(displaySleepAssertion)
    return 0
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
