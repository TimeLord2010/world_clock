import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'city.dart';
import 'city_catalog.dart';
import 'city_clock.dart';
import 'city_clock_layer.dart';
import 'city_store.dart';
import 'map_theme.dart';
import 'moon_marker.dart';
import 'moon_position.dart';
import 'settings_menu.dart';
import 'user_location.dart';
import 'user_marker.dart';
import 'world_dot_map.dart';

void main() {
  // A base de fusos (tzdb) tem de estar carregada antes do primeiro `CityClock`
  // — e `CityClock` é construído assim que o catálogo de cidades chega, no
  // primeiro quadro. Sem isto, `tz.getLocation` lança.
  //
  // `latest_all` e NÃO `latest`: é o `latest_all` que traz os identificadores
  // de link (106 deles). O gerador do catálogo aceita qualquer id que exista na
  // tzdb completa, então com `latest` uma cidade legítima derrubaria a abertura
  // do app.
  tzdata.initializeTimeZones();
  runApp(const WorldClockApp(cityStore: SharedPreferencesCityStore()));
}

class WorldClockApp extends StatelessWidget {
  const WorldClockApp({
    super.key,
    this.locationLookup = UserLocationResolver.resolve,
    this.cityStore,
  });

  /// Como a tela descobre a posição do usuário — repassado para
  /// [WorldMapScreen.locationLookup]; os testes trocam por uma resposta fixa e
  /// assim não dependem de rede nem de permissão.
  final Future<UserLocation> Function() locationLookup;

  /// Onde as cidades salvas ficam entre execuções. Repassado para
  /// [WorldMapScreen.cityStore]; nulo desliga a persistência.
  final CityStore? cityStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'World Clock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF111111),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF9800),
          brightness: Brightness.dark,
        ),
      ),
      home: WorldMapScreen(
        locationLookup: locationLookup,
        cityStore: cityStore,
      ),
    );
  }
}

class WorldMapScreen extends StatefulWidget {
  const WorldMapScreen({
    super.key,
    this.locationLookup = UserLocationResolver.resolve,
    this.cityStore,
  });

  /// Como descobrir a posição do usuário. Injetável para os testes rodarem sem
  /// rede nem permissão (o padrão é a resolução de verdade).
  final Future<UserLocation> Function() locationLookup;

  /// Onde ler e gravar as cidades salvas.
  ///
  /// **Nulo é o padrão, e nulo significa "sem persistência"** — de propósito. O
  /// `shared_preferences` é um plugin nativo: chamá-lo num teste de widget sem
  /// preparo derruba o teste com `MissingPluginException`. Assim os testes que
  /// não se interessam por cidades (a maioria) não precisam saber que isso
  /// existe, e quem quer testar persistência injeta um `MemoryCityStore`.
  final CityStore? cityStore;

  @override
  State<WorldMapScreen> createState() => _WorldMapScreenState();
}

class _WorldMapScreenState extends State<WorldMapScreen> {
  DateTime _now = DateTime.now();

  /// Lua no instante [_now]: recalculada junto com o Sol, no mesmo tique.
  MoonStatus _moon = MoonPosition.at(DateTime.now());

  Timer? _ticker;

  /// Tema em uso. Só o menu o muda; a escolha vive na sessão (não é
  /// persistida entre execuções ainda).
  MapTheme _theme = MapThemes.standard;

  /// Espera pelo crepúsculo: LIGADA por padrão — foi a opção escolhida (a
  /// noite do mapa só chega quando o céu de fato apaga, ~25 min depois do pôr
  /// do sol). O item "Incluir crepúsculo" do menu desliga e o mapa volta ao
  /// desenho anterior (noite no instante em que o sol cruza o horizonte).
  bool _includeTwilight = true;

  /// Onde o usuário está, quando o sistema (ou o IP) responde. Nulo enquanto a
  /// consulta não voltou — a tela abre sem o ponto e ele entra quando chega,
  /// sem prender a abertura do app.
  UserLocation? _location;

  /// As cidades salvas, com o fuso de cada uma já resolvido. Vazio enquanto a
  /// leitura do disco não volta (e continua vazio se não houver nada salvo).
  List<CityClock> _cities = const <CityClock>[];

