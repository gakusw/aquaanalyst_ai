import 'package:cloud_firestore/cloud_firestore.dart';

class GoalTime {
  final String id;
  final String category; // 'swim'
  final String event;    // 例: '100m Fr'
  final double value;    // タイム(秒)
  final DateTime date;   // 目標設定日または目標達成期限日

  GoalTime({
    required this.id,
    required this.category,
    required this.event,
    required this.value,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'event': event,
      'value': value,
      'date': Timestamp.fromDate(date),
    };
  }

  factory GoalTime.fromMap(Map<String, dynamic> map, String id) {
    return GoalTime(
      id: id,
      category: map['category'] ?? 'swim',
      event: map['event'] ?? '',
      value: (map['value'] as num?)?.toDouble() ?? 0.0,
      date: map['date'] != null ? (map['date'] as Timestamp).toDate() : DateTime.now(),
    );
  }
}
