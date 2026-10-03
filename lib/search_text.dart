/// Dobra de texto para busca: minúsculas e sem acento.
///
/// A busca do catálogo tem de achar "São Paulo" quando o usuário tecla
/// `sao paulo`: obrigar a acentuar numa caixa de busca é atrito que não se
/// justifica. A mesma dobra serve para o nome da cidade, a região e o país,
/// então o casamento é simétrico (não existe "só o alvo é dobrado").
library;

/// Letras acentuadas → equivalente ASCII, para o latim que o catálogo
/// realmente usa (português, espanhol, francês, alemão, nórdico, polonês,
/// tcheco e turco). O que não estiver aqui passa intacto — melhor uma busca
/// que erra o acento exótico do que uma tabela enorme e frágil.
const Map<String, String> _foldedLetters = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ď': 'd',
  'đ': 'd',
  'ð': 'd',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ě': 'e',
  'ē': 'e',
  'ė': 'e',
  'ę': 'e',
  'ğ': 'g',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'į': 'i',
  'ı': 'i',
  'ł': 'l',
  'ĺ': 'l',
  'ľ': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ş': 's',
  'ș': 's',
  'ß': 'ss',
  'ť': 't',
  'ț': 't',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ů': 'u',
  'ū': 'u',
  'ű': 'u',
  'ų': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
  'æ': 'ae',
  'œ': 'oe',
  'þ': 'th',
};

/// A tabela indexada por ponto de código, montada uma vez a partir da tabela
/// legível acima (o laço de dobra roda sobre dezenas de milhares de caracteres
/// e não pode pagar uma busca por String a cada um).
final Map<int, String> _foldTable = {
  for (final entry in _foldedLetters.entries)
    entry.key.runes.first: entry.value,
};

/// [value] em minúsculas, sem acento e com os dígrafos equivalentes.
///
/// A dobra do dígrafo `qu` → `k` existe porque a grafia e a pronúncia divergem
/// em português: "Tóquio" se digita "tokio", "Iorque" se pensa "York". Ela é
/// medida, não chutada — sobre as 7.341 cidades do catálogo, 138 nomes contêm
/// `qu` e a troca NÃO cria nenhuma colisão nova (nove nomes já colidiam antes,
/// por diferirem só no acento). Como a dobra é aplicada dos DOIS lados — alvo e
/// consulta —, "tóquio", "toquio" e "tokio" caem todos no mesmo texto, e
/// nenhuma cidade fica inalcançável.
String foldForSearch(String value) {
  final lowered = value.toLowerCase().replaceAll('qu', 'k');
  final buffer = StringBuffer();
  for (final rune in lowered.runes) {
    buffer.write(_foldTable[rune] ?? String.fromCharCode(rune));
  }
  return buffer.toString();
}
