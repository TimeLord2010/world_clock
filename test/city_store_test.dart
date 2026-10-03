import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:world_clock/city_store.dart';

/// Onde a escolha do usuário é guardada entre execuções: o que sobrevive, o que
/// é descartado e por que só ids.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SavedCities', () {
    test('compara por conteúdo, não por identidade', () {
      const a = SavedCities(selected: {'1', '2'}, pinned: {'1'});
      const b = SavedCities(selected: {'2', '1'}, pinned: {'1'});

      expect(a, b, reason: 'a ordem do conjunto não pode importar');
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const SavedCities(selected: {'1'})));
    });

    test('copyWith troca um lado e preserva o outro', () {
      const original = SavedCities(selected: {'1'}, pinned: {'1'});

      expect(original.copyWith(selected: {'2'}).pinned, {'1'});
      expect(original.copyWith(pinned: const <String>{}).selected, {'1'});
      expect(original.copyWith(), original);
    });

    test('vazio por padrão', () {
      expect(const SavedCities().selected, isEmpty);
      expect(const SavedCities().pinned, isEmpty);
    });
  });

  group('MemoryCityStore', () {
    test('devolve o que recebeu', () async {
      final store = MemoryCityStore();

      expect(await store.load(), const SavedCities());

      const saved = SavedCities(selected: {'a', 'b'}, pinned: {'b'});
      await store.save(saved);

      expect(await store.load(), saved);
      expect(store.cities, saved);
      expect(store.saveCount, 1);
    });

    test('pode nascer com um estado, para os testes de restauração', () async {
      final store = MemoryCityStore(
        const SavedCities(selected: {'a'}, pinned: {'a'}),
      );

      expect((await store.load()).selected, {'a'});
      expect(store.saveCount, 0, reason: 'nascer com estado não é gravar');
    });
  });

  group('SharedPreferencesCityStore', () {
    test('grava e relê as duas listas', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = SharedPreferencesCityStore();

      await store.save(const SavedCities(selected: {'1', '2'}, pinned: {'2'}));

      // Lê do zero, como numa abertura nova do app.
      final reloaded = await const SharedPreferencesCityStore().load();

      expect(reloaded.selected, {'1', '2'});
      expect(reloaded.pinned, {'2'});
    });

    test('sem nada gravado, devolve vazio em vez de estourar', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final reloaded = await const SharedPreferencesCityStore().load();

      expect(reloaded, const SavedCities());
    });
  });
}
