import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_clock/moon_marker.dart';
import 'package:world_clock/moon_position.dart';
import 'package:world_clock/panel_card.dart';

/// `03/10` → `DateTime(2026, 10, 3)`. O painel mostra SÓ dia e mês; o ano é o dos
/// dados usados nos testes (nenhum caso atravessa a virada do ano).
DateTime _parseDate(String value) {
  final parts = value.split('/').map(int.parse).toList();
  return DateTime(2026, parts[1], parts[0]);
}

/// Uma célula da linha de fases: o ícone (com a fase desenhada) e a data.
typedef _Cell = ({MoonDisc disc, DateTime date});

/// As células da linha de fases, na ordem em que aparecem no painel.
///
/// Os DOIS primeiros discos da árvore são o do mapa e o do cabeçalho do painel;
/// os quatro seguintes são as fases, na mesma ordem das datas do rodapé.
List<_Cell> _phaseCells(WidgetTester tester) {
  final icons = tester
      .widgetList<MoonDisc>(find.byType(MoonDisc))
      .toList()
      .sublist(2);
  final dates = tester
      .widgetList<Text>(find.byType(Text))
      .where((text) => RegExp(r'^\d{2}/\d{2}$').hasMatch(text.data ?? ''))
      .map((text) => _parseDate(text.data!))
      .toList();
  expect(dates.length, icons.length, reason: 'uma data por fase');
  return [
    for (var i = 0; i < icons.length; i++) (disc: icons[i], date: dates[i]),
  ];
}

/// Retângulo na tela de cada data do rodapé — uma por fase, na ordem do painel.
List<Rect> _dateRects(WidgetTester tester) {
  final texts = find.byType(Text).evaluate().toList();
  final rects = <Rect>[];
  for (var i = 0; i < texts.length; i++) {
    final data = (texts[i].widget as Text).data ?? '';
    if (RegExp(r'^\d{2}/\d{2}$').hasMatch(data)) {
      rects.add(tester.getRect(find.byType(Text).at(i)));
    }
  }
  return rects;
}

