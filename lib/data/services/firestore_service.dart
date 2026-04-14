import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/my_menu.dart';
import '../models/training_record.dart';
import '../models/weekly_plan.dart';
import '../models/training_insight.dart';
import '../models/personal_best.dart';
import '../models/chat_session.dart';
import '../models/goal_time.dart';
import '../models/my_product.dart';

import '../services/gemini_service.dart';
import 'dart:typed_data';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GeminiService _gemini = GeminiService();

  /// 画像解析（OCR）を行って分析シートのデータを取得する
  Future<Map<String, dynamic>?> analyzeAnalysisSheetWithGemini(Uint8List imageBytes, String mimeType) async {
    return _gemini.analyzeSwimmingAnalysisSheet(imageBytes, mimeType);
  }

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

    try {
      final doc = await _db.collection('users').doc(uid).get();
      
      if (doc.exists) {
        final existingData = doc.data()!;
        final Map<String, dynamic> updateData = user.toMap();
        
        // baseProfile のマージ方針：
        // 既存のドキュメントにあるフィールド（例: themeMode）を不用意に消さないよう、
        // 既存データをベースに新しいデータでプロパティ単位で上書きする。
        final oldBaseProfile = existingData['baseProfile'] as Map<String, dynamic>? ?? {};
        final newBaseProfile = user.baseProfile;
        
        final mergedProfile = Map<String, dynamic>.from(oldBaseProfile);
        newBaseProfile.forEach((key, value) {
          // 値が null でない限り、空文字であってもユーザーの意図として上書きを許可する。
          mergedProfile[key] = value;
        });
        updateData['baseProfile'] = mergedProfile;

        if (updateData.isNotEmpty) {
          await _db.collection('users').doc(uid).update(updateData);
        }
        return;
      }
    } catch (e) {
      debugPrint('Error during saveUserProfile update: $e');
      // 取得・更新エラー時はフォールバックとして set を試みる
    }

    // 新規作成時、または既存データなし
    await _db.collection('users').doc(uid).set(user.toMap(), SetOptions(merge: true));
  }

  /// ユーザープロフィールの特定フィールドのみを更新
  Future<void> updateUserProfileFields(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  /// 管理者権限のみを付与（既存のプロフィールを破壊しない）
  Future<void> elevateUserToAdmin(String uid) async {
    await updateUserProfileFields(uid, {'role': 'admin'});
  }

  /// ユーザープロパティのAIモデル設定のみを更新する
  Future<void> updateUserAiModel(String uid, String modelId) async {
    await _db.collection('users').doc(uid).update({
      'baseProfile.aiModel': modelId,
    });
  }

  // --- トレーニング・栄養記録関連 ---

  /// 特定の期間の記録を取得するStream
  Stream<List<TrainingRecord>> getTrainingRecordsStream({int limit = 50}) {
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

  /// サマリー用に当日の記録を取得（朝4時リセットを考慮）
  Future<List<TrainingRecord>> getTodayRecords() async {
    final uid = currentUserId;
    if (uid == null) return [];

    final range = getEffectiveDayRange(DateTime.now());
    final startOfRange = range['start']!;
    final endOfRange = range['end']!;

    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('training_records')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfRange))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfRange))
        .get();

    return snapshot.docs.map((doc) => TrainingRecord.fromMap(doc.data(), doc.id)).toList();
  }

  /// 朝4時を基準とした「実効的な1日」の開始と終了を返す。
  /// 例: 3/10 03:00 (JST) の場合、実効的な1日は 3/09 04:00 ～ 3/10 03:59:59。
  static Map<String, DateTime> getEffectiveDayRange(DateTime time) {
    DateTime start;
    if (time.hour < 4) {
      // 00:00 - 03:59 の間は前日の4:00が開始
      start = DateTime(time.year, time.month, time.day - 1, 4, 0, 0);
    } else {
      // 04:00 以降はその日の4:00が開始
      start = DateTime(time.year, time.month, time.day, 4, 0, 0);
    }
    final end = start.add(const Duration(hours: 23, minutes: 59, seconds: 59));
    return {'start': start, 'end': end};
  }

  /// 指定した2つの日時が、朝4時リセット基準で同じ「実効的な日」に属するか判定する。
  static bool isSameEffectiveDay(DateTime d1, DateTime d2) {
    final range1 = getEffectiveDayRange(d1);
    final start1 = range1['start']!;
    final end1 = range1['end']!;
    return d2.isAtSameMomentAs(start1) || (d2.isAfter(start1) && d2.isBefore(end1.add(const Duration(seconds: 1))));
  }

  /// 記録の追加
  Future<String> addTrainingRecord(TrainingRecord record) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    final docRef = await _db
        .collection('users')
        .doc(uid)
        .collection('training_records')
        .add(record.toMap());
    
    return docRef.id;
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

  /// 特定の記録を取得
  Future<TrainingRecord?> getTrainingRecord(String recordId) async {
    final uid = currentUserId;
    if (uid == null) return null;

    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('training_records')
        .doc(recordId)
        .get();

    if (!doc.exists || doc.data() == null) return null;
    return TrainingRecord.fromMap(doc.data()!, doc.id);
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

  // --- レース記録関連 ---

  /// レース記録を保存する
  Future<String> saveRaceRecord(Map<String, dynamic> data) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    final docRef = await _db
        .collection('users')
        .doc(uid)
        .collection('race_records')
        .add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
    return docRef.id;
  }

  /// レース記録の一覧を取得するStream
  Stream<List<Map<String, dynamic>>> getRaceRecordsStream({int limit = 50}) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(uid)
        .collection('race_records')
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList());
  }


  /// レース記録を削除する
  Future<void> deleteRaceRecord(String recordId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('race_records')
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

  /// すべての週間計画を取得するStream
  Stream<List<WeeklyPlan>> getWeeklyPlansStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(uid)
        .collection('weekly_plans')
        .orderBy('startDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => WeeklyPlan.fromMap(doc.data(), doc.id))
            .toList());
  }

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

    final docRef = insight.id.isEmpty
        ? _db.collection('users').doc(uid).collection('training_insights').doc()
        : _db.collection('users').doc(uid).collection('training_insights').doc(insight.id);

    await docRef.set(insight.toMap());
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


  
  /// タイムが以前の自己ベストより速い場合、または記録がない場合に自己ベストを更新する
  Future<void> updatePersonalBestIfFaster({
    required String event,
    required double value,
    required DateTime date,
    String category = 'swim',
    String? trainingRecordId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    // 現在のその種目のベスト記録を確認
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('personal_bests')
        .where('category', isEqualTo: category)
        .where('event', isEqualTo: event)
        .get();

    bool isNewBest = true;
    if (snapshot.docs.isNotEmpty) {
      // 全データからベスト値を特定
      final values = snapshot.docs.map((d) => (d.data()['value'] as num).toDouble());
      final currentBest = category == 'swim' 
          ? values.reduce((a, b) => a < b ? a : b)
          : values.reduce((a, b) => a > b ? a : b);

      if (category == 'swim') {
        isNewBest = value < currentBest;
      } else {
        isNewBest = value > currentBest;
      }
    }

    if (isNewBest) {
      await savePersonalBest(PersonalBest(
        id: '', // 自動生成
        category: category,
        event: event,
        value: value,
        date: date,
        trainingRecordId: trainingRecordId,
      ));
    }
  }

  // --- 目標タイム関連 ---

  /// 目標タイムのリストを取得するStream
  Stream<List<GoalTime>> getGoalTimesStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(uid)
        .collection('goal_times')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GoalTime.fromMap(doc.data(), doc.id))
            .toList());
  }

  /// 目標タイムを保存・追加する
  Future<void> saveGoalTime(GoalTime gt) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    final docRef = gt.id.isEmpty 
        ? _db.collection('users').doc(uid).collection('goal_times').doc()
        : _db.collection('users').doc(uid).collection('goal_times').doc(gt.id);

    await docRef.set(gt.toMap(), SetOptions(merge: true));
  }

  /// 目標タイムの削除
  Future<void> deleteGoalTime(String gtId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('goal_times')
        .doc(gtId)
        .delete();
  }

  // --- My食品関連 ---

  /// My食品のリストを取得するStream
  Stream<List<MyProduct>> getMyProductsStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(uid)
        .collection('my_products')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => MyProduct.fromMap(doc.data(), doc.id))
            .toList());
  }

  /// 一度だけMy食品のリストを取得する
  Future<List<MyProduct>> getMyProducts() async {
    final uid = currentUserId;
    if (uid == null) return [];

    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('my_products')
        .orderBy('createdAt', descending: true)
        .get();
        
    return snapshot.docs.map((doc) => MyProduct.fromMap(doc.data(), doc.id)).toList();
  }

  /// My食品を保存・追加する
  Future<void> saveMyProduct(MyProduct product) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    final docRef = product.id.isEmpty 
        ? _db.collection('users').doc(uid).collection('my_products').doc()
        : _db.collection('users').doc(uid).collection('my_products').doc(product.id);

    await docRef.set(product.toMap(), SetOptions(merge: true));
  }

  /// My製品の削除
  Future<void> deleteMyProduct(String productId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('my_products')
        .doc(productId)
        .delete();
  }

  // --- チャットセッション関連 ---

  /// チャットセッション一覧を取得するStream
  Stream<List<ChatSessionModel>> getChatSessionsStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatSessionModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  /// 特定のセッションのメッセージ一覧を取得するStream
  Stream<List<ChatMessage>> getChatMessagesStream(String sessionId) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .doc(sessionId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessage.fromMap(doc.data()))
            .toList());
  }

  Future<String> createChatSession({required String title, String? systemInstruction}) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    final docRef = await _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .add({
      'title': title,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'systemInstruction': systemInstruction,
    });

    return docRef.id;
  }

  /// 指定したIDでチャットセッションを保存または上書きする
  Future<void> saveChatSession(ChatSessionModel session) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .doc(session.id)
        .set(session.toMap());
  }

  /// チャットセッションにメッセージを追加する
  Future<void> saveChatMessage(String sessionId, ChatMessage message) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .doc(sessionId)
        .collection('messages')
        .add(message.toMap());

    // 最終更新日を更新
    await _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .doc(sessionId)
        .update({'lastMessageAt': FieldValue.serverTimestamp()});
  }

  /// チャットセッションのタイトルを更新する
  Future<void> updateChatSessionTitle(String sessionId, String newTitle) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    await _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .doc(sessionId)
        .update({'title': newTitle});
  }

  /// チャットセッションを削除する
  Future<void> deleteChatSession(String sessionId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    final sessionRef = _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .doc(sessionId);

    // サブコレクション（messages）もバッチ処理で完全に削除する
    final messagesSnapshot = await sessionRef.collection('messages').get();
    final batch = _db.batch();

    for (var doc in messagesSnapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(sessionRef);

    await batch.commit();
  }

  /// ホームチャット（ID: home_chat）の存在を確認し、なければ作成する
  Future<void> ensureHomeChatExists() async {
    final uid = currentUserId;
    if (uid == null) return;

    final docRef = _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .doc('home_chat');

    final doc = await docRef.get();
    if (!doc.exists) {
      await docRef.set({
        'title': 'ホームチャット',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'systemInstruction': 'あなたは競泳コーチです。日々の練習についてのアドバイスを丁寧に行ってください。',
      });
    }
  }

  /// 本日の利用回数をインクリメントする (デバッグ用)
  Future<void> incrementDailyUsage() async {
    final uid = currentUserId;
    if (uid == null) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final ref = _db.collection('users').doc(uid).collection('usage').doc(today);
    await ref.set({
      'count': FieldValue.increment(1),
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 本日の利用回数をクリアする (管理者用リセット)
  Future<void> clearDailyUsage() async {
    final uid = currentUserId;
    if (uid == null) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _db.collection('users').doc(uid).collection('usage').doc(today).delete();
  }

  /// 本日の利用回数を取得する
  Stream<int> getDailyUsageStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(0);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _db.collection('users').doc(uid).collection('usage').doc(today).snapshots().map((doc) {
      if (!doc.exists) return 0;
      return (doc.data()?['count'] as num?)?.toInt() ?? 0;
    });
  }

  // --- グローバル統計 (管理者用) ---

  /// グローバルなAI利用統計をインクリメントする
  Future<void> incrementGlobalUsage(String modelId, {int inputTokens = 0, int outputTokens = 0}) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final batch = _db.batch();

    // 1. 日別統計
    final dailyRef = _db.collection('system_stats').doc('gemini_daily').collection('days').doc(today);
    batch.set(dailyRef, {
      'total_requests': FieldValue.increment(1),
      'models': {
        modelId: {
          'requests': FieldValue.increment(1),
          'input_tokens': FieldValue.increment(inputTokens),
          'output_tokens': FieldValue.increment(outputTokens),
        }
      },
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2. 累計統計
    final totalRef = _db.collection('system_stats').doc('gemini_total');
    batch.set(totalRef, {
      'total_requests': FieldValue.increment(1),
      'models': {
        modelId: {
          'requests': FieldValue.increment(1),
          'input_tokens': FieldValue.increment(inputTokens),
          'output_tokens': FieldValue.increment(outputTokens),
        }
      },
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// 本日のグローバル統計を取得する
  Stream<Map<String, dynamic>> getGlobalDailyUsageStream() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _db.collection('system_stats').doc('gemini_daily').collection('days').doc(today).snapshots().map((doc) => doc.data() ?? {});
  }

  /// 累計のグローバル統計を取得する
  Stream<Map<String, dynamic>> getGlobalTotalUsageStream() {
    return _db.collection('system_stats').doc('gemini_total').snapshots().map((doc) => doc.data() ?? {});
  }

  /// グローバル統計をリセットする (実務上は慎重に)
  Future<void> resetGlobalTotalUsage() async {
    await _db.collection('system_stats').doc('gemini_total').delete();
  }

  /// メッセージを追加する
  Future<void> addChatMessage(String sessionId, ChatMessage message) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    final batch = _db.batch();
    
    final messageRef = _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .doc(sessionId)
        .collection('messages')
        .doc();
    
    batch.set(messageRef, message.toMap());
    
    final sessionRef = _db
        .collection('users')
        .doc(uid)
        .collection('chat_sessions')
        .doc(sessionId);
    
    batch.update(sessionRef, {
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// 種目名を正規化するヘルパー。
  /// 括弧とその中身を除去し、前後の空白をトリムする。
  static String _normalizeExerciseName(String name) {
    return name
        .replaceAll(RegExp(r'[\(（][^)）]*[\)）]'), '') // 括弧とその中身を除去
        .replaceAll(RegExp(r'\d+セット目|set\s*\d+|回目|第\d+'), '') // セット情報除去
        .trim();
  }

  /// 正規化後の種目名が有効かどうかを判定する。
  static bool _isValidExerciseName(String name) {
    if (name.isEmpty || name.length < 2) return false;
    if (name.contains('セット') || name.contains('回') || name.contains('種目')) return false;
    if (name.length > 20) return false;
    // 記号のみの名前を除外（例: °)、・、etc.）
    if (RegExp(r'^[^\p{L}]+$', unicode: true).hasMatch(name)) return false;
    return true;
  }

  /// 陸上トレーニングのすべての履歴をスキャンし、各エクササイズの最大重量を計算して
  /// 自己ベスト（PersonalBest）として全件再構築する。
  /// トレーニング記録の削除・更新時にも呼び出すことで同期を保証する。
  Future<void> generateInitialDrylandPbs() async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');

    // 1. 既存のdryland PBをすべて削除（全件再構築のため）
    final existingPbSnapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('personal_bests')
        .where('category', isEqualTo: 'dryland')
        .get();

    final deleteBatch = _db.batch();
    for (var doc in existingPbSnapshot.docs) {
      deleteBatch.delete(doc.reference);
    }
    await deleteBatch.commit();

    // 2. 過去のすべてのトレーニング記録（drylandのみ）を取得
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('training_records')
        .where('type', isEqualTo: 'dryland')
        .get();

    if (snapshot.docs.isEmpty) return;

    // 種目ごとの最大重量とその達成日を保持するマップ
    final Map<String, _BestRecord> bestRecords = {};

    final RegExp legacyWeightRegex = RegExp(r'([^\d\s\n:：,、.。\+\-\*\/×÷]+)[\s　]*(?:\d+セット目|set\s*\d+)?[\s　]*(\d+\.?\d*)[\s　]*kg', caseSensitive: false);

    for (var doc in snapshot.docs) {
      final record = TrainingRecord.fromMap(doc.data(), doc.id);
      final detailsList = record.details as List<dynamic>? ?? [];
      
      // 2.1 構造化データ (dryland_set) からの抽出を優先
      final drylandSets = detailsList.where((d) => d['type'] == 'dryland_set').toList();
      
      if (drylandSets.isNotEmpty) {
        for (var set in drylandSets) {
          final rawName = set['exercise']?.toString().trim() ?? '';
          final weight = (set['weight'] as num?)?.toDouble() ?? 0.0;
          final eventName = _normalizeExerciseName(rawName);
          
          if (_isValidExerciseName(eventName) && weight > 0) {
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
          final rawName = match.group(1)?.trim() ?? '';
          final weightStr = match.group(2);
          final eventName = _normalizeExerciseName(rawName);
          
          if (weightStr != null && _isValidExerciseName(eventName)) {
            final weight = double.tryParse(weightStr);
            if (weight != null && weight > 0) {
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

    // 3. 新しいPBを一括作成
    final createBatch = _db.batch();
    for (final entry in bestRecords.entries) {
      final newPbRef = _db.collection('users').doc(uid).collection('personal_bests').doc();
      final newPb = PersonalBest(
        id: newPbRef.id,
        category: 'dryland',
        event: entry.key,
        value: entry.value.weight,
        date: entry.value.date,
      );
      createBatch.set(newPbRef, newPb.toMap());
    }
    await createBatch.commit();
  }

  // --- システム設定関連 (管理者用) ---

  /// システム設定を取得するStream
  Stream<Map<String, dynamic>> getSystemSettingsStream() {
    return _db.collection('system_settings').doc('ai_config').snapshots().map((snapshot) {
      return snapshot.data() ?? {};
    });
  }

  /// システム設定を取得する (単発)
  Future<Map<String, dynamic>> getSystemSettings() async {
    final snapshot = await _db.collection('system_settings').doc('ai_config').get();
    return snapshot.data() ?? {};
  }

  /// システム設定を保存する
  Future<void> saveSystemSettings(Map<String, dynamic> settings) async {
    await _db.collection('system_settings').doc('ai_config').set(settings, SetOptions(merge: true));
  }

  // --- 統計ダッシュボード用 ---

  /// 総ユーザー数を取得
  Future<int> getTotalUserCount() async {
    try {
      final snapshot = await _db.collection('users').count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('Error counting users: $e');
      return 0;
    }
  }

  /// 直近7日以内の新規登録ユーザー数を取得
  Future<int> getNewUserCountThisWeek() async {
    try {
      final oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
      final snapshot = await _db
          .collection('users')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(oneWeekAgo))
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('Error counting new users: $e');
      return 0;
    }
  }

  /// トレーニングインサイト（履歴）を取得するStream
  Stream<List<TrainingInsight>> getTrainingInsightsStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('users')
        .doc(uid)
        .collection('training_insights')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TrainingInsight.fromMap(doc.data(), doc.id))
            .toList());
  }

  // --- My Menus ---

  Stream<List<MyMenu>> getMyMenusStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('users')
        .doc(uid)
        .collection('my_menus')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => MyMenu.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<void> saveMyMenu(MyMenu menu) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');
    
    if (menu.id.isEmpty) {
      await _db.collection('users').doc(uid).collection('my_menus').add(menu.toMap());
    } else {
      await _db.collection('users').doc(uid).collection('my_menus').doc(menu.id).update(menu.toMap());
    }
  }

  Future<void> deleteMyMenu(String menuId) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('ログインしていません');
    await _db.collection('users').doc(uid).collection('my_menus').doc(menuId).delete();
  }
}

class _BestRecord {
  final double weight;
  final DateTime date;
  _BestRecord({required this.weight, required this.date});
}
