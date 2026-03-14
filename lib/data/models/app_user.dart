import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String displayName;
  final Map<String, dynamic> baseProfile;
  final String vision;
  final DateTime createdAt;
  final String role; // 'user' or 'admin'

  AppUser({
    required this.uid,
    required this.displayName,
    this.baseProfile = const {},
    this.vision = '',
    this.role = 'user',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) {
    return AppUser(
      uid: uid,
      displayName: map['displayName'] ?? '',
      baseProfile: Map<String, dynamic>.from(map['baseProfile'] ?? {}),
      vision: map['vision'] ?? '',
      role: map['role'] ?? 'user',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'baseProfile': baseProfile,
      'vision': vision,
      'role': role,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
