import 'package:cloud_firestore/cloud_firestore.dart';

class TrainingInsight {
  final String id;
  final DateTime createdAt;
  final String overallInsight; // エージェント思考ログに相当するAIの推論
  final List<EventPrediction> predictions;
  final List<String> agentThinkingSteps; // 推論のステップ（思考の断片）

  TrainingInsight({
    required this.id,
    required this.createdAt,
    required this.overallInsight,
    required this.predictions,
    required this.agentThinkingSteps,
  });

  Map<String, dynamic> toMap() {
    return {
      'createdAt': Timestamp.fromDate(createdAt),
      'overallInsight': overallInsight,
      'predictions': predictions.map((p) => p.toMap()).toList(),
      'agentThinkingSteps': agentThinkingSteps,
    };
  }

  factory TrainingInsight.fromMap(Map<String, dynamic> map, String id) {
    return TrainingInsight(
      id: id,
      createdAt: map['createdAt'] != null ? (map['createdAt'] as Timestamp).toDate() : DateTime.now(),
      overallInsight: map['overallInsight'] ?? '',
      predictions: (map['predictions'] as List<dynamic>?)
              ?.map((p) => EventPrediction.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
      agentThinkingSteps: List<String>.from(map['agentThinkingSteps'] ?? []),
    );
  }
}

class EventPrediction {
  final String eventName;
  final String predictedTime;
  final String confidenceInterval;
  final double successRate;
  final List<LapPrediction> laps;
  final String specificInsight;

  EventPrediction({
    required this.eventName,
    required this.predictedTime,
    required this.confidenceInterval,
    required this.successRate,
    required this.laps,
    required this.specificInsight,
  });

  Map<String, dynamic> toMap() {
    return {
      'eventName': eventName,
      'predictedTime': predictedTime,
      'confidenceInterval': confidenceInterval,
      'successRate': successRate,
      'laps': laps.map((l) => l.toMap()).toList(),
      'specificInsight': specificInsight,
    };
  }

  factory EventPrediction.fromMap(Map<String, dynamic> map) {
    return EventPrediction(
      eventName: map['eventName'] ?? '',
      predictedTime: map['predictedTime'] ?? '',
      confidenceInterval: map['confidenceInterval'] ?? '',
      successRate: (map['successRate'] as num?)?.toDouble() ?? 0.0,
      laps: (map['laps'] as List<dynamic>?)
              ?.map((l) => LapPrediction.fromMap(l as Map<String, dynamic>))
              .toList() ??
          [],
      specificInsight: map['specificInsight'] ?? '',
    );
  }
}

class LapPrediction {
  final String section;
  final String time;
  final int strokeCount;

  LapPrediction({
    required this.section,
    required this.time,
    required this.strokeCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'section': section,
      'time': time,
      'strokeCount': strokeCount,
    };
  }

  factory LapPrediction.fromMap(Map<String, dynamic> map) {
    return LapPrediction(
      section: map['section'] ?? '',
      time: map['time'] ?? '',
      strokeCount: (map['strokeCount'] as num?)?.toInt() ?? 0,
    );
  }
}
