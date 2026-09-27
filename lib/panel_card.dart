import 'package:flutter/material.dart';

/// O cartão dos painéis flutuantes: a bandeja de opções e o overlay da Lua.
///
/// A largura sai do CONTEÚDO ([IntrinsicWidth]), **nunca** de uma constante —
/// no `flutter test` a fonte default desenha 1 em por caractere, então largura
/// fixa lá vira reticências; e no app real um rótulo mais longo que o previsto
/// seria cortado em silêncio.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.background,
    required this.children,
  });

  /// Fundo do tema em uso: o cartão é esse fundo um degrau mais claro, então o
  /// painel acompanha o tema em vez de ter cor própria.
  final Color background;

  final List<Widget> children;

  /// Fio de contorno: sem ele o cartão some no fundo escuro do mapa.
  static final Color hairline = Colors.white.withValues(alpha: 0.14);

  /// Texto principal do painel.
  static final Color textColor = Colors.white.withValues(alpha: 0.92);

  /// Rótulos e textos secundários.
  static final Color dimTextColor = Colors.white.withValues(alpha: 0.55);

  /// A cor do cartão para um [background] de tema.
  static Color cardColor(Color background) =>
      Color.alphaBlend(Colors.white.withValues(alpha: 0.07), background);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cardColor(background),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // Stretch: todas as linhas ficam com a largura da mais larga, então
          // os valores ficam alinhados à direita.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Linha de dados de um painel: rótulo à esquerda, valor à direita.
///
/// Sem `GestureDetector`/cursor de clique de propósito: são dados, não opções —
/// o cursor de mão aqui prometeria um clique que não existe.
class PanelInfoRow extends StatelessWidget {
  const PanelInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.dimValue = false,
  });

  final String label;
  final String value;

  /// Valor em tom secundário (para data/hora, por exemplo).
  final bool dimValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: PanelCard.dimTextColor),
          ),
          const SizedBox(width: 20),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: dimValue ? PanelCard.dimTextColor : PanelCard.textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Número com vírgula decimal (pt-BR) e [decimals] casas.
String formatDecimal(double value, [int decimals = 1]) =>
    value.toStringAsFixed(decimals).replaceAll('.', ',');

/// Inteiro com ponto de milhar: `375.478`.
String formatThousands(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write('.');
    }
    out.write(digits[i]);
  }
  return out.toString();
}

/// Data curta do calendário local: `18/10/2026`.
///
/// Data **local** e não UTC: sem a hora, um carimbo UTC cairia no dia anterior
/// quando a sizígia acontece de madrugada em UTC (00:00–03:00 UTC é 21:00–24:00
/// em Brasília) — o dia que o usuário vê no calendário dele é o local.
String formatDate(DateTime when) {
  final local = when.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}
