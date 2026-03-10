import 'package:cloud_firestore/cloud_firestore.dart';

class DailyPlan {
  final String dateStr; // "3/2 (月)" のような表示用文字列
  final String waterMenu;
  final String dryland;
  final String intensity; // "低", "中", "高", "OFF", "REST"
  final int targetCalories;
  final int targetProtein;
  final int targetFat;
  final int targetCarbs;

  DailyPlan({
    required this.dateStr,
    required this.waterMenu,
    required this.dryland,
    required this.intensity,
    required this.targetCalories,
    this.targetProtein = 0,
    this.targetFat = 0,
    this.targetCarbs = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'dateStr': dateStr,
      'waterMenu': waterMenu,
      'dryland': dryland,
      'intensity': intensity,
      'targetCalories': targetCalories,
      'targetProtein': targetProtein,
      'targetFat': targetFat,
      'targetCarbs': targetCarbs,
    };
  }

  factory DailyPlan.fromMap(Map<String, dynamic> map) {
    return DailyPlan(
      dateStr: map['dateStr'] ?? '',
      waterMenu: map['waterMenu'] ?? '',
      dryland: map['dryland'] ?? '',
      intensity: map['intensity'] ?? '中',
      targetCalories: (map['targetCalories'] ?? 2500).toInt(),
      targetProtein: (map['targetProtein'] ?? 0).toInt(),
      targetFat: (map['targetFat'] ?? 0).toInt(),
      targetCarbs: (map['targetCarbs'] ?? 0).toInt(),
    );
  }
}

class WeeklyPlan {
  final String id;
  final DateTime startDate; // 週の開始日（月曜日など）
  final DateTime endDate;   // 週の終了日（日曜日など）
  final List<DailyPlan> dailyPlans; // 7日分の計画
  final String aiMessage;   // AIからの全体的なコメント
  final DateTime createdAt; // 生成日時（履歴管理用）

  WeeklyPlan({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.dailyPlans,
    required this.aiMessage,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'dailyPlans': dailyPlans.map((d) => d.toMap()).toList(),
      'aiMessage': aiMessage,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory WeeklyPlan.fromMap(Map<String, dynamic> map, String id) {
    return WeeklyPlan(
      id: id,
      startDate: map['startDate'] != null ? (map['startDate'] as Timestamp).toDate() : DateTime.now(),
      endDate: map['endDate'] != null ? (map['endDate'] as Timestamp).toDate() : DateTime.now(),
      dailyPlans: (map['dailyPlans'] as List<dynamic>?)
              ?.map((d) => DailyPlan.fromMap(d as Map<String, dynamic>))
              .toList() ??
          [],
      aiMessage: map['aiMessage'] ?? '',
      createdAt: map['createdAt'] != null ? (map['createdAt'] as Timestamp).toDate() : DateTime.now(),
    );
  }
}
