import 'package:cloud_firestore/cloud_firestore.dart';

class PersonalBest {
  final String id;
  final String category; // 'swim', 'dryland'
  final String event;    // 例: '100m Fr', 'ベンチプレス'
  final double value;    // タイム(秒) または 重量(kg)
  final DateTime date;   // 達成日
  final String? trainingRecordId; // 紐付く詳細記録のID

  PersonalBest({
    required this.id,
    required this.category,
    required this.event,
    required this.value,
    required this.date,
    this.trainingRecordId,
  });

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'event': event,
      'value': value,
      'date': Timestamp.fromDate(date),
      'trainingRecordId': trainingRecordId,
    };
  }

  factory PersonalBest.fromMap(Map<String, dynamic> map, String id) {
    return PersonalBest(
      id: id,
      category: map['category'] ?? '',
      event: map['event'] ?? '',
      value: (map['value'] as num?)?.toDouble() ?? 0.0,
      date: (map['date'] as Timestamp).toDate(),
      trainingRecordId: map['trainingRecordId'],
    );
  }
}
