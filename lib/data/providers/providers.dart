import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firestore_service.dart';
import '../models/training_record.dart';
import '../models/personal_best.dart';
import '../models/goal_time.dart';
import '../models/weekly_plan.dart';
import '../models/app_user.dart';
import '../models/training_insight.dart';
import '../services/gemini_service.dart';

final firestoreServiceProvider = Provider((ref) => FirestoreService());

// ユーザープロフィール
final userProfileProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final stream = ref.watch(firestoreServiceProvider).getUserProfileStream();
  // 管理者の場合、設定を自動ロードする副作用を追加
  stream.listen((user) {
    if (user?.role == 'admin') {
      GeminiService().ensureSettingsLoaded(isAdmin: true);
    }
  });
  return stream;
});

// 練習記録 (最新50件)
final trainingRecordsProvider = StreamProvider.autoDispose<List<TrainingRecord>>((ref) {
  return ref.watch(firestoreServiceProvider).getTrainingRecordsStream(limit: 50);
});

// 自己ベスト
final personalBestsProvider = StreamProvider.autoDispose<List<PersonalBest>>((ref) {
  return ref.watch(firestoreServiceProvider).getPersonalBestsStream();
});

// 目標タイム
final goalTimesProvider = StreamProvider.autoDispose<List<GoalTime>>((ref) {
  return ref.watch(firestoreServiceProvider).getGoalTimesStream();
});

// 最新の週間計画
final latestWeeklyPlanProvider = StreamProvider.autoDispose<WeeklyPlan?>((ref) {
  return ref.watch(firestoreServiceProvider).getLatestWeeklyPlanStream();
});

// --- カテゴリ別レコードProvider (Computed) ---

// プール練習記録のみ
final poolRecordsProvider = Provider.autoDispose<List<TrainingRecord>>((ref) {
  final allRecords = ref.watch(trainingRecordsProvider).value ?? [];
  return allRecords.where((r) => r.type == 'pool').toList();
});

// 陸上トレーニング記録のみ
final drylandRecordsProvider = Provider.autoDispose<List<TrainingRecord>>((ref) {
  final allRecords = ref.watch(trainingRecordsProvider).value ?? [];
  return allRecords.where((r) => r.type == 'dryland').toList();
});

// 食事記録のみ（体組成フラグが立っていないもの）
final dailyNutritionRecordsProvider = Provider.autoDispose<List<TrainingRecord>>((ref) {
  final allRecords = ref.watch(trainingRecordsProvider).value ?? [];
  return allRecords.where((r) => 
    r.type == 'nutrition' && 
    r.subjectiveMetrics['is_body_composition'] != true
  ).toList();
});

// 睡眠記録のみ
final sleepRecordsProvider = Provider.autoDispose<List<TrainingRecord>>((ref) {
  final allRecords = ref.watch(trainingRecordsProvider).value ?? [];
  return allRecords.where((r) => r.type == 'sleep').toList();
});

// 体組成記録のみ
final bodyCompositionRecordsProvider = Provider.autoDispose<List<TrainingRecord>>((ref) {
  final allRecords = ref.watch(trainingRecordsProvider).value ?? [];
  return allRecords.where((r) => 
    r.type == 'body_composition' || 
    (r.type == 'nutrition' && r.subjectiveMetrics['is_body_composition'] == true)
  ).toList();
});

// 実効日（朝4時切り替え）ごとにグルーピングされたレコード
final recordsByEffectiveDayProvider = Provider.autoDispose<Map<String, List<TrainingRecord>>>((ref) {
  final allRecords = ref.watch(trainingRecordsProvider).value ?? [];
  final Map<String, List<TrainingRecord>> grouped = {};
  for (var r in allRecords) {
    // 4時前なら前日扱いにする判定（FirestoreService にあるロジックを流用）
    final effectiveDate = r.date.hour < 4 ? r.date.subtract(const Duration(days: 1)) : r.date;
    final key = "${effectiveDate.year}-${effectiveDate.month}-${effectiveDate.day}";
    grouped.putIfAbsent(key, () => []).add(r);
  }
  return grouped;
});

// --- ロジックProvider (Computed) ---

// 今日の記録
final todayRecordsProvider = Provider.autoDispose<List<TrainingRecord>>((ref) {
  final allRecords = ref.watch(trainingRecordsProvider).value ?? [];
  return allRecords.where((record) {
    return FirestoreService.isSameEffectiveDay(DateTime.now(), record.date);
  }).toList();
});

