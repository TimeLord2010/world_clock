import 'package:flutter/foundation.dart' show immutable, setEquals;
import 'package:shared_preferences/shared_preferences.dart';

/// O que o usuário escolheu e precisa sobreviver ao fechamento do app.
@immutable
class SavedCities {
  const SavedCities({
    this.selected = const <String>{},
    this.pinned = const <String>{},
  });

  /// Ids das cidades salvas (aparecem como ponto no mapa).
  final Set<String> selected;

  /// Ids das cidades com o horário sempre visível, sem depender de clique.
  /// Subconjunto de [selected] na prática, mas não é imposto aqui.
  final Set<String> pinned;

  SavedCities copyWith({Set<String>? selected, Set<String>? pinned}) =>
      SavedCities(
        selected: selected ?? this.selected,
        pinned: pinned ?? this.pinned,
      );

  @override
  bool operator ==(Object other) =>
      other is SavedCities &&
      setEquals(other.selected, selected) &&
      setEquals(other.pinned, pinned);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(selected),
    Object.hashAllUnordered(pinned),
  );

  @override
  String toString() => 'SavedCities(selected: $selected, pinned: $pinned)';
}

/// Onde a escolha do usuário fica entre execuções.
///
/// **Guarda só IDs do catálogo** (`City.id`), nunca nome, coordenada ou fuso: o
/// catálogo é a fonte desses dados, então regenerá-lo com dados melhores não
/// invalida a escolha de ninguém. Um id que sumir do catálogo numa regeneração
/// é descartado por quem carrega (`CityCatalog.byIds`), em silêncio — o usuário
/// não tem o que fazer a respeito, e travar a abertura do app por causa de um id
/// órfão seria pior do que perder a cidade.
///
/// A interface existe para a tela não conhecer o `shared_preferences` e para os
/// testes injetarem uma implementação de memória (ver [MemoryCityStore]).
abstract interface class CityStore {
  Future<SavedCities> load();
  Future<void> save(SavedCities cities);
}

/// Implementação de verdade: `NSUserDefaults` no macOS, via
/// `shared_preferences`.
///
/// NÃO é o default do `WorldMapScreen` de propósito: `SharedPreferences` é um
/// plugin, e num teste de widget uma chamada sem preparo derruba o teste com
/// `MissingPluginException`. Quem constrói o app de verdade (`main`) passa este;
/// os testes passam [MemoryCityStore] ou nada.
class SharedPreferencesCityStore implements CityStore {
  const SharedPreferencesCityStore();

  /// Nomes das chaves. Prefixadas porque o `NSUserDefaults` é compartilhado com
  /// qualquer outra coisa que o app venha a guardar.
  static const String selectedKey = 'cities.selected';
  static const String pinnedKey = 'cities.pinned';

  @override
  Future<SavedCities> load() async {
    final preferences = await SharedPreferences.getInstance();
    return SavedCities(
      selected: (preferences.getStringList(selectedKey) ?? const <String>[])
          .toSet(),
      pinned: (preferences.getStringList(pinnedKey) ?? const <String>[])
          .toSet(),
    );
  }

  @override
  Future<void> save(SavedCities cities) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(selectedKey, cities.selected.toList());
    await preferences.setStringList(pinnedKey, cities.pinned.toList());
  }
}

/// Implementação de memória: os testes injetam esta, e ela serve de documentação
/// viva do contrato (nada além de guardar o que recebeu).
class MemoryCityStore implements CityStore {
  MemoryCityStore([this._cities = const SavedCities()]);

  SavedCities _cities;

  /// Quantas vezes [save] foi chamado — os testes usam para conferir que a tela
  /// só grava quando algo muda, e não a cada quadro.
  int saveCount = 0;

  /// O que está guardado agora.
  SavedCities get cities => _cities;

  @override
  Future<SavedCities> load() async => _cities;

  @override
  Future<void> save(SavedCities cities) async {
    _cities = cities;
    saveCount++;
  }
}
