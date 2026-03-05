import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String displayName;
  final Map<String, dynamic> baseProfile;
  final String vision;
  final DateTime createdAt;

  AppUser({
    required this.uid,
    required this.displayName,
    this.baseProfile = const {},
    this.vision = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) {
    return AppUser(
      uid: uid,
      displayName: map['displayName'] ?? '',
      baseProfile: Map<String, dynamic>.from(map['baseProfile'] ?? {}),
      vision: map['vision'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'baseProfile': baseProfile,
      'vision': vision,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