  /// O catálogo inteiro (7.341 lugares), que alimenta o painel de cidades.
  ///
  /// Fica na tela porque o painel precisa poder BUSCAR em qualquer cidade, e não
  /// só nas salvas — sem ele, não haveria como adicionar a primeira.
  List<City> _catalog = const <City>[];

  @override
  void initState() {
    super.initState();
    unawaited(_refreshLocation());
    unawaited(_loadCities());
    // Keep the day/night boundary moving: refresh the reference instant
    // every 5 minutes (the sun moves ~1,25° of longitude in that window —
    // about one cell of the 1° dot grid; the old 15-minute step was ~3,75°).
    _ticker = Timer.periodic(const Duration(minutes: 5), (_) {
      setState(() {
        _now = DateTime.now();
        // A Lua anda ~0,04° em 5 min — menos de 1 px no mapa, então o mesmo
        // tique serve para ela. Se um dia quiser movimento contínuo, o
        // marcador está FORA do RepaintBoundary do mapa: dá para atualizá-lo
        // sozinho, sem repintar os pontos.
        _moon = MoonPosition.at(_now);
      });
      // O Mac não sai do lugar, mas a RESPOSTA pode mudar: quem negou a
      // permissão e depois autorizou só ganha o ponto porque este tique
      // pergunta de novo. Uma consulta a cada 5 min é barata (a posição do
      // sistema vem do cache do Wi-Fi, o IP é uma requisição curta).
      unawaited(_refreshLocation());
    });
  }

  /// Lê o catálogo e as cidades salvas, e publica as que ainda existem.
  ///
  /// O CATÁLOGO é lido mesmo sem persistência nenhuma: o painel de cidades
  /// precisa dele para oferecer qualquer coisa, e sem isso não haveria como
  /// adicionar a primeira cidade.
  ///
  /// As leituras são assíncronas (asset, disco, e o `tz.getLocation` de cada
  /// cidade), então a tela abre sem marcador nenhum e eles entram quando a
  /// leitura volta — o mesmo contrato do ponto do usuário, que também não prende
  /// a abertura.
  Future<void> _loadCities() async {
    var catalog = const <City>[];
    var saved = const SavedCities();
    try {
      catalog = await CityCatalog.load();
      final store = widget.cityStore;
      if (store != null) {
        saved = await store.load();
      }
    } catch (error) {
      // O mapa é o conteúdo; as cidades são um extra. Uma falha ao ler o
      // catálogo ou o disco não pode impedir o app de abrir — mas também não
      // pode sumir sem deixar rastro.
      if (kDebugMode) {
        debugPrint('[cidades] falha ao carregar o catálogo/cidades: $error');
      }
    }
    if (!mounted) {
      return;
    }
    final chosen = CityCatalog.byIds(catalog, saved.selected);
    setState(() {
      _catalog = catalog;
      _cities = [for (final city in chosen) CityClock(city)];
    });
  }

  /// A cidade do catálogo com este id, ou nulo (id órfão).
  City? _cityById(String id) {
    for (final city in _catalog) {
      if (city.id == id) {
        return city;
      }
    }
    return null;
  }

  /// Salva a cidade ou a retira do mapa.
  void _toggleSavedCity(String id) {
    final city = _cityById(id);
    if (city == null) {
      return;
    }
    final isSaved = _cities.any((clock) => clock.city.id == id);

    setState(() {
      if (isSaved) {
        _cities = [
          for (final clock in _cities)
            if (clock.city.id != id) clock,
        ];
      } else {
        // Ordem por população, a mesma do catálogo: os marcadores não dançam
        // conforme a ordem em que o usuário escolheu.
        _cities = [..._cities, CityClock(city)]
          ..sort((a, b) => b.city.population.compareTo(a.city.population));
      }
    });
    unawaited(_persistCities());
  }

  /// Grava a escolha atual. Falha não impede nada: o estado da sessão continua
  /// valendo, só não sobrevive ao fechamento.
  Future<void> _persistCities() async {
    final store = widget.cityStore;
    if (store == null) {
      return;
    }
    try {
      await store.save(
        SavedCities(selected: {for (final clock in _cities) clock.city.id}),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[cidades] falha ao gravar as cidades salvas: $error');
      }
    }
  }

