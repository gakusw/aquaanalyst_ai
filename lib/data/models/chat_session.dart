import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String text;
  final bool isAi;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isAi,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'isAi': isAi,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      text: map['text'] as String? ?? '',
      isAi: map['isAi'] as bool? ?? false,
      timestamp: (map['timestamp'] as Timestamp).toDate(),
    );
  }
}

class ChatSessionModel {
  final String id;
  final String title;
  final DateTime lastMessageAt;
  final String? systemInstruction;

  ChatSessionModel({
    required this.id,
    required this.title,
    required this.lastMessageAt,
    this.systemInstruction,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'lastMessageAt': Timestamp.fromDate(lastMessageAt),
      'systemInstruction': systemInstruction,
    };
  }

  factory ChatSessionModel.fromMap(Map<String, dynamic> map, String id) {
    return ChatSessionModel(
      id: id,
      title: map['title'] as String? ?? '新しい会話',
      lastMessageAt: (map['lastMessageAt'] as Timestamp? ?? Timestamp.now()).toDate(),
      systemInstruction: map['systemInstruction'] as String?,
    );
  }
}
