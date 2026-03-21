import 'package:cloud_firestore/cloud_firestore.dart';

class MyProduct {
  final String id;
  final String name;
  final double protein;
  final double fat;
  final double carbs;
  final double calories;
  final DateTime createdAt;

  MyProduct({
    required this.id,
    required this.name,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.calories,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory MyProduct.fromMap(Map<String, dynamic> map, String id) {
    return MyProduct(
      id: id,
      name: map['name'] ?? '',
      protein: (map['protein'] as num?)?.toDouble() ?? 0.0,
      fat: (map['fat'] as num?)?.toDouble() ?? 0.0,
      carbs: (map['carbs'] as num?)?.toDouble() ?? 0.0,
      calories: (map['calories'] as num?)?.toDouble() ?? 0.0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'protein': protein,
      'fat': fat,
      'carbs': carbs,
      'calories': calories,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
