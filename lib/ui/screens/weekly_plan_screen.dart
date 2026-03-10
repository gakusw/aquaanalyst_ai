import 'package:flutter/material.dart';
import 'dart:convert';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/app_user.dart';
import '../../data/models/weekly_plan.dart';
import '../../data/models/personal_best.dart';
import '../widgets/stable_text_field.dart';

/// 週間トレーニング計画画面
/// コーチとの対話で生成された計画を見やすく表示する
/// また，コーチへの指示となる「週間目標」を編集可能にする
class WeeklyPlanScreen extends StatefulWidget {
  const WeeklyPlanScreen({super.key});

  @override
  State<WeeklyPlanScreen> createState() => _WeeklyPlanScreenState();
}

class _WeeklyPlanScreenState extends State<WeeklyPlanScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _drylController = TextEditingController();
  final TextEditingController _sleepController = TextEditingController();
  late final Stream<WeeklyPlan?> _planStream;
  AppUser? _currentUser;
  bool _isSaving = false;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _planStream = _firestoreService.getLatestWeeklyPlanStream();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final stream = _firestoreService.getUserProfileStream();
      final user = await stream.first;
      if (!mounted) return;
      setState(() {
        _currentUser = user;
        if (user != null) {
          _drylController.text = user.baseProfile['weeklyGoal_dryland'] ?? '週3回（胸・背中・体幹を均等にカバー）';
          _sleepController.text = user.baseProfile['weeklyGoal_sleep'] ?? '7〜8時間 / 日（炭水化物不足のため夜間回復を優先）';
        }
      });
    } catch (e) {
      debugPrint('プロフィールの取得に失敗しました: $e');
    }
  }

  @override
  void dispose() {
    _drylController.dispose();
    _sleepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('週間トレーニング計画'),
        actions: [
          // 元に戻す (Undo) ボタン
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: '直前の計画に戻す',
            onPressed: _undoLastWeeklyPlan,
          ),
          if (_isGenerating)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'コーチに計画を再生成させる',
              onPressed: _generateWeeklyPlan,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 説明カード
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.1),
              border: Border.all(color: Colors.teal.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.psychology, color: Colors.teal, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'コーチ画面でのAIとの対話に基づき生成されました．\n「週間目標」の設定値もコーチの計画立案に参照されます．',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 期間表示と各曜日の計画
          StreamBuilder<WeeklyPlan?>(
            stream: _planStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _buildWeekPlanContent(snapshot.data);
            },
          ),

          const SizedBox(height: 24),

          // ===== 週間目標（コーチへの指示）=====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.08),
              border: Border.all(color: Colors.purple.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_suggest, color: Colors.purpleAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '週間目標を変更すると，次回の計画生成時にAIコーチが参考にします',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isSaving ? null : () async {
                    if (_currentUser == null) return;
                    setState(() => _isSaving = true);
                    try {
                      final updatedProfile = Map<String, dynamic>.from(_currentUser!.baseProfile);
                      updatedProfile['weeklyGoal_dryland'] = _drylController.text;
                      updatedProfile['weeklyGoal_sleep'] = _sleepController.text;
                      
                      final newUser = AppUser(
                        uid: _currentUser!.uid,
                        displayName: _currentUser!.displayName,
                        baseProfile: updatedProfile,
                        vision: _currentUser!.vision,
                        createdAt: _currentUser!.createdAt,
                      );
                      await _firestoreService.saveUserProfile(newUser);
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('週間目標を保存しました')),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isSaving = false);
                      }
                    }
                  },
                  child: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('保存'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 陸上トレーニング目標（編集可能）
          _buildEditableGoalCard(
            icon: Icons.fitness_center,
            color: Colors.greenAccent,
            title: '陸上トレーニング目標',
            controller: _drylController,
            hint: '例: 週2回（胸・体幹中心）',
          ),
          const SizedBox(height: 8),

          // 睡眠・リカバリー目標（編集可能）
          _buildEditableGoalCard(
            icon: Icons.bedtime,
            color: Colors.purpleAccent,
            title: '睡眠・リカバリー目標',
            controller: _sleepController,
            hint: '例: 7時間以上 / 日',
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // 各入力フィールドの状態を固守するためのGlobalKey
  final Map<String, GlobalKey> _fieldKeys = {};

  GlobalKey _getFieldKey(String title) {
    return _fieldKeys.putIfAbsent(title, () => GlobalKey());
  }

  Widget _buildEditableGoalCard({
    required IconData icon,
    required Color color,
    required String title,
    required TextEditingController controller,
    required String hint,
  }) {
    return Card(
      key: _getFieldKey(title),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.2),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StableTextField(
                    controller: controller,
                    lines: 10,
                    hintText: hint,
                    labelText: title,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _currentPlanId; // Undo用に現在のプランIDを保持
  bool _isAutoCopying = false; // 自動繰越の重複実行を防ぐフラグ

  Future<void> _copyPlanToNextWeek(WeeklyPlan oldPlan) async {
    if (_isAutoCopying) return;
    _isAutoCopying = true;
    try {
      final now = DateTime.now();
      final diff = DateTime.monday - now.weekday;
      final nextMonday = now.add(Duration(days: diff <= 0 ? 7 + diff : diff));
      final nextSunday = nextMonday.add(const Duration(days: 6));

      // 前回のデイリープランの `dateStr` から日付部分(例: "(3/2)")を取り除き、曜日だけの状態に正規化する
      final cleanDailyPlans = oldPlan.dailyPlans.map((d) {
        final cleanDateStr = d.dateStr.replaceAll(RegExp(r'\s*\(.*?\)'), '');
        return DailyPlan(
          dateStr: cleanDateStr,
          waterMenu: d.waterMenu,
          dryland: d.dryland,
          intensity: d.intensity,
          targetCalories: d.targetCalories,
        );
      }).toList();

      final newPlan = WeeklyPlan(
        id: '${nextMonday.toIso8601String().split('T').first}_${DateTime.now().millisecondsSinceEpoch}',
        startDate: nextMonday,
        endDate: nextSunday,
        dailyPlans: cleanDailyPlans,
        aiMessage: '【システム自動更新】\n新しい週が始まったため、先週のメニューを自動で繰り越しました。\n新しいメニューを組みたい場合は右上の更新ボタンを押してください。',
        createdAt: DateTime.now(),
      );
      
      await _firestoreService.saveWeeklyPlan(newPlan);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('新しい週のため、前回の計画を自動で引き継ぎました。')));
      }
    } catch (e) {
      debugPrint('自動繰越でのエラー: $e');
    } finally {
      if (mounted) {
        // すぐにフラグを下ろすと画面再描画のタイミングで2重実行される可能性があるため少し待つ
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _isAutoCopying = false;
        });
      }
    }
  }

  Future<void> _undoLastWeeklyPlan() async {
    if (_currentPlanId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('戻せる計画がありません。')));
      return;
    }
    
    // 確認ダイアログ
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('計画を戻す'),
        content: const Text('現在の計画を削除し、1つ前の計画に戻しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('戻す', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    
    if (confirm != true) return;

    try {
      await _firestoreService.deleteWeeklyPlan(_currentPlanId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('1つ前の計画に戻しました。')));
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _generateWeeklyPlan() async {
    if (_currentUser == null) return;
    setState(() => _isGenerating = true);
    try {
      final gemini = GeminiService();
      final targetDryland = _drylController.text;
      final targetSleep = _sleepController.text;
      final profile = _currentUser!.baseProfile.toString();
      final vision = _currentUser!.vision;
      final allPbs = await _firestoreService.getPersonalBestsStream().first;
      
      String pbText = "登録されている自己ベストはありません。";
      if (allPbs.isNotEmpty) {
        final Map<String, PersonalBest> latestPbs = {};
        for (var pb in allPbs.reversed) {
          latestPbs[pb.event] = pb;
        }
        pbText = latestPbs.values.map((pb) => 
          "- ${pb.event}: ${pb.value} ${pb.category == 'swim' ? '秒' : 'kg'} (${pb.date.year}/${pb.date.month}/${pb.date.day})"
        ).join('\n');
      }

      // 共通メソッドを使用してシステム指示（人格）を生成
      final sysInst = gemini.getCoachSystemInstruction(
        _currentUser!,
        supplementaryContext: """
[任務]
あなたは今から、ユーザーの次週月曜日始まりの1週間（7日間）のトレーニング計画を作成します。
出力は必ず指定のJSON形式のみで行ってください。
""",
      );

      final prompt = '''
$sysInst

【現在の状況】
- 最新のプロフィール: $profile
- 最終目標(ビジョン): $vision
- 現在の自己ベスト:
$pbText
- 今週の陸上トレーニング目標: $targetDryland
- 今週の睡眠・リカバリー目標: $targetSleep

【出力フォーマット】
期待される出力は以下のJSONスキーマに従う純粋なJSON文字列のみです。追加のテキストやマークダウンバックティックは含めないでください。
{
  "aiMessage": "コーチとしての今週のアドバイス（あなたの設定された口調で記述してください）",
  "dailyPlans": [
    {
      "dateStr": "月曜日",
      "waterMenu": "W-up 800m...",
      "dryland": "胸・三頭筋...",
      "intensity": "中", 
      "targetCalories": 3200,
      "targetProtein": 150,
      "targetFat": 70,
      "targetCarbs": 450
    }
  ]
}
※targetProtein, targetFat, targetCarbs はその日の合計摂取目標量（g）です。
※トレーニング強度(intensity)が高い日は炭水化物(targetCarbs)を多めに設定するなど、専門的な調整を行ってください。
※dailyPlansは必ず月曜日から日曜日までの7日分を配列で作成してください。
※intensityは必ず "低", "中低", "中", "高", "OFF", "REST" のいずれかにしてください。
''';

      final result = await gemini.generateContent(prompt, responseMimeType: 'application/json');
      if (result != null) {
        // 先頭や末尾にマークダウンの```があった場合は取り除く
        final cleanJson = result.replaceAll(RegExp(r'^```(json)?\n'), '').replaceAll(RegExp(r'\n```$'), '').trim();
        final jsonMap = jsonDecode(cleanJson);
        final now = DateTime.now();
        final diff = DateTime.monday - now.weekday;
        final nextMonday = now.add(Duration(days: diff <= 0 ? 7 + diff : diff));
        final nextSunday = nextMonday.add(const Duration(days: 6));

        final plan = WeeklyPlan(
          id: '${nextMonday.toIso8601String().split('T').first}_${DateTime.now().millisecondsSinceEpoch}',
          startDate: nextMonday,
          endDate: nextSunday,
          dailyPlans: (jsonMap['dailyPlans'] as List).map((e) => DailyPlan.fromMap(e as Map<String, dynamic>)).toList(),
          aiMessage: jsonMap['aiMessage'] ?? 'AIコーチからの新しい週間計画です。',
          createdAt: DateTime.now(),
        );
        await _firestoreService.saveWeeklyPlan(plan);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('新しい週間計画を生成しました。')));
        }
      } else {
        throw Exception('AIからの応答が空でした');
      }
    } catch (e) {
      if (mounted) {
        final msg = GeminiService().translateError(e, modelId: GeminiService.modelPro);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Widget _buildWeekPlanContent(WeeklyPlan? plan) {
    if (plan == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: Center(child: Text('現在設定されている週間計画はありません。\n右上の更新ボタンから計画をAIに生成させてください。', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.5))),
      );
    }

    // 現在取得できたプランのIDを保持（Undo用）
    // Widgetのビルド中に直接状態を更新するのは避けたいため、Future.microtaskを使う
    if (_currentPlanId != plan.id) {
      Future.microtask(() {
        if (mounted) {
          setState(() {
            _currentPlanId = plan.id;
          });
        }
      });
    }

    // 古い計画を自動で今の週に繰り越す処理の判定
    final now = DateTime.now();
    final endOfPlan = DateTime(plan.endDate.year, plan.endDate.month, plan.endDate.day, 23, 59, 59);
    
    if (now.isAfter(endOfPlan) && !_isGenerating && !_isAutoCopying) {
      // 過去の計画であれば、別のタスクで自動繰越を実行
      Future.microtask(() => _copyPlanToNextWeek(plan));
    }

    final startStr = '${plan.startDate.year}年${plan.startDate.month}月${plan.startDate.day}日';
    final endStr = '${plan.endDate.month}月${plan.endDate.day}日';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$startStr 〜 $endStr',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Chip(
              label: const Text('生成された計画'),
              backgroundColor: Colors.teal.withOpacity(0.3),
              labelStyle: const TextStyle(fontSize: 10),
            ),
          ],
        ),
        if (plan.aiMessage.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.psychology, color: Colors.blueAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(plan.aiMessage, style: const TextStyle(fontSize: 13, height: 1.4))),
              ],
            ),
          ),
        const SizedBox(height: 12),
        ...plan.dailyPlans.map((d) => _buildDayCard(d)),
      ],
    );
  }

  Widget _buildDayCard(DailyPlan plan) {
    // 擬似的に当日の判定を行う。実際の運用時は plan.dateStr のパースか別管理が必要。
    final nowStr = ['月','火','水','木','金','土','日'][DateTime.now().weekday - 1];
    final bool isToday = plan.dateStr.contains(nowStr);
    
    Color intensityColor;
    switch (plan.intensity) {
      case '高': intensityColor = Colors.red; break;
      case '中': intensityColor = Colors.orange; break;
      case '中低': intensityColor = Colors.amber; break;
      case '低': intensityColor = Colors.green; break;
      case 'OFF':
      case 'REST': intensityColor = Colors.grey; break;
      default: intensityColor = Colors.blue;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        key: PageStorageKey('day_${plan.dateStr}'),
        initiallyExpanded: isToday,
        title: Row(children: [
          Expanded(child: Text(plan.dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: intensityColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: intensityColor),
            ),
            child: Text(plan.intensity, style: TextStyle(fontSize: 11, color: intensityColor, fontWeight: FontWeight.bold)),
          ),
        ]),
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.pool, color: Colors.blueAccent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      plan.waterMenu.isNotEmpty ? plan.waterMenu : 'なし',
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.fitness_center, color: Colors.greenAccent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      plan.dryland.isNotEmpty ? plan.dryland : 'なし',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                   const Icon(Icons.restaurant, color: Colors.orangeAccent, size: 16),
                   const SizedBox(width: 6),
                   Expanded(
                     child: Text(
                       '目標: ${plan.targetCalories} kcal (P:${plan.targetProtein}g / F:${plan.targetFat}g / C:${plan.targetCarbs}g)',
                       style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                     ),
                   ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