  /// Pergunta a posição e publica o resultado. Falha não é silenciosa: o
  /// motivo vai para a linha da bandeja (ver `SettingsMenu.locationNotice`) e
  /// fica registrado no log — sem isso, "o ponto não apareceu" é indistinguível
  /// de "a consulta quebrou".
  Future<void> _refreshLocation() async {
    final location = await widget.locationLookup();
    if (kDebugMode) {
      debugPrint('[localização] $location');
    }
    if (!mounted) {
      return;
    }
    setState(() => _location = location);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _theme.background,
      body: SafeArea(
        child: Stack(
          children: [
            // The map keeps its 2:1 equirectangular aspect: it fills the width
            // in portrait and the height in landscape.
            //
            // RepaintBoundary (dentro do Stack do mapa): o mapa tem dezenas de
            // milhares de pontos e era irmão do menu na mesma camada. Sem a
            // fronteira, CADA rebuild do menu (abrir, trocar de opção, destacar
            // uma linha) invalidava a camada e repintava o mapa inteiro — era
            // isso que travava a tela no hover. Com ela, o menu repinta só a si
            // mesmo, e a Lua também.
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mapWidth =
                      constraints.maxWidth < constraints.maxHeight * 2
                      ? constraints.maxWidth
                      : constraints.maxHeight * 2;
                  final mapSize = Size(mapWidth, mapWidth / 2);
                  return Center(
                    child: SizedBox(
                      width: mapSize.width,
                      height: mapSize.height,
                      child: Stack(
                        // Clip.none: o overlay da Lua pode passar da borda do
                        // mapa quando ela está colada no limite (é o Stack de
                        // fora, da tela, que acaba recortando).
                        clipBehavior: Clip.none,
                        children: [
                          // O RepaintBoundary envolve SÓ os pontos do mapa. A
                          // Lua é irmã dele no Stack: um tique da Lua — ou o
                          // hover no marcador — não invalida a camada do mapa
                          // (dezenas de milhares de pontos). O pintor dos
                          // pontos segue recebendo os mesmos dados, então nem o
                          // rebuild do hover faz o mapa repintar.
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: WorldDotMap(
                                now: _now,
                                backgroundColor: _theme.background,
                                dotColor: _theme.land,
                                oceanColor: _theme.ocean,
                                includeTwilight: _includeTwilight,
                              ),
                            ),
                          ),
                          // Positioned.fill: o marcador se posiciona sozinho (e
                          // o overlay junto), porque a posição depende do
                          // tamanho do mapa em pontos.
                          //
                          // As CIDADES vêm antes da Lua e do ponto do usuário no
                          // Stack (ou seja, por baixo dos dois): num encontro
                          // fortuito, quem manda é o "você está aqui" e o objeto
                          // celeste, que não são clicáveis nem escolhidos pelo
                          // usuário. O ponto do usuário é IgnorePointer, então um
                          // clique sobre a cidade atravessa e chega nela.
                          Positioned.fill(
                            child: CityClockLayer(
                              cities: _cities,
                              mapSize: mapSize,
                              land: _theme.land,
                            ),
                          ),
                          Positioned.fill(
                            child: MoonMarker(
                              status: _moon,
                              mapSize: mapSize,
                              background: _theme.background,
                            ),
                          ),
                          // O ponto do usuário fica DEPOIS do marcador da Lua
                          // no Stack, ou seja, por cima: se os dois caírem no
                          // mesmo lugar, quem não pode sumir é o "você está
                          // aqui". Como o marcador da Lua, ele mora fora do
                          // RepaintBoundary dos pontos.
                          Positioned.fill(
                            child: UserMarker(
                              location: _location,
                              mapSize: mapSize,
                              land: _theme.land,
                              background: _theme.background,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // O menu fica por cima do mapa: ele mesmo desenha a barreira de
            // "clicou fora, fechou". Os dados da Lua não estão aqui — aparecem
            // no overlay do marcador, dentro do mapa. A localização aparece
            // SÓ quando não há posição: aí a linha diz o motivo (sem ela, um
            // ponto que não surge seria uma falha silenciosa).
            Positioned.fill(
              child: SettingsMenu(
                theme: _theme,
                onThemeSelected: (theme) => setState(() => _theme = theme),
                includeTwilight: _includeTwilight,
                onTwilightChanged: (value) =>
                    setState(() => _includeTwilight = value),
                locationNotice: _location?.notice,
                cities: _catalog,
                savedCityIds: {for (final clock in _cities) clock.city.id},
                onCityToggled: _toggleSavedCity,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
