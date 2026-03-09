/// 種目名や泳法名を正規化し、日本語の正式名称に変換するユーティリティ
class EventUtils {
  /// 略称や揺れのある名称を正式名称に変換する
  /// 例: "Fr 50" -> "自由形 50", "50m Bu" -> "50m バタフライ"
  static String normalizeEventName(String input) {
    if (input.isEmpty) return input;

    String normalized = input;

    // 自由形 (Fr, Freel, Free) - 数値の前後や括弧の前後でも認識するように調整
    normalized = normalized.replaceAll(RegExp(r'\b(Fr|Freel|Free)\b', caseSensitive: false), '自由形');
    
    // バタフライ (Fly, Bu)
    normalized = normalized.replaceAll(RegExp(r'\b(Fly|Bu)\b', caseSensitive: false), 'バタフライ');
    
    // 背泳ぎ (Ba, Bc, Back)
    normalized = normalized.replaceAll(RegExp(r'\b(Ba|Bc|Back)\b', caseSensitive: false), '背泳ぎ');
    
    // 平泳ぎ (Br, Breast)
    normalized = normalized.replaceAll(RegExp(r'\b(Br|Breast)\b', caseSensitive: false), '平泳ぎ');

    // 複数のスペースを1つにまとめ、前後の空白を削除
    return normalized.replaceAll(RegExp(r' {2,}'), ' ').trim();
  }
}
