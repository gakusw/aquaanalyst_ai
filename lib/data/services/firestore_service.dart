import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import '../models/training_record.dart';
import '../models/weekly_plan.dart';
import '../models/training_insight.dart';
import '../models/personal_best.dart';

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

  // --- 自己ベスト関連 ---
  
  /// 自己ベストの削除
  Future<void> deletePersonalBest(String pbId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('personal_bests')
        .doc(pbId)
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

  // --- 自己ベスト関連 ---

  /// 自己ベストの履歴を取得するStream
  Stream<List<PersonalBest>> getPersonalBestsStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(uid)
        .collection('personal_bests')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PersonalBest.fromMap(doc.data(), doc.id))
            .toList());
  }

  /// 自己ベストを保存・追加する
  Future<void> savePersonalBest(PersonalBest pb) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    final docRef = pb.id.isEmpty 
        ? _db.collection('users').doc(uid).collection('personal_bests').doc()
        : _db.collection('users').doc(uid).collection('personal_bests').doc(pb.id);

    await docRef.set(pb.toMap(), SetOptions(merge: true));
  }

  /// 陸上トレーニングのすべての履歴をスキャンし、各エクササイズの最大重量を計算して
  /// 自己ベスト（PersonalBest）として一括登録・更新する。
  /// （すでにPBが存在する場合は、履歴の最大重量が上回っている場合のみ更新）
  Future<void> generateInitialDrylandPbs() async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    // 1. 過去のすべてのトレーニング記録（drylandのみ）を取得
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('training_records')
        .where('type', isEqualTo: 'dryland')
        .get();

    if (snapshot.docs.isEmpty) return;

    // 種目ごとの最大重量とその達成日を保持するマップ
    final Map<String, _BestRecord> bestRecords = {};

    // 正規表現の改善: 種目名の後に重量が来るパターン。
    // 括弧内の補助情報は後で正規化する。
    final RegExp legacyWeightRegex = RegExp(r'([^\d\s\n:：,、.。\+\-\*\/×÷]+)[\s　]*(?:\d+セット目|set\s*\d+)?[\s　]*(\d+\.?\d*)[\s　]*kg', caseSensitive: false);

    for (var doc in snapshot.docs) {
      final record = TrainingRecord.fromMap(doc.data(), doc.id);
      final detailsList = record.details as List<dynamic>? ?? [];
      
      // 2.1 構造化データ (dryland_set) からの抽出を優先
      final drylandSets = detailsList.where((d) => d['type'] == 'dryland_set').toList();
      
      if (drylandSets.isNotEmpty) {
        for (var set in drylandSets) {
          final eventName = set['exercise']?.toString().trim();
          final weight = (set['weight'] as num?)?.toDouble() ?? 0.0;
          
          if (eventName != null && eventName.isNotEmpty && weight > 0) {
            // トレーニング名はそのまま使用（括弧等も保持）
            if (!bestRecords.containsKey(eventName) || bestRecords[eventName]!.weight < weight) {
              bestRecords[eventName] = _BestRecord(weight: weight, date: record.date);
            } else if (bestRecords[eventName]!.weight == weight && record.date.isBefore(bestRecords[eventName]!.date)) {
              bestRecords[eventName] = _BestRecord(weight: weight, date: record.date);
            }
          }
        }
      } else {
        // 2.2 構造化データがない場合はテキストから抽出 (互換性維持)
        final fullText = detailsList.map((d) => d['content']?.toString() ?? '').join('\n');
        final matches = legacyWeightRegex.allMatches(fullText);
        for (final match in matches) {
          String eventName = match.group(1)?.trim() ?? '';
          final weightStr = match.group(2);
          
          if (eventName.isNotEmpty && weightStr != null) {
            // 不要な単語やメタ情報のクリーンアップ（括弧はトレーニング名の一部として保持）
            eventName = eventName
                .replaceAll(RegExp(r'\d+セット目|set\s*\d+|回目|第\d+'), '')
                .trim();

            if (eventName.contains('セット') || 
                eventName.contains('回') || 
                eventName.contains('種目') || 
                eventName.length > 20 ||
                eventName.length < 2 || // 1文字以下の誤検知（例: °) ）を排除
                eventName.isEmpty) {
              continue;
            }

            final weight = double.tryParse(weightStr);
            if (weight != null) {
              if (!bestRecords.containsKey(eventName) || bestRecords[eventName]!.weight < weight) {
                bestRecords[eventName] = _BestRecord(weight: weight, date: record.date);
              } else if (bestRecords[eventName]!.weight == weight && record.date.isBefore(bestRecords[eventName]!.date)) {
                bestRecords[eventName] = _BestRecord(weight: weight, date: record.date);
              }
            }
          }
        }
      }
    }

    if (bestRecords.isEmpty) return;

    // 3. 現在の自己ベスト（dryland）を取得
    final pbSnapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('personal_bests')
        .where('category', isEqualTo: 'dryland')
        .get();

    final Map<String, PersonalBest> currentPbs = {};
    for (var doc in pbSnapshot.docs) {
      final pb = PersonalBest.fromMap(doc.data(), doc.id);
      // 同じ種目の最新のPBを保持（日付順に整理）
      if (!currentPbs.containsKey(pb.event) || pb.date.isAfter(currentPbs[pb.event]!.date)) {
        currentPbs[pb.event] = pb;
      }
    }

    // 4. 最大重量が現在のPBを上回っている（または未登録の）場合にのみ新規保存
    final batch = _db.batch();
    bool hasUpdates = false;

    for (final entry in bestRecords.entries) {
      final event = entry.key;
      final best = entry.value;

      final currentPb = currentPbs[event];
      if (currentPb == null || best.weight > currentPb.value) {
        final newPbRef = _db.collection('users').doc(uid).collection('personal_bests').doc();
        final newPb = PersonalBest(
          id: newPbRef.id,
          category: 'dryland',
          event: event,
          value: best.weight,
          date: best.date,
        );
        batch.set(newPbRef, newPb.toMap());
        hasUpdates = true;
      }
    }

    if (hasUpdates) {
      await batch.commit();
    }
  }
}

class _BestRecord {
  final double weight;
  final DateTime date;
  _BestRecord({required this.weight, required this.date});
}
