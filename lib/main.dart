import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'city.dart';
import 'city_catalog.dart';
import 'city_clock.dart';
import 'city_clock_layer.dart';
import 'city_store.dart';
import 'clicked_point.dart';
import 'map_geometry.dart';
import 'map_theme.dart';
import 'moon_marker.dart';
import 'moon_position.dart';
import 'place_lookup.dart';
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
    this.placeLookup,
    this.nameLookup,
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

  /// Como descobrir o que há num ponto clicado no mapa. Nulo (o padrão) monta o
  /// [OfflinePlaceLookup] com o catálogo carregado — o fuso sai sempre dos
  /// polígonos ou da faixa náutica, e o nome da cidade mais próxima.
  final PlaceLookup? placeLookup;

  /// A reserva de NOME exato (a única coisa que usa rede). Nula (o padrão) usa o
  /// `BigDataCloudNameLookup`; os testes injetam uma fonte controlada — ou
  /// deixam a padrão, que sob o `HttpOverrides` do `flutter_test` não alcança a
  /// rede de verdade.
  final PlaceNameLookup? nameLookup;

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

  /// A cidade com o overlay aberto por clique — uma só por vez. O overlay
  /// "sempre visível" é outra coisa: vem de [_pinnedCityIds].
  String? _selectedCityId;

  /// As cidades com o horário sempre visível, sem depender de clique.
  Set<String> _pinnedCityIds = const <String>{};

  /// O ponto que o usuário clicou no mapa, quando há um. Um só por vez: um
  /// clique novo substitui o anterior.
  ClickedPoint? _clickedPoint;

  /// Qual clique é o atual. Cada clique incrementa; uma resposta que chega
  /// depois de outro clique é DESCARTADA — senão o nome de um ponto sobrescreve
  /// o cartão do ponto que o usuário clicou em seguida.
  int _clickGeneration = 0;

  /// Como resolver um ponto clicado. Nasce no [_loadCities], quando o catálogo
  /// chega (é ele que dá o nome de terra firme).
  PlaceLookup? _placeLookup;

  /// A reserva de nome exato. Separada porque só entra DEPOIS da resposta
  /// offline, e nunca pode segurá-la.
  PlaceNameLookup? _nameLookup;

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
      // Ids de cidades que não existem mais no catálogo ficam no conjunto sem
      // efeito nenhum (só é consultado com `contains`), e o próximo `save`
      // limpa.
      _pinnedCityIds = saved.pinned;
      // O clique funciona mesmo sem catálogo: o fuso sai do polígono ou da faixa
      // náutica, que não dependem dele. Só o NOME de terra firme é que fica sem
      // fonte.
      _placeLookup =
          widget.placeLookup ?? OfflinePlaceLookup(catalog: catalog);
      _nameLookup = widget.nameLookup ?? BigDataCloudNameLookup();
    });
  }

  /// Trata um clique no mapa: marca o ponto e responde o que se sabe dele.
  ///
  /// **Duas fases, de propósito.** A primeira é offline e responde a HORA — a
  /// pergunta que o usuário fez — sem esperar rede nenhuma; a segunda pede o
  /// nome exato e o aplica por cima quando (e se) chegar. Numa fase só, um
  /// clique longe de qualquer cidade ficaria segurando o horário por até 5
  /// segundos, que é o pior desfecho possível para um relógio.
  void _clickAt(Offset local, Size mapSize) {
    final point = MapPoint.at(local, mapSize);
    final generation = ++_clickGeneration;

    setState(() {
      _clickedPoint = ClickedPoint(point: point);
      // O clique no mapa fecha o overlay de cidade aberto: a atenção vai para
      // onde o usuário acabou de clicar.
      _selectedCityId = null;
    });

    final lookup = _placeLookup;
    if (lookup == null) {
      return;
    }
    unawaited(() async {
      // Fase 1: offline, imediata.
      final place = await lookup.resolve(point);
      if (!mounted || generation != _clickGeneration) {
        return;
      }
      setState(() => _clickedPoint = ClickedPoint(point: point, place: place));

      // Fase 2: só quando o offline não deu um nome exato. Um nome que já é o
      // lugar do clique não justifica requisição nenhuma.
      final source = _nameLookup;
      if (source == null || (place.name != null && !place.approximate)) {
        return;
      }
      final PlaceName? exact;
      try {
        exact = await source.lookup(point);
      } catch (error) {
        if (kDebugMode) {
          debugPrint('[nome] consulta falhou: $error');
        }
        if (!mounted || generation != _clickGeneration) {
          return;
        }
        // A hora e o nome do catálogo continuam valendo; o motivo fica anotado
        // para o cartão poder explicar a ausência, em vez de ficar mudo.
        setState(
          () => _clickedPoint = ClickedPoint(
            point: point,
            place: place.withNotice('nome exato indisponível'),
          ),
        );
        return;
      }
      if (!mounted || generation != _clickGeneration) {
        return;
      }
      final name = exact;
      if (name == null) {
        return;
      }
      setState(
        () => _clickedPoint = ClickedPoint(
          point: point,
          place: place.withExactName(name),
        ),
      );
    }());
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
        // Retirar a cidade solta o pino: um "sempre visível" de uma cidade que
        // não está mais no mapa não teria onde aparecer.
        _pinnedCityIds = {..._pinnedCityIds}..remove(id);
        if (_selectedCityId == id) {
          _selectedCityId = null;
        }
      } else {
        // Ordem por população, a mesma do catálogo: os marcadores não dançam
        // conforme a ordem em que o usuário escolheu.
        _cities = [..._cities, CityClock(city)]
          ..sort(
            (a, b) => b.city.population.compareTo(a.city.population),
          );
      }
    });
    unawaited(_persistCities());
  }

  /// Liga ou desliga o "horário sempre visível" de uma cidade.
  void _togglePinnedCity(String id) {
    setState(() {
      final pinned = {..._pinnedCityIds};
      if (!pinned.remove(id)) {
        pinned.add(id);
      }
      _pinnedCityIds = pinned;
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
        SavedCities(
          selected: {for (final clock in _cities) clock.city.id},
          pinned: _pinnedCityIds,
        ),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[cidades] falha ao gravar as cidades salvas: $error');
      }
    }
  }

  /// Abre o overlay da cidade clicada; clicar de novo na mesma fecha.
  ///
  /// Não grava: a cidade já está salva (senão não estaria no mapa), e qual
  /// overlay está aberto agora é estado de sessão, não escolha do usuário.
  void _selectCity(String id) {
    setState(() {
      _selectedCityId = _selectedCityId == id ? null : id;
    });
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
                    // O detector envolve EXATAMENTE o retângulo do mapa, então o
                    // `localPosition` do toque já vem no espaço do mapa — não há
                    // conversão global→local em lugar nenhum. E o filho é opaco
                    // (o `ColoredBox` do mapa cobre a área toda), então o toque
                    // em qualquer ponto chega aqui.
                    child: GestureDetector(
                      onTapUp: (details) =>
                          _clickAt(details.localPosition, mapSize),
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
                                background: _theme.background,
                                selectedId: _selectedCityId,
                                pinnedIds: _pinnedCityIds,
                                onSelect: _selectCity,
                                clickedPoint: _clickedPoint,
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
                pinnedCityIds: _pinnedCityIds,
                onCityToggled: _toggleSavedCity,
                onCityPinToggled: _togglePinnedCity,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
