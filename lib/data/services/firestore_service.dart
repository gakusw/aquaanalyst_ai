import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import '../models/training_record.dart';
import '../models/weekly_plan.dart';
import '../models/training_insight.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // --- ユーザープロファイル関連 ---
  
  /// ユーザープロフィールの取得Stream
  Stream<AppUser?> getUserProfileStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(null);

    return _db.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return null;
      return AppUser.fromMap(snapshot.data()!, snapshot.id);
    });
  }

  /// ユーザープロフィールの保存・更新
  Future<void> saveUserProfile(AppUser user) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    // uidはドキュメントIDであるためMapのフィールドからは除外してsetする
    await _db.collection('users').doc(uid).set(user.toMap(), SetOptions(merge: true));
  }

  // --- トレーニング・栄養記録関連 ---

  /// 特定の期間の記録を取得するStream
  Stream<List<TrainingRecord>> getTrainingRecordsStream({int limit = 30}) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(uid)
        .collection('training_records')
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TrainingRecord.fromMap(doc.data(), doc.id))
            .toList());
  }

  /// サマリー用に当日の記録を取得（日付で絞り込み）
  Future<List<TrainingRecord>> getTodayRecords() async {
    final uid = currentUserId;
    if (uid == null) return [];

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('training_records')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .get();

    return snapshot.docs.map((doc) => TrainingRecord.fromMap(doc.data(), doc.id)).toList();
  }

  /// 記録の追加
  Future<void> addTrainingRecord(TrainingRecord record) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('training_records')
        .add(record.toMap());
  }

  /// 記録の更新（AIフィードバックの追記など）
  Future<void> updateTrainingRecord(String recordId, Map<String, dynamic> data) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('training_records')
        .doc(recordId)
        .update(data);
  }

  /// 記録の削除
  Future<void> deleteTrainingRecord(String recordId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('training_records')
        .doc(recordId)
        .delete();
  }

  // --- 週間計画関連 ---

  /// 最新の週間計画を取得するStream
  Stream<WeeklyPlan?> getLatestWeeklyPlanStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(null);

    return _db
        .collection('users')
        .doc(uid)
        .collection('weekly_plans')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return WeeklyPlan.fromMap(doc.data(), doc.id);
    });
  }

  /// 週間計画を保存する
  Future<void> saveWeeklyPlan(WeeklyPlan plan) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    // 生成履歴を残すため、常に `createdAt` で作成された別ドキュメントとして保存する
    await _db
        .collection('users')
        .doc(uid)
        .collection('weekly_plans')
        .doc(plan.id) 
        .set(plan.toMap(), SetOptions(merge: true));
  }

  /// 特定の週間計画を削除する（Undo機能用）
  Future<void> deleteWeeklyPlan(String planId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('weekly_plans')
        .doc(planId)
        .delete();
  }

  /// 最新のトレーニングインサイトを取得するStream
  Stream<TrainingInsight?> getLatestInsightStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(null);

    return _db
        .collection('users')
        .doc(uid)
        .collection('training_insights')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return TrainingInsight.fromMap(doc.data(), doc.id);
    });
  }

  /// トレーニングインサイトを保存する
  Future<void> saveTrainingInsight(TrainingInsight insight) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('training_insights')
        .doc(insight.id)
        .set(insight.toMap());
  }
}