// 自己ベストのカテゴライズ（最新）
final categorizedPbsProvider = Provider.autoDispose<Map<String, Map<String, PersonalBest>>>((ref) {
  final allPbs = ref.watch(personalBestsProvider).value ?? [];
  final Map<String, PersonalBest> swim = {};
  final Map<String, PersonalBest> dryland = {};
  
  for (var pb in allPbs.reversed) {
    if (pb.category == 'swim') {
      swim[pb.event] = pb;
    } else if (pb.category == 'dryland') {
      dryland[pb.event] = pb;
    }
  }
  return {'swim': swim, 'dryland': dryland};
});

// 自己ベストの履歴（種目別リスト）
final pbHistoryProvider = Provider.autoDispose<Map<String, Map<String, List<PersonalBest>>>>((ref) {
  final allPbs = ref.watch(personalBestsProvider).value ?? [];
  final Map<String, List<PersonalBest>> swim = {};
  final Map<String, List<PersonalBest>> dryland = {};
  
  for (var pb in allPbs) {
    if (pb.category == 'swim') {
      swim.putIfAbsent(pb.event, () => []).add(pb);
    } else if (pb.category == 'dryland') {
      dryland.putIfAbsent(pb.event, () => []).add(pb);
    }
  }
  return {'swim': swim, 'dryland': dryland};
});

/// AIコーチ用のシステム指示コンテキストを生成するProvider
final coachSystemContextProvider = Provider.autoDispose<String>((ref) {
  final user = ref.watch(userProfileProvider).value;
  final records = ref.watch(trainingRecordsProvider).value ?? [];
  final pbs = ref.watch(personalBestsProvider).value ?? [];
  final goals = ref.watch(goalTimesProvider).value ?? [];

  if (user == null) return "ユーザー情報がありません。";

  final bodyCompRecords = records.where((r) => r.type == 'body_composition').toList();
  final nutritionRecords = records.where((r) => r.type == 'nutrition').toList();
  final sleepRecords = records.where((r) => r.type == 'sleep').toList();

  String bodyCompText = bodyCompRecords.isEmpty ? "なし" : bodyCompRecords.take(5).map((r) => 
    "- ${r.date.toIso8601String().substring(0,10)}: 体重 ${r.subjectiveMetrics['weight']}kg, 体脂肪 ${r.subjectiveMetrics['body_fat']}%").join('\n');
    
  String nutritionText = nutritionRecords.isEmpty ? "なし" : nutritionRecords.take(10).map((r) {
    final detail = r.details.firstWhere((d) => d['type'] == 'memo', orElse: () => {'content': ''});
    final mealLabel = r.subjectiveMetrics['meal_label'] ?? '不明';
    return "- ${r.date.toIso8601String().substring(0,10)} ($mealLabel): ${detail['content']}";
  }).join('\n');
  
  String pbText = pbs.isEmpty ? "なし" : pbs.map((pb) => "- ${pb.event}: ${pb.value}").join('\n');
  String goalText = goals.isEmpty ? "なし" : goals.map((g) => "- ${g.event}: ${g.value}").join('\n');
  
  String sleepText = sleepRecords.isEmpty ? "なし" : sleepRecords.take(7).map((r) {
    final hours = (r.durationMinutes / 60).floor();
    final mins = r.durationMinutes % 60;
    return "- ${r.date.toIso8601String().substring(0,10)}: ${hours}時間${mins}分 睡眠";
  }).join('\n');

  return """
[最新のユーザーデータ]
■ 睡眠記録 (直近):
$sleepText

■ 体組成:
$bodyCompText

■ 食事/サプリメント記録:
$nutritionText

■ 自己ベスト:
$pbText

■ 目標タイム:
$goalText
""";
});

// インサイト画面用の統計データを計算・保持するProvider
final insightDataProvider = Provider.autoDispose<Map<String, dynamic>>((ref) {
  final records = ref.watch(trainingRecordsProvider).value ?? [];
  final pbs = ref.watch(personalBestsProvider).value ?? [];
  
  // 種目別の履歴リストを作成
  final Map<String, List<TrainingRecord>> swimEventRecords = {};
  for (var r in records.where((r) => r.type == 'pool')) {
    for (var detail in r.details) {
      final event = detail['event'] as String?;
      if (event != null) {
        swimEventRecords.putIfAbsent(event, () => []).add(r);
      }
    }
  }

  // 体組成の推移データ
  final bodyCompHistory = records.where((r) => r.type == 'body_composition').toList();
  bodyCompHistory.sort((a, b) => a.date.compareTo(b.date));

  return {
    'swimEventRecords': swimEventRecords,
    'bodyCompHistory': bodyCompHistory,
    'allPbs': pbs,
  };
});

// 最新のトレーニングインサイト
final latestInsightProvider = StreamProvider.autoDispose<TrainingInsight?>((ref) {
  return ref.watch(firestoreServiceProvider).getLatestInsightStream();
});

// 本日のAI利用回数
final dailyUsageProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(firestoreServiceProvider).getDailyUsageStream();
});
