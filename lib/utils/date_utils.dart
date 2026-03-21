import 'package:intl/intl.dart';

class AppDateUtils {
  /// アプリ内での日付が切り替わる時間 (0-23)
  static int logicalDayStartHour = 4;

  /// アプリ内での「現在時刻」を取得します。
  /// 将来的にデバッグや管理者モードで時刻を偽装する場合、ここを拡張します。
  static DateTime get now => DateTime.now();

  static DateTime logicalToday() => getLogicalDate(now);

  /// 指定された日時の「論理的な日付」を返します（午前4時など設定時間までは前日扱い）。
  static DateTime getLogicalDate(DateTime date) {
    if (date.hour < logicalDayStartHour) {
      final previous = date.subtract(const Duration(days: 1));
      return DateTime(previous.year, previous.month, previous.day);
    }
    return DateTime(date.year, date.month, date.day);
  }

  /// グラフ用の日付フォーマットを生成します。
  /// 年の変わり目や、大きな間隔がある場合に年を表示します。
  static String formatChartDate(DateTime date, {DateTime? previousDate}) {
    if (previousDate != null && date.year != previousDate.year) {
      return DateFormat('yyyy/MM/dd').format(date);
    }
    // 年の初め付近（1月）の場合も年を表示すると親切
    if (date.month == 1 && date.day <= 7) {
      return DateFormat('yyyy/MM/dd').format(date);
    }
    return DateFormat('MM/dd').format(date);
  }

  /// ミリ秒からDateTimeに変換し、グラフ用のラベルを返します。
  /// [previousValue] が指定されている場合、年またぎを判定して yyyy/MM/dd を表示します。
  /// また、1月1日以降の最初の記録でも yyyy/MM/dd を表示するようにします。
  static String getChartLabel(double value, {double? previousValue}) {
    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    
    if (previousValue != null) {
      final prevDate = DateTime.fromMillisecondsSinceEpoch(previousValue.toInt());
      // 年が変わった場合
      if (date.year != prevDate.year) {
        return DateFormat('yyyy/MM/dd').format(date);
      }
    } else {
      // 最初のデータで、かつ1月1日〜7日程度なら年を表示（親切心）
      if (date.month == 1 && date.day <= 7) {
        return DateFormat('yyyy/MM/dd').format(date);
      }
    }
    
    return DateFormat('MM/dd').format(date);
  }

  /// グラフ用の月別ラベルを生成します (例: 10月, 2024年 01月)
  static String getMonthlyChartLabel(double value, {double? previousValue}) {
    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    
    // 未来の月は非表示
    final now = DateTime.now();
    if (date.year > now.year || (date.year == now.year && date.month > now.month)) {
      return '';
    }
    
    // 前回表示した月と同じ月なら表示しない (重複回避)
    if (previousValue != null) {
      final prevDate = DateTime.fromMillisecondsSinceEpoch(previousValue.toInt());
      if (date.year == prevDate.year && date.month == prevDate.month) {
        return '';
      }
    }

    // 1月の場合だけ年を表示する
    if (date.month == 1) {
      return DateFormat('yyyy年 MM月').format(date);
    }
    return DateFormat('MM月').format(date);
  }
}