/// O marcador da Lua: a POSIÇÃO no mapa (a projeção tem de ser a mesma do
/// dataset de pontos), a direção da luz (o lado iluminado aponta para o Sol) e
/// o overlay que abre com o ponteiro em cima do disco.
void main() {
  // Um mapa 2:1 como o do app: 360 pt de largura, 180 pt de altura.
  const mapSize = Size(360, 180);

  /// A Lua real de 2026-09-27 19:00 UTC, com o que o teste quiser trocar.
  final base = MoonPosition.at(DateTime.utc(2026, 9, 27, 19));

  MoonStatus statusWith({
    double? lat,
    double? lon,
    double? sunLat,
    double? sunLon,
    double? illumination,
  }) => MoonStatus(
    subLatDeg: lat ?? base.subLatDeg,
    subLonDeg: lon ?? base.subLonDeg,
    illumination: illumination ?? base.illumination,
    elongationDeg: base.elongationDeg,
    distanceKm: base.distanceKm,
    ageDays: base.ageDays,
    phase: base.phase,
    sunSubLatDeg: sunLat ?? base.sunSubLatDeg,
    sunSubLonDeg: sunLon ?? base.sunSubLonDeg,
    nextFullMoon: base.nextFullMoon,
    nextNewMoon: base.nextNewMoon,
    lastNewMoon: base.lastNewMoon,
    nextHalfMoons: base.nextHalfMoons,
  );

  /// Retângulo do disco DO MAPA — o overlay também tem um disco (a fase em
  /// miniatura), e o do mapa é o primeiro na árvore.
  Rect discRect(WidgetTester tester) =>
      tester.getRect(find.byType(MoonDisc).first);

  group('MoonMarker.offsetFor', () {
    test('cantos e centro caem onde a grade do mapa manda', () {
      // Mesma projeção equirretangular do dataset: (lon+180)/360, (90-lat)/180.
      expect(MoonMarker.offsetFor(-180, 90, mapSize), const Offset(0, 0));
      expect(MoonMarker.offsetFor(180, 90, mapSize), const Offset(360, 0));
      expect(MoonMarker.offsetFor(-180, -90, mapSize), const Offset(0, 180));
      expect(MoonMarker.offsetFor(180, -90, mapSize), const Offset(360, 180));
      expect(MoonMarker.offsetFor(0, 0, mapSize), const Offset(180, 90));
    });

    test('cada grau vale um ponto nos DOIS eixos (célula quadrada)', () {
      // Num mapa 2:1, 1° de longitude = W/360 e 1° de latitude = H/180 = W/360:
      // os dois valem o mesmo em pontos, e é isso que mantém a grade quadrada.
      final a = MoonMarker.offsetFor(0, 0, mapSize);
      final b = MoonMarker.offsetFor(10, 0, mapSize);
      final c = MoonMarker.offsetFor(0, 10, mapSize);
      expect(b.dx - a.dx, closeTo(10, 1e-9), reason: '10° de longitude');
      expect(a.dy - c.dy, closeTo(10, 1e-9), reason: '10° de latitude');
    });
  });

  group('MoonMarker.litTurnRad', () {
    test('Sol a leste do subponto: luz vem da direita (0 rad)', () {
      final status = statusWith(
        sunLat: base.subLatDeg,
        sunLon: base.subLonDeg + 90,
      );
      expect(MoonMarker.litTurnRad(status, mapSize), closeTo(0, 1e-9));
    });

    test('Sol a oeste: luz vem da esquerda (π)', () {
      final status = statusWith(
        sunLat: base.subLatDeg,
        sunLon: base.subLonDeg - 90,
      );
      expect(
        MoonMarker.litTurnRad(status, mapSize).abs(),
        closeTo(3.14159, 1e-4),
      );
    });

    test('Sol ao norte do subponto: luz vem de cima (−π/2)', () {
      final status = statusWith(
        sunLon: base.subLonDeg,
        sunLat: base.subLatDeg + 40,
      );
      expect(MoonMarker.litTurnRad(status, mapSize), closeTo(-1.570796, 1e-5));
    });

    test('a virada de ±180° de longitude não dá meia volta de erro', () {
      // Lua em −179° com Sol em −177° (2° a leste, quase reto para a direita)…
      expect(
        MoonMarker.litTurnRad(
          statusWith(lat: 0, lon: -179, sunLat: 0, sunLon: -177),
          mapSize,
        ),
        closeTo(0, 0.07),
      );
      // …e a Lua vizinha do outro lado da virada dá o mesmo resultado. Sem
      // normalizar a diferença de longitude, uma das duas daria 180° errado.
      expect(
        MoonMarker.litTurnRad(
          statusWith(lat: 0, lon: 179, sunLat: 0, sunLon: 181),
          mapSize,
        ),
        closeTo(0, 0.07),
      );
    });
  });

  group('MoonMarker na tela', () {
    /// Monta o marcador dentro de um Stack de 360×180, como em `main.dart` —
    /// inclusive o `Clip.none`, que é o que deixa o overlay passar da borda do
    /// mapa quando a Lua está colada no limite.
    Future<void> pumpMarker(WidgetTester tester, MoonStatus status) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              key: const ValueKey('mapa'),
              width: mapSize.width,
              height: mapSize.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: MoonMarker(
                      status: status,
                      mapSize: mapSize,
                      background: const Color(0xFF111111),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    /// Adiciona UM ponteiro de mouse (o MouseTracker só aceita um por vez) e o
    /// deixa parado em cima de [target].
    Future<TestGesture> mouseAt(WidgetTester tester, Offset target) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(1, 1));
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pumpAndSettle();
      return gesture;
    }

    testWidgets('o disco cai no ponto exato do mapa', (tester) async {
      // Lua no subponto (0°, 0°) → centro do retângulo do mapa, e o disco não
      // muda isso: o Positioned posiciona pelo CENTRO, não pelo canto.
      await pumpMarker(tester, statusWith(lat: 0, lon: 0));
      expect(find.byType(MoonDisc), findsOneWidget);
      final mapBox = tester.getRect(find.byKey(const ValueKey('mapa')));
      final center = discRect(tester).center;
      expect(center, mapBox.center);

      // Lua a 90° E e 45° S anda exatamente 90 pt e 45 pt a partir dali.
      await pumpMarker(tester, statusWith(lat: -45, lon: 90));
      final moved = discRect(tester).center - center;
      expect(moved.dx, closeTo(90, 0.01), reason: '90° de longitude');
      expect(moved.dy, closeTo(45, 0.01), reason: '45° de latitude');
    });

    testWidgets('o disco tem o diâmetro pedido, centrado no subponto', (
      tester,
    ) async {
      await pumpMarker(tester, statusWith(lat: 0, lon: 0));
      final rect = tester.getRect(find.byType(MoonDisc));
      expect(rect.width, 14);
      expect(rect.height, 14);
      expect(
        rect.center,
        tester.getRect(find.byKey(const ValueKey('mapa'))).center,
      );
    });

    testWidgets('o overlay NÃO aparece com o ponteiro longe do disco', (
      tester,
    ) async {
      await pumpMarker(tester, statusWith(lat: 0, lon: 0));
      expect(find.byType(PanelCard), findsNothing);

      await mouseAt(tester, const Offset(10, 10));
      expect(find.byType(PanelCard), findsNothing);
    });

    testWidgets('o overlay abre com o ponteiro em cima do disco, com os '
        'números do instante', (tester) async {
      await pumpMarker(tester, statusWith(lat: 0, lon: 0));

      await mouseAt(tester, discRect(tester).center);
      expect(find.byType(PanelCard), findsOneWidget);

      // Números de 2026-09-27 19:00 UTC (logo depois da cheia), em pt-BR:
      // vírgula decimal e ponto de milhar.
      expect(
        find.textContaining(RegExp(r'^\d{1,3},\d% iluminada$')),
        findsOneWidget,
      );
      expect(find.text('Fase'), findsOneWidget);
      expect(find.text('Cheia'), findsOneWidget);
      // A idade da Lua saiu do painel: "Desde a lua nova · 16,7 dias" não
      // agregou (pedido do usuário, 27/09/2026) — a linha voltar é a regressão
      // que este teste denuncia.
      expect(find.text('Desde a lua nova'), findsNothing);
      expect(find.textContaining(RegExp(r'^\d{1,2},\d dias$')), findsNothing);
      // A linha de subponto saiu: a coordenada não agrega para quem só quer
      // saber a fase (o subponto continua sendo o que posiciona o marcador).
      expect(find.text('Subponto'), findsNothing);
      expect(find.textContaining(RegExp(r'^\d{3}\.\d{3} km$')), findsOneWidget);
      // As quatro próximas fases — nova, as DUAS de 50% e cheia — com a data SÓ
      // em dia e mês (a hora saiu a pedido do usuário: "não é relevante").
      expect(find.textContaining(RegExp(r'^\d{2}/\d{2}$')), findsNWidgets(4));
      expect(find.textContaining('UTC'), findsNothing);
      // Os rótulos em TEXTO das fases saíram: quem as identifica agora é o
      // desenho do disco (o lado iluminado distingue crescente de minguante).
      for (final label in [
        'Próxima nova',
        'Próxima cheia',
        '50% crescente',
        '50% minguante',
      ]) {
        expect(find.text(label), findsNothing, reason: 'rótulo "$label"');
      }
      // Seis discos: o do mapa, o da fase no cabeçalho e os 4 ícones da linha.
      expect(find.byType(MoonDisc), findsNWidgets(6));
      // As 4 fases ficam lado a lado SEM `Expanded`: quem distribui é o
      // `spaceBetween`, então o primeiro item encosta na borda esquerda do
      // conteúdo e o último na direita — nada de sobra morta nas pontas.
      // A linha de fases ocupa a MESMA faixa de conteúdo das linhas de cima: o
      // primeiro item alinha com os rótulos (`Distância`) e o último com os
      // valores — é o `spaceBetween`, sem sobra morta nas pontas (a borda de
      // 1 pt do cartão entra nas duas medidas e se cancela na comparação).
      final dates = _dateRects(tester);
      expect(dates.length, 4);
      final label = tester.getRect(find.text('Distância'));
      final value = tester.getRect(
        find.textContaining(RegExp(r'^\d{3}\.\d{3} km$')),
      );
      expect(dates.first.left, closeTo(label.left, 0.01));
      expect(dates.last.right, closeTo(value.right, 0.01));
      // Mesma largura para as quatro (toda data é `NN/NN`, cinco caracteres) e
      // vãos iguais: é o vão que separa uma fase da outra, e ele tem de ser
      // visível. A folga de 2 pt cobre o dígito `1`, mais estreito na fonte real.
      for (final rect in dates) {
        expect(rect.width, closeTo(dates.first.width, 2));
      }
      final gaps = [
        for (var i = 1; i < dates.length; i++)
          dates[i].left - dates[i - 1].right,
      ];
      for (final gap in gaps) {
        expect(gap, closeTo(gaps.first, 0.01), reason: 'vãos diferentes');
      }
      expect(gaps.first, greaterThan(12), reason: 'fases coladas uma na outra');
      expect(find.byType(Expanded), findsNothing);
    });

    testWidgets('as quatro próximas fases saem em ordem cronológica, com o ícone '
        'de cada fase', (tester) async {
      // 27/09/2026 é minguante: o próximo 50% (03/10) acontece ANTES da próxima
      // nova (10/10). É o caso que denuncia ordem fixa no código (nova, 50%,
      // cheia) em vez de cronológica.
      await pumpMarker(tester, statusWith(lat: 0, lon: 0));
      await mouseAt(tester, discRect(tester).center);

      final events = _phaseCells(tester);
      expect(events.length, 4);
      for (var i = 1; i < events.length; i++) {
        expect(
          events[i - 1].date.isBefore(events[i].date),
          isTrue,
          reason:
              'datas fora de ordem: '
              '${events.map((e) => e.date.day).join(", ")}',
        );
      }

      // O ícone de cada célula é o desenho da fase do evento, na ordem
      // cronológica: 50% minguante (luz à esquerda), nova, 50% crescente (luz à
      // direita) e cheia.
      expect(events.map((e) => e.disc.illumination).toList(), [
        0.5,
        0.0,
        0.5,
        1.0,
      ]);
      expect(events[0].disc.litDirectionRad, closeTo(pi, 1e-9));
      expect(events[2].disc.litDirectionRad, 0);
      // E as quatro células saem do mesmo tamanho (a data é quem manda na
      // largura, e toda data é `NN/NN`).
      final rects = _dateRects(tester);
      expect(rects.length, 4);
      for (final rect in rects) {
        expect(rect.width, closeTo(rects.first.width, 0.01));
      }
      // O nome de cada evento continua no código, para leitor de tela.
      expect(find.bySemanticsLabel('Próxima metade minguante'), findsOneWidget);
      expect(find.bySemanticsLabel('Próxima metade crescente'), findsOneWidget);
      expect(find.bySemanticsLabel('Próxima lua nova'), findsOneWidget);
      expect(find.bySemanticsLabel('Próxima lua cheia'), findsOneWidget);
    });

    testWidgets('o 50% crescente aponta a luz para o outro lado', (
      tester,
    ) async {
      // Na metade crescente do mês o lado iluminado é o da direita (0 rad) —
      // é o que distingue o quarto crescente do minguante no painel sem rótulo.
      final waxing = MoonPosition.at(DateTime.utc(2026, 10, 4));
      expect(waxing.nextHalfMoons.first.waxing, isTrue);
      await pumpMarker(
        tester,
        MoonStatus(
          subLatDeg: 0,
          subLonDeg: 0,
          illumination: 0.3,
          elongationDeg: waxing.elongationDeg,
          distanceKm: waxing.distanceKm,
          ageDays: waxing.ageDays,
          phase: waxing.phase,
          sunSubLatDeg: 0,
          sunSubLonDeg: 0,
          nextFullMoon: waxing.nextFullMoon,
          nextNewMoon: waxing.nextNewMoon,
          lastNewMoon: waxing.lastNewMoon,
          nextHalfMoons: waxing.nextHalfMoons,
        ),
      );
      await mouseAt(tester, discRect(tester).center);

      final events = _phaseCells(tester);
      // Ordem cronológica a partir de 04/10: nova (10/10), 50% crescente (18/10),
      // cheia (26/10) e o 50% minguante seguinte (01/11) — as duas passagens de
      // 50% na mesma linha, uma antes e outra depois da cheia.
      expect(events.map((e) => e.disc.illumination).toList(), [
        0.0,
        0.5,
        1.0,
        0.5,
      ]);
      expect(events[1].disc.litDirectionRad, 0, reason: 'crescente');
      expect(events[3].disc.litDirectionRad, closeTo(pi, 1e-9));
      expect(events.map((e) => e.date.day).toList(), [10, 18, 26, 1]);
      expect(find.bySemanticsLabel('Próxima metade crescente'), findsOneWidget);
    });

    testWidgets('o overlay fecha quando o ponteiro sai do disco', (
      tester,
    ) async {
      await pumpMarker(tester, statusWith(lat: 0, lon: 0));
      final mouse = await mouseAt(tester, discRect(tester).center);
      expect(find.byType(PanelCard), findsOneWidget);

      // Sai para longe do disco E do painel: fecha.
      await mouse.moveTo(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(PanelCard), findsNothing);
      expect(find.byType(MoonDisc), findsOneWidget);
    });

    testWidgets('o overlay não captura o ponteiro: parar em cima dele fecha', (
      tester,
    ) async {
      // O painel é `IgnorePointer` de propósito: sem isso ele apareceria e no
      // mesmo instante roubaria o hover, e ficaria piscando.
      await pumpMarker(tester, statusWith(lat: 0, lon: 0));
      final mouse = await mouseAt(tester, discRect(tester).center);
      final panel = tester.getRect(find.byType(PanelCard));

      await mouse.moveTo(panel.center);
      await tester.pumpAndSettle();
      expect(find.byType(PanelCard), findsNothing);
    });

    testWidgets('o overlay abre para o lado que tem espaço', (tester) async {
      // Um ponteiro só para o teste inteiro: o MouseTracker do flutter_test
      // aceita um mouse por vez (adicionar outro estoura assert).
      final mouse = await mouseAt(tester, const Offset(1, 1));

      // Lua a 175° E: colada na borda direita do mapa, o painel abre para a
      // esquerda (ancorado pelo lado de lá, sem adivinhar a largura).
      await pumpMarker(tester, statusWith(lat: 0, lon: 175));
      await mouse.moveTo(discRect(tester).center);
      await tester.pumpAndSettle();
      var panel = tester.getRect(find.byType(PanelCard));
      expect(
        panel.right,
        lessThan(discRect(tester).left),
        reason: 'abriu para a esquerda',
      );
      expect(panel.width, greaterThan(100), reason: 'painel dimensionado');

      // A 175° W, ao contrário.
      await pumpMarker(tester, statusWith(lat: 0, lon: -175));
      await mouse.moveTo(discRect(tester).center);
      await tester.pumpAndSettle();
      panel = tester.getRect(find.byType(PanelCard));
      expect(
        panel.left,
        greaterThan(discRect(tester).right),
        reason: 'abriu para a direita',
      );

      // O cartão PODE passar da borda do mapa quando o outro lado é estreito
      // (com a fonte larga do flutter_test, sempre passa): é justamente para
      // isso que o Stack do mapa tem `Clip.none` — quem recorta é o Stack de
      // fora, da tela. O que não pode é o painel cobrir o disco (teste acima).
    });

    testWidgets('o overlay nunca cobre o disco da Lua', (tester) async {
      // Em qualquer quadrante, o painel fica fora do disco — se ele cobrisse o
      // marcador, o ponteiro sairia do MouseRegion e o painel piscaria.
      final mouse = await mouseAt(tester, const Offset(1, 1));
      for (final lon in [-175.0, -90.0, 0.0, 90.0, 175.0]) {
        for (final lat in [-80.0, 0.0, 80.0]) {
          await pumpMarker(tester, statusWith(lat: lat, lon: lon));
          await mouse.moveTo(discRect(tester).center);
          await tester.pumpAndSettle();
          final panel = tester.getRect(find.byType(PanelCard));
          expect(
            panel.overlaps(discRect(tester)),
            isFalse,
            reason: 'overlay cobriu o disco em lat=$lat lon=$lon',
          );
        }
      }
    });

    testWidgets('nenhum texto do overlay sai cortado', (tester) async {
      await pumpMarker(tester, statusWith(lat: 0, lon: 0));
      await mouseAt(tester, discRect(tester).center);

      // Cartão dimensionado pelo conteúdo: nem com a fonte do flutter_test
      // (1 em por caractere, bem mais larga que a real) os rótulos e valores
      // cabem inteiros. Largura fixa aqui quebra este teste.
      // São 9 textos: a linha do disco, as 2 linhas de rótulo/valor (Fase e
      // Distância) e as 4 datas da linha de fases — as fases viraram ícone.
      final texts = find.byType(Text).evaluate().toList();
      expect(texts.length, greaterThanOrEqualTo(9));
      for (final element in texts) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '"${(element.widget as Text).data}" não caberia no overlay',
        );
      }
    });

    testWidgets('o disco da fase no overlay é o mesmo desenho do mapa', (
      tester,
    ) async {
      await pumpMarker(tester, statusWith(lat: 0, lon: 0, illumination: 0.25));
      await mouseAt(tester, discRect(tester).center);

      final discs = tester.widgetList<MoonDisc>(find.byType(MoonDisc)).toList();
      expect(discs.length, 6);
      // O primeiro é o do mapa; o segundo é o do cabeçalho do painel — e a
      // iluminação é a mesma, então o desenho da fase é o mesmo nos dois.
      expect(discs.first.illumination, 0.25);
      expect(discs[1].illumination, 0.25);
    });
  });
}
