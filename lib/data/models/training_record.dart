import 'package:cloud_firestore/cloud_firestore.dart';

class TrainingRecord {
  final String id;
  final DateTime date;
  final String type; // "pool", "dryland", "nutrition"
  final int totalMeters;
  final int durationMinutes;
  final List<Map<String, dynamic>> details;
  final Map<String, dynamic> subjectiveMetrics;
  final String? aiFeedback;

  TrainingRecord({
    required this.id,
    required this.date,
    required this.type,
    this.totalMeters = 0,
    this.durationMinutes = 0,
    this.details = const [],
    this.subjectiveMetrics = const {},
    this.aiFeedback,
  });

  factory TrainingRecord.fromMap(Map<String, dynamic> map, String id) {
    return TrainingRecord(
      id: id,
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type: map['type'] ?? 'pool',
      totalMeters: map['totalMeters'] ?? 0,
      durationMinutes: map['durationMinutes'] ?? 0,
      details: List<Map<String, dynamic>>.from(map['details'] ?? []),
      subjectiveMetrics: Map<String, dynamic>.from(map['subjectiveMetrics'] ?? {}),
      aiFeedback: map['aiFeedback'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'type': type,
      'totalMeters': totalMeters,
      'durationMinutes': durationMinutes,
      'details': details,
      'subjectiveMetrics': subjectiveMetrics,
      'aiFeedback': aiFeedback,
    };
  }
}
