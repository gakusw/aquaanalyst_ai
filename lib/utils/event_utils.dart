/// 種目名や泳法名を正規化し、日本語の正式名称に変換するユーティリティ
class EventUtils {
  /// 略称や揺れのある名称を正式名称に変換する
  /// 例: "Fr 50" -> "自由形 50", "50m Bu" -> "50m バタフライ"
  static String normalizeEventName(String input) {
    if (input.isEmpty) return input;

    String normalized = input;

    // 数値と略称が繋がっている場合にスペースを挿入 (例: 100Fr -> 100 Fr, Fly50 -> Fly 50)
    normalized = normalized.replaceAllMapped(RegExp(r'(\d+)([a-zA-Z]+)', caseSensitive: false), (m) => '${m.group(1)} ${m.group(2)}');
    normalized = normalized.replaceAllMapped(RegExp(r'([a-zA-Z]+)(\d+)', caseSensitive: false), (m) => '${m.group(1)} ${m.group(2)}');

    // 自由形 (Fr, Freel, Free)
    normalized = normalized.replaceAll(RegExp(r'\b(Fr|Freel|Free)\b', caseSensitive: false), '自由形');
    
    // バタフライ (Fly, Bu)
    normalized = normalized.replaceAll(RegExp(r'\b(Fly|Bu)\b', caseSensitive: false), 'バタフライ');
    
    // 背泳ぎ (Ba, Bc, Back)
    normalized = normalized.replaceAll(RegExp(r'\b(Ba|Bc|Back)\b', caseSensitive: false), '背泳ぎ');
    
    // 平泳ぎ (Br, Breast)
    normalized = normalized.replaceAll(RegExp(r'\b(Br|Breast)\b', caseSensitive: false), '平泳ぎ');

    // 個人メドレー (IM)
    normalized = normalized.replaceAll(RegExp(r'\b(IM)\b', caseSensitive: false), '個人メドレー');

    // 数値と 'm' の間のスペースを削除 (例: 100 m -> 100m)
    normalized = normalized.replaceAllMapped(RegExp(r'(\d+)\s+m'), (m) => '${m.group(1)}m');

    // 複数のスペースを1つにまとめ、前後の空白を削除
    normalized = normalized.replaceAll(RegExp(r' {2,}'), ' ').trim();

    // フォーマット調整: "自由形 100m" -> "100m 自由形" のように数値を前に出す
    // ※ ユーザーの好みが分かれる可能性があるが、多くの場合 "100m 自由形" が標準的
    final match = RegExp(r'^([^\d]+)\s+(\d+m)$').firstMatch(normalized);
    if (match != null) {
      final style = match.group(1);
      final dist = match.group(2);
      return '$dist $style';
    }

    return normalized;
  }
}
