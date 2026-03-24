import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/training_record.dart';
import '../../data/models/personal_best.dart';
import '../../data/models/goal_time.dart';
import '../../data/models/weekly_plan.dart';
import '../../data/models/app_user.dart';
import '../../utils/event_utils.dart';
import '../../utils/date_utils.dart';
import '../../utils/app_colors.dart';
import '../../utils/file_saver.dart'; // Add this
import '../../data/providers/providers.dart';
import '../widgets/premium_card.dart';
import '../widgets/training_form.dart';
import '../widgets/nutrition_form.dart';
import '../widgets/body_composition_form.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final int _bodyCompOffset = 1; // デフォルトで今月を右から2番目にするためのオフセット
  bool _showMonthlyBadges = true; // バッジ表示切替フラグ
  bool _isRaceRecordsExpanded = false; // レース記録の開閉状態

  bool _isShowingSleepDialog = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // クエリパラメータによるダイアログ自動表示のチェック
    final uri = GoRouterState.of(context).uri;
    final action = uri.queryParameters['action'];
    if (action == 'add_sleep') {
      if (!_isShowingSleepDialog) {
        _isShowingSleepDialog = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showAddSleepDialog(context);
          }
        });
      }
    } else {
      // パラメータがない場合はフラグをリセットして次回の呼び出しに備える
      _isShowingSleepDialog = false;
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // 必要なフィールドのみを select で監視し、再描画範囲を限定
    final planAsync = ref.watch(latestWeeklyPlanProvider);
    // user の名前やコーチ設定など、頻繁に変わらないものは個別に watch または select
    final userAsync = ref.watch(userProfileProvider);
    // recordsAsync は全体の変更を検知するが、リスト表示以外では select を推奨
    final recordsAsync = ref.watch(trainingRecordsProvider);
    final goalTimesAsync = ref.watch(goalTimesProvider);

    // 読み込み中またはエラー時の表示
    if (recordsAsync.isLoading || userAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final plan = planAsync.value;
    final user = userAsync.value;
    final allGts = goalTimesAsync.value ?? [];

    // 計算済み Provider を使用 (既にフィルタリング・メモ化されている)
    final todayRecords = ref.watch(todayRecordsProvider);
    final poolRecord = todayRecords.where((r) => r.type == 'pool').firstOrNull;
    final drylandRecord = todayRecords.where((r) => r.type == 'dryland').firstOrNull;

    final categorizedPbs = ref.watch(categorizedPbsProvider);
    final latestSwimPbs = categorizedPbs['swim']!;
    final latestDrylandPbs = categorizedPbs['dryland']!;

    final pbHistory = ref.watch(pbHistoryProvider);
    final swimPbHistory = pbHistory['swim']!;
    final drylandPbHistory = pbHistory['dryland']!;

    // 体組成データも計算済み Provider から取得
    final bodyCompRecords = ref.watch(bodyCompositionRecordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AquaAnalyst AI',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: AppColors.skyBlue,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'バッジコレクション', 
                                  style: TextStyle(
                                    fontSize: 18, 
                                    fontWeight: FontWeight.bold, 
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(value: true, label: Text('今月', style: TextStyle(fontSize: 11))),
                                    ButtonSegment(value: false, label: Text('累計', style: TextStyle(fontSize: 11))),
                                  ],
                                  selected: {_showMonthlyBadges},
                                  onSelectionChanged: (val) => setState(() => _showMonthlyBadges = val.first),
                                  showSelectedIcon: false,
                                  style: SegmentedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _BadgeCountSection(
                              showMonthly: _showMonthlyBadges,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // 今日のサマリー
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000), // サマリーも巨大化を防ぐ
                        child: _TodaySummaryCard(
                          poolRecords: todayRecords.where((r) => r.type == 'pool').toList(),
                          drylandRecords: todayRecords.where((r) => r.type == 'dryland').toList(),
                          nutritionRecords: todayRecords.where((r) => 
                            r.type == 'nutrition' && 
                            r.subjectiveMetrics['is_body_composition'] != true
                          ).toList(),
                          sleepRecords: todayRecords.where((r) => r.type == 'sleep').toList(),
                          user: user,
                          latestPlan: plan,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // アクティビティ履歴とレース記録（PCでは横並び）
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final calendar = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('アクティビティ履歴', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 600),
                                child: const _ActivityCalendar(),
                              ),
                            ),
                          ],
                        );
                        final races = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('レース記録', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                TextButton.icon(
                                  onPressed: () => setState(() => _isRaceRecordsExpanded = !_isRaceRecordsExpanded),
                                  icon: Icon(_isRaceRecordsExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
                                  label: Text(_isRaceRecordsExpanded ? 'たたむ' : 'すべて表示', style: const TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildRaceRecordsSection(ref),
                          ],
                        );

                        if (constraints.maxWidth > 900) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: calendar),
                              const SizedBox(width: 32),
                              Expanded(flex: 2, child: races),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              calendar,
                              const SizedBox(height: 32),
                              races,
                            ],
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 32),

            // 現在の自己ベスト
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('現在の自己ベスト', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle, color: Colors.blueAccent), onPressed: () => _showAddPbDialog(context, 'swim')),
              ],
            ),
            const SizedBox(height: 16),
            if (latestSwimPbs.isEmpty) const Text('自己ベストがまだ登録されていません。', style: TextStyle(color: Colors.grey)),
            ...latestSwimPbs.values.toList().reversed.map((pb) => 
               _buildBestTimeCard(context, pb, swimPbHistory[pb.event]!)
            ),
            const SizedBox(height: 24),
 
            // ウエイトトレーニングの自己ベスト
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ウエイトトレーニング自己ベスト', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle, color: Colors.amber), onPressed: () => _showAddPbDialog(context, 'dryland')),
              ],
            ),
            const SizedBox(height: 16),
            if (latestDrylandPbs.isEmpty) const Text('自己ベストがまだ登録されていません。', style: TextStyle(color: Colors.grey)),
            ...latestDrylandPbs.values.toList().reversed.map((pb) => 
               _buildWeightBestCard(context, pb, drylandPbHistory[pb.event]!)
            ),
            const SizedBox(height: 24),

            // 目標タイム
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('目標タイム', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.flag, color: Colors.blueAccent), onPressed: () => _showAddGoalDialog(context)),
              ],
            ),
            const SizedBox(height: 16),
            if (allGts.isEmpty) const Text('目標タイムがまだ設定されていません。', style: TextStyle(color: Colors.grey)),
            ...allGts.map((gt) => _buildGoalTimeCard(context, gt)),
            const SizedBox(height: 24),
            
            // 重要：動的なリスト表示部分を RepaintBoundary で分離
            RepaintBoundary(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 現在の体組成（自己ベスト下）
                  const Text('現在の体組成', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildLatestBodyCompCard(bodyCompRecords),
                ],
              ),
            ),
            
          ],
        ),
      ),
    );
  }

  Widget _buildLatestBodyCompCard(List<TrainingRecord> bodyCompRecords) {
    if (bodyCompRecords.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('体組成の記録がまだありません。「+」ボタンから記録できます。', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    // 最新の記録
    final latest = bodyCompRecords.first;
    final weight = latest.subjectiveMetrics['weight']?.toDouble() ?? 0.0;
    final muscle = latest.subjectiveMetrics['muscle_mass']?.toDouble() ?? 0.0;
    final fat = latest.subjectiveMetrics['body_fat']?.toDouble() ?? 0.0;
    final dateStr = "${latest.date.year}/${latest.date.month.toString().padLeft(2, '0')}/${latest.date.day.toString().padLeft(2, '0')}";

    // 比較用（1つ前の記録があれば）
    double weightDiff = 0;
    double muscleDiff = 0;
    if (bodyCompRecords.length > 1) {
      final prev = bodyCompRecords[1];
      final prevWeight = prev.subjectiveMetrics['weight']?.toDouble() ?? 0.0;
      final prevMuscle = prev.subjectiveMetrics['muscle_mass']?.toDouble() ?? 0.0;
      if (prevWeight > 0) weightDiff = weight - prevWeight;
      if (prevMuscle > 0) muscleDiff = muscle - prevMuscle;
    }

    return PremiumCard(
      onTap: () => _showBodyCompositionHistory(context, bodyCompRecords),
      icon: Icons.monitor_weight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bodyComp.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.monitor_weight, color: AppColors.bodyComp, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('最新の測定データ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                        Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _DetailRow(label: '体重', value: weight > 0 ? '$weight kg' : '未入力'),
                    _DetailRow(label: '筋量', value: muscle > 0 ? '$muscle kg' : '未入力'),
                    _DetailRow(label: '脂肪率', value: fat > 0 ? '$fat %' : '未入力'),
                  ],
                ),
              ),
            ],
          ),
          if (weightDiff != 0 || muscleDiff != 0) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 4),
            Text('前回比', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 4),
            Row(children: [
              if (weightDiff != 0) ...[
                Icon(weightDiff < 0 ? Icons.arrow_downward : Icons.arrow_upward, 
                     color: weightDiff < 0 ? Colors.greenAccent : Colors.orangeAccent, size: 14),
                const SizedBox(width: 4),
                Text('体重 ${weightDiff > 0 ? '+' : ''}${weightDiff.toStringAsFixed(1)} kg', 
                     style: TextStyle(fontSize: 13, color: weightDiff < 0 ? Colors.greenAccent : Colors.orangeAccent)),
                const SizedBox(width: 16),
              ],
              if (muscleDiff != 0) ...[
                Icon(muscleDiff > 0 ? Icons.arrow_upward : Icons.arrow_downward, 
                     color: muscleDiff > 0 ? Colors.blueAccent : Colors.redAccent, size: 14),
                const SizedBox(width: 4),
                Text('骨格筋量 ${muscleDiff > 0 ? '+' : ''}${muscleDiff.toStringAsFixed(1)} kg', 
                     style: TextStyle(fontSize: 13, color: muscleDiff > 0 ? Colors.blueAccent : Colors.redAccent)),
              ],
            ]),
          ],
        ],
      ),
    );
  }

  void _showAddSleepDialog(BuildContext context) {
    final now = DateTime.now();
    DateTime wakeDate = now;
    final sleepHourController = TextEditingController(text: '23');
    final sleepMinController = TextEditingController(text: '00');
    final wakeHourController = TextEditingController(text: '07');
    final wakeMinController = TextEditingController(text: '00');
    bool sleptYesterday = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.bedtime, color: AppColors.sleep),
              SizedBox(width: 8),
              Text('睡眠記録'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('就寝・起床の時刻を数値で入力してください', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                const Text('就寝時刻', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(child: TextField(controller: sleepHourController, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: '時'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: sleepMinController, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: '分'))),
                  ],
                ),
                CheckboxListTile(
                  title: const Text('前日の夜に寝た', style: TextStyle(fontSize: 12)),
                  value: sleptYesterday,
                  onChanged: (val) => setDialogState(() => sleptYesterday = val ?? true),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 12),
                const Text('起床時刻', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(child: TextField(controller: wakeHourController, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: '時'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: wakeMinController, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: '分'))),
                  ],
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('起床日', style: TextStyle(fontSize: 13)),
                  subtitle: Text('${wakeDate.month}/${wakeDate.day}'),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: wakeDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setDialogState(() => wakeDate = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                context.go('/home');
                Navigator.pop(ctx);
              },
              child: const Text('キャンセル'),
            ),
            (() {
              bool isSaving = false;
              return StatefulBuilder(
                builder: (ctx, setBtnState) {
                  return ElevatedButton(
                    onPressed: isSaving ? null : () async {
                      final sH = int.tryParse(sleepHourController.text) ?? 23;
                      final sM = int.tryParse(sleepMinController.text) ?? 0;
                      final wH = int.tryParse(wakeHourController.text) ?? 7;
                      final wM = int.tryParse(wakeMinController.text) ?? 0;

                      final sleepDate = sleptYesterday ? wakeDate.subtract(const Duration(days: 1)) : wakeDate;
                      final sleepStart = DateTime(sleepDate.year, sleepDate.month, sleepDate.day, sH, sM);
                      final sleepEnd = DateTime(wakeDate.year, wakeDate.month, wakeDate.day, wH, wM);
                      
                      if (sleepEnd.isBefore(sleepStart)) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('起床時刻が入眠時刻より前になっています')));
                        return;
                      }

                      final duration = sleepEnd.difference(sleepStart).inMinutes;
                      
                      // 同期不備を防ぐため、date には起床日の 12:00:00 を設定して「実効的な当日」に確実に入れる
                      final recordDate = DateTime(wakeDate.year, wakeDate.month, wakeDate.day, 12, 0, 0);

                      final record = TrainingRecord(
                        id: '',
                        type: 'sleep',
                        date: recordDate,
                        durationMinutes: duration,
                        subjectiveMetrics: {
                          'sleep_start': sleepStart.toIso8601String(),
                          'sleep_end': sleepEnd.toIso8601String(),
                        },
                        details: [],
                      );
                      
                      setBtnState(() => isSaving = true);
                      try {
                        await _firestoreService.addTrainingRecord(record);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          context.go('/home'); 
                        }
                      } catch (e) {
                          if (ctx.mounted) {
                            GeminiService.showErrorDialog(ctx, e, title: '保存エラー');
                          }
                      } finally {
                        if (ctx.mounted) setBtnState(() => isSaving = false);
                      }
                    },
                    child: isSaving 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('保存'),
                  );
                }
              );
            })(),
          ],
        ),
      ),
    );
  }

  void _showAddPbDialog(BuildContext context, String category) {
    final eventController = TextEditingController();
    final valueController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(category == 'swim' ? '水泳のPBを追加' : '陸トレのPBを追加'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: eventController, decoration: InputDecoration(labelText: category == 'swim' ? '種目 (例: 50m Fr)' : '種目 (例: ベンチプレス)')),
              TextField(controller: valueController, decoration: InputDecoration(labelText: category == 'swim' ? 'タイム (秒)' : '重量 (kg)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              ListTile(
                title: const Text('記録日', style: TextStyle(fontSize: 14)),
                subtitle: Text('${selectedDate.year}/${selectedDate.month}/${selectedDate.day}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            (() {
              bool isSaving = false;
              return StatefulBuilder(
                builder: (ctx, setBtnState) {
                  return ElevatedButton(
                    onPressed: isSaving ? null : () async {
                      final val = double.tryParse(valueController.text);
                      if (eventController.text.isNotEmpty && val != null) {
                        final pb = PersonalBest(
                          id: '',
                          category: category,
                          event: category == 'swim' 
                              ? EventUtils.normalizeEventName(eventController.text) 
                              : eventController.text,
                          value: val,
                          date: selectedDate,
                        );
                        setBtnState(() => isSaving = true);
                        try {
                          await _firestoreService.savePersonalBest(pb);
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) {
                            GeminiService.showErrorDialog(ctx, e, title: '保存エラー');
                          }
                        } finally {
                          if (ctx.mounted) setBtnState(() => isSaving = false);
                        }
                      }
                    },
                    child: isSaving 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('保存'),
                  );
                }
              );
            })(),
          ],
        ),
      ),
    );
  }

  void _showPbHistoryDialog(BuildContext context, String event, List<PersonalBest> history, {required bool isTime}) {
    // 日付順にソート（グラフ用）
    final sortedHistory = List<PersonalBest>.from(history)..sort((a, b) => a.date.compareTo(b.date));
    if (sortedHistory.isEmpty) return;

    // 自己ベスト（一番速い/重い）を特定
    final bestPb = isTime 
        ? history.reduce((a, b) => a.value < b.value ? a : b)
        : history.reduce((a, b) => a.value > b.value ? a : b);

    showDialog(
      context: context,
      builder: (ctx) {
        int selectedIndex = bestPb.trainingRecordId != null ? 0 : 1; // ラップがあればラップ、なければグラフ
        TrainingRecord? bestRecord;
        bool isLoadingRecord = bestPb.trainingRecordId != null;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 初回のみ記録を取得
            if (isLoadingRecord && bestRecord == null) {
              _firestoreService.getTrainingRecord(bestPb.trainingRecordId!).then((record) {
                if (ctx.mounted) {
                  setDialogState(() {
                    bestRecord = record;
                    isLoadingRecord = false;
                  });
                }
              });
            }

            return AlertDialog(
              title: Row(
                children: [
                  Expanded(child: Text(event, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  if (isTime && bestPb.trainingRecordId != null)
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('ラップ', style: TextStyle(fontSize: 10))),
                        ButtonSegment(value: 1, label: Text('推移', style: TextStyle(fontSize: 10))),
                      ],
                      selected: {selectedIndex},
                      onSelectionChanged: (s) => setDialogState(() => selectedIndex = s.first),
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: selectedIndex == 0 && isTime
                  ? _buildPbDetailView(bestPb, bestRecord, isLoadingRecord)
                  : _buildPbTrendView(event, sortedHistory, isTime),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる')),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPbDetailView(PersonalBest pb, TrainingRecord? record, bool isLoading) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (record == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            const Text('詳細データがありません', style: TextStyle(color: Colors.grey)),
            Text('達成日: ${pb.date.year}/${pb.date.month}/${pb.date.day}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    final lapsData = record.details.firstWhere((d) => d['type'] == 'laps', orElse: () => {})['data'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BEST TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.light ? Colors.teal.shade900 : AppColors.skyBlue)),
                  Text(_formatSeconds(pb.value), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.light ? Colors.teal.shade900 : AppColors.skyBlue)),
                ],
              ),
              Text('${pb.date.year}/${pb.date.month}/${pb.date.day}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('ラップタイム詳細', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const Divider(),
        Expanded(
          child: lapsData.isEmpty 
            ? const Center(child: Text('ラップデータがありません', style: TextStyle(fontSize: 12, color: Colors.grey)))
            : ListView.separated(
                itemCount: lapsData.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final lap = lapsData[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        SizedBox(width: 60, child: Text(lap['section'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey))),
                        Expanded(child: Text(lap['cumulative'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.light ? Colors.black87 : Colors.white))),
                        Text('(${lap['time'] ?? ''})', style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.light ? Colors.teal.shade800 : AppColors.skyBlue)),
                      ],
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildPbTrendView(String event, List<PersonalBest> sortedHistory, bool isTime) {
    final List<FlSpot> spots = sortedHistory.map((pb) {
      final yValue = (isTime && pb.category == 'swim') ? -pb.value : pb.value;
      return FlSpot(pb.date.millisecondsSinceEpoch.toDouble(), yValue);
    }).toList();

    final yValues = spots.map((s) => s.y).toList();
    final xValues = spots.map((s) => s.x).toList();
    
    final buffer = 86400000.0 * 30; // 30日分のパディング
    final minX = xValues.length == 1 ? xValues.first - buffer : xValues.reduce((a, b) => a < b ? a : b) - buffer;
    final maxX = xValues.length == 1 ? xValues.first + buffer : xValues.reduce((a, b) => a > b ? a : b) + buffer;
    
    final minY = yValues.reduce((a, b) => a < b ? a : b) - 1.0;
    final maxY = yValues.reduce((a, b) => a > b ? a : b) + 1.0;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY - (maxY - minY).abs() * 0.1,
        maxY: maxY + (maxY - minY).abs() * 0.1,
        clipData: const FlClipData.all(),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: isTime ? const Color(0xFF00B0FF) : AppColors.dryland,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 3,
                color: isTime ? const Color(0xFF00B0FF) : AppColors.dryland,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(_formatSeconds(value.abs()), style: const TextStyle(fontSize: 10));
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (maxX - minX) / 4 > 86400000 ? (maxX - minX) / 4 : 86400000,
              getTitlesWidget: (value, meta) {
                // ラベルの間隔を調整して重なりを防ぐ
                if (value % meta.appliedInterval != 0 && value != meta.max && value != meta.min) {
                   return const SizedBox.shrink();
                }
                
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    AppDateUtils.getMonthlyChartLabel(value, previousValue: meta.min == value ? null : value - meta.appliedInterval),
                    style: const TextStyle(fontSize: 8, color: Colors.grey),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.blueGrey,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((s) {
                return LineTooltipItem(
                  '${_formatSeconds(s.y.abs())}${isTime ? '' : ' kg'}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  void _showBodyCompositionHistory(BuildContext context, List<TrainingRecord> logs) {
    // 体組成データを抽出・ソート
    final bodyLogs = logs.where((l) => 
      l.type == 'body_composition' || 
      (l.type == 'nutrition' && l.subjectiveMetrics['is_body_composition'] == true)
    ).toList()..sort((a, b) => a.date.compareTo(b.date));

    if (bodyLogs.isEmpty) return;

    final List<FlSpot> weightSpots = [];
    final List<FlSpot> muscleSpots = [];
    final List<FlSpot> fatSpots = [];

    for (final log in bodyLogs) {
      final double x = log.date.millisecondsSinceEpoch.toDouble();
      final metrics = log.subjectiveMetrics;
      if (metrics.containsKey('weight')) {
        weightSpots.add(FlSpot(x, (metrics['weight'] as num).toDouble()));
      }
      if (metrics.containsKey('muscle_mass')) {
        muscleSpots.add(FlSpot(x, (metrics['muscle_mass'] as num).toDouble()));
      }
      if (metrics.containsKey('body_fat')) {
        fatSpots.add(FlSpot(x, (metrics['body_fat'] as num).toDouble()));
      }
    }

    final xValues = (weightSpots + muscleSpots + fatSpots).map((s) => s.x).toList();
    if (xValues.isEmpty) return;
    
    final minX = xValues.length == 1 ? xValues.first - 86400000 : xValues.reduce((a, b) => a < b ? a : b) - 43200000;
    final maxX = xValues.length == 1 ? xValues.first + 86400000 : xValues.reduce((a, b) => a > b ? a : b) + 43200000;

    // kg系（体重・筋量）のレンジ
    final kgValues = (weightSpots + muscleSpots).map((s) => s.y).toList();
    final double minKg = kgValues.isEmpty ? 0 : kgValues.reduce((a, b) => a < b ? a : b) - 2;
    final double maxKg = kgValues.isEmpty ? 100 : kgValues.reduce((a, b) => a > b ? a : b) + 2;

    // %系（体脂肪率）のレンジ
    final fatValues = fatSpots.map((s) => s.y).toList();
    final double minFat = fatValues.isEmpty ? 0 : fatValues.reduce((a, b) => a < b ? a : b) - 1;
    final double maxFat = fatValues.isEmpty ? 30 : fatValues.reduce((a, b) => a > b ? a : b) + 1;

    // 体脂肪率をkgレンジに正規化してプロット用スポットを作成
    final normalizedFatSpots = fatSpots.map((s) {
      double normalizedY;
      if (maxFat == minFat) {
        normalizedY = (maxKg + minKg) / 2;
      } else {
        normalizedY = (s.y - minFat) / (maxFat - minFat) * (maxKg - minKg) + minKg;
      }
      return FlSpot(s.x, normalizedY);
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('体組成推移', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          height: 350,
          child: Column(
            children: [
              Expanded(
                child: LineChart(
                  LineChartData(
                    minX: minX,
                    maxX: maxX,
                    minY: minKg,
                    maxY: maxKg,
                    clipData: const FlClipData.all(),
                    lineBarsData: [
                      if (weightSpots.isNotEmpty)
                        LineChartBarData(
                          spots: weightSpots,
                          color: Colors.blue,
                          barWidth: 3,
                          isCurved: false,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                              radius: 3,
                              color: Colors.blue,
                              strokeWidth: 1.5,
                              strokeColor: Colors.white,
                            ),
                          ),
                        ),
                      if (muscleSpots.isNotEmpty)
                        LineChartBarData(
                          spots: muscleSpots,
                          color: Colors.green,
                          barWidth: 3,
                          isCurved: false,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                              radius: 3,
                              color: Colors.green,
                              strokeWidth: 1.5,
                              strokeColor: Colors.white,
                            ),
                          ),
                        ),
                      if (normalizedFatSpots.isNotEmpty)
                        LineChartBarData(
                          spots: normalizedFatSpots,
                          color: Colors.orange,
                          barWidth: 3,
                          isCurved: false,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                              radius: 3,
                              color: Colors.orange,
                              strokeWidth: 1.5,
                              strokeColor: Colors.white,
                            ),
                          ),
                        ),
                    ],
                    titlesData: FlTitlesData(
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (v, m) {
                            if (maxKg == minKg) return const SizedBox.shrink();
                            final fatVal = (v - minKg) / (maxKg - minKg) * (maxFat - minFat) + minFat;
                            return Text(fatVal.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: Colors.orange));
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (v, m) => Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: Colors.blue)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: (maxX - minX) / 4 > 86400000 ? (maxX - minX) / 4 : 86400000,
                          getTitlesWidget: (v, m) {
                            if (v % m.appliedInterval != 0 && v != m.max && v != m.min) {
                               return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                AppDateUtils.getMonthlyChartLabel(v, previousValue: m.min == v ? null : v - m.appliedInterval),
                                style: const TextStyle(fontSize: 8, color: Colors.grey),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => Colors.blueGrey,
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((s) {
                            String unit = ' kg';
                            double displayValue = s.y;
                            if (s.bar.color == Colors.orange) {
                              unit = ' %';
                              // 正規化を解除して元の体脂肪率に戻す
                              if (maxKg != minKg) {
                                displayValue = (s.y - minKg) / (maxKg - minKg) * (maxFat - minFat) + minFat;
                              } else {
                                displayValue = minFat;
                              }
                            }
                            return LineTooltipItem(
                              '${displayValue.toStringAsFixed(1)}$unit',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildLegend(Colors.blue, '体重(kg)'),
                  _buildLegend(Colors.green, '骨格筋量(kg)'),
                  _buildLegend(Colors.orange, '体脂肪率(%)'),
                ],
              )
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  void _showPbOptionsDialog(BuildContext context, PersonalBest pb) {
    final eventController = TextEditingController(text: pb.event);
    final valueController = TextEditingController(text: pb.value.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${pb.event}」の自己ベスト'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: eventController, decoration: const InputDecoration(labelText: '種目名')),
            TextField(controller: valueController, decoration: InputDecoration(labelText: pb.category == 'swim' ? 'タイム (秒)' : '重量 (kg)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  title: const Text('削除の確認'),
                  content: const Text('この自己ベストを削除してもよろしいですか？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                await FirestoreService().deletePersonalBest(pb.id);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自己ベストを削除しました')));
                }
              }
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () async {
              final newVal = double.tryParse(valueController.text);
              if (eventController.text.isNotEmpty && newVal != null) {
                final updatedPb = PersonalBest(
                  id: pb.id,
                  category: pb.category,
                  event: EventUtils.normalizeEventName(eventController.text),
                  value: newVal,
                  date: pb.date,
                );
                await FirestoreService().savePersonalBest(updatedPb);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自己ベストを更新しました')));
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }



  void _showAddGoalDialog(BuildContext context) {
    final eventController = TextEditingController();
    final valueController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('目標タイムを追加'),
        content: SizedBox(
          width: 300, // 幅を固定
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: eventController, decoration: const InputDecoration(labelText: '種目 (例: 100m Fr)')),
              TextField(controller: valueController, decoration: const InputDecoration(labelText: '目標タイム (秒)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(valueController.text);
              if (eventController.text.isNotEmpty && val != null) {
                final gt = GoalTime(
                  id: '',
                  category: 'swim',
                  event: EventUtils.normalizeEventName(eventController.text),
                  value: val,
                  date: DateTime.now(),
                );
                await _firestoreService.saveGoalTime(gt);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showGoalOptionsDialog(BuildContext context, GoalTime gt) {
    final eventController = TextEditingController(text: gt.event);
    final valueController = TextEditingController(text: gt.value.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${gt.event}」の目標'),
        content: SizedBox(
          width: 300, // 幅を固定
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: eventController, decoration: const InputDecoration(labelText: '種目名')),
              TextField(controller: valueController, decoration: const InputDecoration(labelText: '目標タイム (秒)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  title: const Text('削除の確認'),
                  content: const Text('この目標タイムを削除してもよろしいですか？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                await _firestoreService.deleteGoalTime(gt.id);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () async {
              final newVal = double.tryParse(valueController.text);
              if (eventController.text.isNotEmpty && newVal != null) {
                final updatedGt = GoalTime(
                  id: gt.id,
                  category: gt.category,
                  event: EventUtils.normalizeEventName(eventController.text),
                  value: newVal,
                  date: gt.date,
                );
                await _firestoreService.saveGoalTime(updatedGt);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }


  List<LineChartBarData> _buildBodyCompLineBars(List<TrainingRecord> allRecords) {
    final now = DateTime.now();
    final baseMonth = DateTime(now.year, now.month - _bodyCompOffset + 1, 1);
    final last12Months = <DateTime>[];
    for (int i = 11; i >= 0; i--) {
      last12Months.add(DateTime(baseMonth.year, baseMonth.month - i, 1));
    }

    final weightSpots = <FlSpot>[];
    final muscleSpots = <FlSpot>[];
    
    // 期間開始前の最新データを探す（引き継ぎ用）
    double? lastWeight;
    double? lastMuscle;
    final preRecords = allRecords.where((r) => 
      (r.type == 'body_composition' || (r.type == 'nutrition' && r.subjectiveMetrics['is_body_composition'] == true)) &&
      r.date.isBefore(last12Months.first)
    ).toList();
    if (preRecords.isNotEmpty) {
      lastWeight = preRecords.first.subjectiveMetrics['weight']?.toDouble();
      lastMuscle = preRecords.first.subjectiveMetrics['muscle_mass']?.toDouble();
    }

    for (int i = 0; i < 12; i++) {
      final monthStart = last12Months[i];
      final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0, 23, 59, 59);
      final monthRecords = allRecords.where((r) => 
        (r.type == 'body_composition' || (r.type == 'nutrition' && r.subjectiveMetrics['is_body_composition'] == true)) &&
        r.date.isAfter(monthStart.subtract(const Duration(seconds: 1))) &&
        r.date.isBefore(monthEnd.add(const Duration(seconds: 1)))
      ).toList();

      if (monthRecords.isNotEmpty) {
        final latest = monthRecords.first;
        final w = latest.subjectiveMetrics['weight']?.toDouble();
        final m = latest.subjectiveMetrics['muscle_mass']?.toDouble();
        if (w != null && w > 0) lastWeight = w;
        if (m != null && m > 0) lastMuscle = m;
      }
      if (lastWeight != null && lastWeight > 0) weightSpots.add(FlSpot((i + 1).toDouble(), lastWeight));
      if (lastMuscle != null && lastMuscle > 0) muscleSpots.add(FlSpot((i + 1).toDouble(), lastMuscle));
    }

    return [
      LineChartBarData(
        spots: weightSpots,
        isCurved: false,
        color: AppColors.skyBlue,
        barWidth: 3,
        dotData: const FlDotData(show: true),
      ),
      LineChartBarData(
        spots: muscleSpots,
        isCurved: false,
        color: Colors.orange,
        barWidth: 3,
        dotData: const FlDotData(show: true),
      ),
    ];
  }

  Widget _buildBestTimeCard(BuildContext context, PersonalBest pb, List<PersonalBest> history) {
    return PremiumCard(
      onTap: () => _showPbHistoryDialog(context, pb.event, history, isTime: true),
      icon: Icons.timer_outlined,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.pool.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.timer_outlined, color: AppColors.pool, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pb.event, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  'Best: ${pb.date.year}/${pb.date.month}/${pb.date.day}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          Text(
            _formatSeconds(pb.value),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.pool),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightBestCard(BuildContext context, PersonalBest pb, List<PersonalBest> history) {
    return PremiumCard(
      onTap: () => _showPbHistoryDialog(context, pb.event, history, isTime: false),
      icon: Icons.fitness_center_outlined,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.dryland.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.fitness_center_outlined, color: AppColors.dryland, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pb.event, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  'Best: ${pb.date.year}/${pb.date.month}/${pb.date.day}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          Text(
            '${pb.value.toStringAsFixed(1)} kg',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.dryland),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalTimeCard(BuildContext context, GoalTime gt) {
    return PremiumCard(
      onTap: () => _showGoalOptionsDialog(context, gt),
      icon: Icons.flag_outlined,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.flag_outlined, color: Colors.blueAccent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gt.event, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text('目標タイム', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
              ],
            ),
          ),
          Text(
            gt.value.toStringAsFixed(2),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.blueAccent),
          ),
        ],
      ),
    );
  }

  String _formatSeconds(double seconds) {
    if (seconds <= 0) return '0.00';
    final int min = (seconds / 60).floor();
    final double sec = seconds % 60;
    if (min == 0) return sec.toStringAsFixed(2);
    return '$min:${sec.toStringAsFixed(2).padLeft(5, '0')}';
  }

  Widget _buildRaceRecordsSection(WidgetRef ref) {
    final raceRecordsAsync = ref.watch(raceRecordsProvider);

    return raceRecordsAsync.when(
      data: (records) {
        if (records.isEmpty) {
          return const Text('レース記録がまだありません。', style: TextStyle(color: Colors.grey));
        }
        
        // 折りたたみ時は最新の3件のみ表示
        final displayRecords = _isRaceRecordsExpanded ? records : records.take(3).toList();
        
        return Column(
          children: [
            ...displayRecords.map((record) => _buildRaceRecordCard(context, record)),
            if (!_isRaceRecordsExpanded && records.length > 3)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text('ほか ${records.length - 3} 件の記録があります', 
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Text('エラーが発生しました: $e'),
    );
  }

  Widget _buildRaceRecordCard(BuildContext context, Map<String, dynamic> record) {
    final date = (record['date'] as Timestamp).toDate();
    final event = record['event'] as String? ?? '不明';
    final totalTime = record['totalTime']?.toString() ?? '-';
    final distance = record['distance']?.toString() ?? '-';
return PremiumCard(
      onTap: () => _showRaceRecordDetailsDialog(context, record),
      icon: Icons.history_edu_outlined,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.skyBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_edu_outlined, color: AppColors.skyBlue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  '${date.year}/${date.month}/${date.day} • $distance',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          Text(
            totalTime,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.skyBlue),
          ),
        ],
      ),
    );
  }

  void _showRaceRecordDetailsDialog(BuildContext context, Map<String, dynamic> record) {
    final date = (record['date'] as Timestamp).toDate();
    final event = record['event'] as String? ?? '不明';
    final totalTime = record['totalTime']?.toString() ?? '-';
    final distance = record['distance']?.toString() ?? '-';
    final course = record['course']?.toString() ?? '-';
    final laps = record['laps'] as List<dynamic>? ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$event 詳細'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('日時: ${date.year}/${date.month}/${date.day}', style: const TextStyle(fontSize: 14)),
              Text('距離/コース: $distance / $course', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.skyBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Text('TOTAL TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                    Text(totalTime, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.skyBlue)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('ラップ・反省', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Divider(),
              if (laps.isEmpty)
                const Text('ラップデータがありません', style: TextStyle(color: Colors.grey))
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: laps.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final lap = laps[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SizedBox(width: 50, child: Text(lap['section'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey))),
                                Text(lap['cumulative'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Text('(${lap['time'] ?? ''})', style: const TextStyle(fontSize: 12, color: AppColors.skyBlue)),
                              ],
                            ),
                            if (lap['memo'] != null && lap['memo'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0, left: 50),
                                child: Text(lap['memo'], style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  title: const Text('削除の確認'),
                  content: const Text('このレース記録を削除してもよろしいですか？\n※PB推移データは削除されません。'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                await _firestoreService.deleteRaceRecord(record['id']);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('レース記録を削除しました')));
                }
              }
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる')),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionLabel({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
    ]);
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  const _DetailRow({required this.label, this.value, this.child});
  @override
  Widget build(BuildContext context) {
    final labelColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final hasLabel = label.isNotEmpty;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasLabel) ...[
            SizedBox(width: 130, child: Text(label, style: TextStyle(color: labelColor, fontSize: 13))),
          ],
          Expanded(child: child ?? Text(value ?? '', style: const TextStyle(fontSize: 13))),
        ]
      ),
    );
  }
}

class _PfcStatusRow extends StatelessWidget {
  final String label;
  final double value;
  final double maxValue;
  final Color color;
  final String status;
  final bool isPoster;

  const _PfcStatusRow({
    required this.label, 
    required this.value, 
    required this.maxValue, 
    required this.color, 
    required this.status,
    this.isPoster = false,
  });

  @override
  Widget build(BuildContext context) {
    final double percent = maxValue > 0 ? (value / maxValue).clamp(0.0, 1.0) : 0.0;
    
    if (isPoster) {
      final pLabel = (label.contains('タンパク質') || label.contains('Protein')) ? 'タンパク質' : 
                     (label.contains('脂質') || label.contains('Fat')) ? '脂質' : 
                     (label.contains('炭水化物') || label.contains('Carbs')) ? '炭水化物' : 'エネルギー';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            SizedBox(
              width: 100, // ラベル幅を短縮
              child: Text(pLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent,
                  backgroundColor: color.withValues(alpha: 0.1),
                  color: color,
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: Text(
                '${value.toInt()}/${maxValue.toInt()}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: -0.5),
              ),
            ),
          ],
        ),
      );
    }

    final labelColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final bgColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(children: [
        SizedBox(width: 130, child: Text(label, style: TextStyle(color: labelColor, fontSize: 13))),
        Expanded(
          child: LinearProgressIndicator(
            value: value / maxValue,
            backgroundColor: bgColor,
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text(
            '${value.toInt()} / ${maxValue.toInt()}',
            style: TextStyle(color: labelColor, fontSize: 11, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(
            status, 
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ]),
    );
  }
}

class _BadgeCountSection extends ConsumerWidget {
  final bool showMonthly;
  const _BadgeCountSection({super.key, required this.showMonthly});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsByEffectiveDay = ref.watch(recordsByEffectiveDayProvider);
    final weeklyPlans = ref.watch(weeklyPlansProvider).value ?? [];
    // recordsByEffectiveDay はプロバイダーから取得済み

    int poolTotal = 0, poolMonth = 0;
    int drylandTotal = 0, drylandMonth = 0;
    int pTotal = 0, pMonth = 0;
    int fTotal = 0, fMonth = 0;
    int cTotal = 0, cMonth = 0;
    final logicalNow = AppDateUtils.logicalToday();

    for (var key in recordsByEffectiveDay.keys) {
      final dayRecords = recordsByEffectiveDay[key]!;
      final parts = key.split('-');
      final y = int.parse(parts[0]), m = int.parse(parts[1]), d = int.parse(parts[2]);
      final isThisMonth = (y == logicalNow.year && m == logicalNow.month);
      
      // カテゴリ別達成判定
      bool hasPool = dayRecords.any((r) => r.type == 'pool');
      bool hasDryland = dayRecords.any((r) => r.type == 'dryland');
      
      // 栄養素合計
      double dP = 0, dF = 0, dC = 0;
      for (var r in dayRecords.where((r) => r.type == 'nutrition' && r.subjectiveMetrics['is_body_composition'] != true)) {
        dP += r.subjectiveMetrics['protein']?.toDouble() ?? 0.0;
        dF += r.subjectiveMetrics['fat']?.toDouble() ?? 0.0;
        dC += r.subjectiveMetrics['carbs']?.toDouble() ?? 0.0;
      }

      // その日の目標値を取得（過去の計画を優先）
      final dt = DateTime(y, m, d);
      final weekdayStr = ['月','火','水','木','金','土','日'][dt.weekday - 1];
      int targetP = 150, targetF = 70, targetC = 400; // デフォルト

      // その日を含む計画を検索
      final planForDay = weeklyPlans.where((p) => 
        (p.startDate.isBefore(dt) || p.startDate.isAtSameMomentAs(dt)) && 
        (p.endDate.isAfter(dt) || p.endDate.isAtSameMomentAs(dt))
      ).firstOrNull;

      if (planForDay != null) {
        final dp = planForDay.dailyPlans.where((p) => p.dateStr.contains(weekdayStr)).firstOrNull;
        if (dp != null) {
          targetP = dp.targetProtein > 0 ? dp.targetProtein : targetP;
          targetF = dp.targetFat > 0 ? dp.targetFat : targetF;
          targetC = dp.targetCarbs > 0 ? dp.targetCarbs : targetC;
        }
      }

      if (hasPool) { poolTotal++; if (isThisMonth) poolMonth++; }
      if (hasDryland) { drylandTotal++; if (isThisMonth) drylandMonth++; }
      if (dP >= targetP && targetP > 0) { pTotal++; if (isThisMonth) pMonth++; }
      if (dF >= targetF && targetF > 0) { fTotal++; if (isThisMonth) fMonth++; }
      if (dC >= targetC && targetC > 0) { cTotal++; if (isThisMonth) cMonth++; }
    }

    return PremiumCard(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const SizedBox.shrink(),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isNarrow = constraints.maxWidth < 600;
              final trainingBadges = [
                _BadgeCountItem(icon: Icons.pool, color: AppColors.pool, count: showMonthly ? poolMonth : poolTotal, label: '水中'),
                _BadgeCountItem(icon: Icons.fitness_center, color: AppColors.dryland, count: showMonthly ? drylandMonth : drylandTotal, label: '陸トレ'),
              ];
              final nutrientBadges = [
                _BadgeCountItem(icon: Icons.restaurant, color: AppColors.protein, count: showMonthly ? pMonth : pTotal, label: 'P'),
                _BadgeCountItem(icon: Icons.restaurant, color: AppColors.fat, count: showMonthly ? fMonth : fTotal, label: 'F'),
                _BadgeCountItem(icon: Icons.restaurant, color: AppColors.carbs, count: showMonthly ? cMonth : cTotal, label: 'C'),
              ];

              if (isNarrow) {
                return Column(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: trainingBadges,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: nutrientBadges,
                    ),
                  ],
                );
              } else {
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [...trainingBadges, ...nutrientBadges],
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _BadgeCountItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;

  const _BadgeCountItem({required this.icon, required this.color, required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodaySummaryCard extends StatefulWidget {
  final List<TrainingRecord> poolRecords;
  final List<TrainingRecord> drylandRecords;
  final List<TrainingRecord> nutritionRecords;
  final List<TrainingRecord> sleepRecords;
  final AppUser? user;
  final WeeklyPlan? latestPlan;

  const _TodaySummaryCard({
    required this.poolRecords,
    required this.drylandRecords,
    required this.sleepRecords,
    required this.nutritionRecords,
    this.user,
    this.latestPlan,
  });

  @override
  State<_TodaySummaryCard> createState() => _TodaySummaryCardState();
}

class _TodaySummaryCardState extends State<_TodaySummaryCard> {
  final String? _aiEvaluation = null;
  final ScreenshotController _screenshotController = ScreenshotController();
  final ScreenshotController _posterScreenshotController = ScreenshotController();
  final ScreenshotController _mobilePosterScreenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(_TodaySummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  Future<void> _shareSummary() async {
    final ScreenshotController? selectedController = await showModalBottomSheet<ScreenshotController>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('画像サイズを選択', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.smartphone),
              title: const Text('スマホ比率 (縦長)'),
              subtitle: const Text('Instagramのストーリーズや縦長画面に最適'),
              onTap: () => Navigator.pop(context, _mobilePosterScreenshotController),
            ),
            ListTile(
              leading: const Icon(Icons.desktop_windows),
              title: const Text('PC比率 (ワイド)'),
              subtitle: const Text('X(Twitter)やブログなどの横長画面に最適'),
              onTap: () => Navigator.pop(context, _posterScreenshotController),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (selectedController == null) return;

    try {
      final image = await selectedController.capture(
        delay: const Duration(milliseconds: 300),
        pixelRatio: 2.0, // ファイルサイズを抑えてWeb共有の成功率を上げる
      );

      if (image != null) {
        if (kIsWeb) {
          // Web: 画像での共有を試みる
          try {
            await Share.shareXFiles(
              [XFile.fromData(image, name: 'summary.png', mimeType: 'image/png')],
              text: '今日のスイム・コンディショニングサマリー #AquaAnalystAI',
            );
          } catch (e) {
            debugPrint('Web image share failed (Web Share API not fully supported), falling back to download: $e');
            // 共有APIが使えない場合は画像をダウンロードさせる
            saveFile(image, 'aqua_analyst_summary.png');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('画像をダウンロードしました。Instagram等でご利用ください。')),
              );
            }
          }
          return;
        }

        final io.Directory directory = await getTemporaryDirectory();
        final io.File imagePath = await io.File('${directory.path}/summary.png').create();
        await imagePath.writeAsBytes(image);

        await Share.shareXFiles(
          [XFile(imagePath.path)],
          text: '今日のスイム・コンディショニングサマリー #AquaAnalystAI',
        );
      }
    } catch (e) {
      debugPrint('Error sharing summary image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('画像の生成に失敗しました')),
        );
      }
    }
  }

  Future<void> _copySummaryToClipboard() async {
    try {
      final text = _generateSummaryText();
      await Clipboard.setData(ClipboardData(text: text));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('レポート内容をテキストとしてコピーしました')),
        );
      }
    } catch (e) {
      debugPrint('Error copying summary text: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('テキストのコピーに失敗しました')),
        );
      }
    }
  }


  void _shareSummaryText() {
    Share.share(_generateSummaryText());
  }

  String _generateSummaryText() {
    final int totalPoolDuration = widget.poolRecords.fold(0, (sum, r) => sum + r.durationMinutes);
    final poolDist = totalPoolDuration > 0 ? '$totalPoolDuration 分' : '未入力';
    
    final String poolMenu = widget.poolRecords.isNotEmpty
        ? widget.poolRecords.map((r) => r.details.isNotEmpty ? (r.details.first['content'] ?? '記録あり') : '記録あり').join(' / ')
        : '未入力';

    final String drylandMenu = widget.drylandRecords.isNotEmpty
        ? widget.drylandRecords.map((r) {
            if (r.details.isEmpty) return '記録あり';
            final menuTextItem = r.details.where((d) => d['type'] == 'menu_text').firstOrNull;
            if (menuTextItem != null && menuTextItem['content'] != null) return menuTextItem['content'] as String;
            final sets = r.details.where((d) => d['type'] == 'dryland_set');
            if (sets.isNotEmpty) {
              final exercises = <String>{};
              for (var s in sets) { exercises.add('${s['exercise']} ${s['weight']}kg'); }
              return exercises.join(', ');
            }
            return '記録あり';
          }).join(' / ')
        : '未入力';

    double p = 0, f = 0, c = 0;
    for (var r in widget.nutritionRecords) {
      p += r.subjectiveMetrics['protein']?.toDouble() ?? 0.0;
      f += r.subjectiveMetrics['fat']?.toDouble() ?? 0.0;
      c += r.subjectiveMetrics['carbs']?.toDouble() ?? 0.0;
    }

    int targetP = 150, targetF = 70, targetC = 400;
    if (widget.latestPlan != null) {
      final logicalToday = AppDateUtils.logicalToday();
      final weekdayStr = ['月曜','火曜','水曜','木曜','金曜','土曜','日曜'][logicalToday.weekday - 1];
      final todaysPlan = widget.latestPlan!.dailyPlans.where((p) => p.dateStr.contains(weekdayStr)).firstOrNull;
      if (todaysPlan != null) {
        targetP = todaysPlan.targetProtein > 0 ? todaysPlan.targetProtein : targetP;
        targetF = todaysPlan.targetFat > 0 ? todaysPlan.targetFat : targetF;
        targetC = todaysPlan.targetCarbs > 0 ? todaysPlan.targetCarbs : targetC;
      }
    }

    final int totalSleepMinutes = widget.sleepRecords.fold(0, (sum, r) => sum + r.durationMinutes);
    final sleepStr = totalSleepMinutes > 0 
      ? '${(totalSleepMinutes / 60).floor()}時間 ${totalSleepMinutes % 60}分'
      : '未入力';

    return """
🌊 今日の AquaAnalyst 成果！

【水中】$poolDist ($poolMenu)
【陸トレ】$drylandMenu
【栄養】タンパク質: ${p.toInt()}/${targetP}g (${p >= targetP ? '達成' : '不足'}), 脂質: ${f.toInt()}/${targetF}g, 炭水化物: ${c.toInt()}/${targetC}g
【睡眠】$sleepStr

#AquaAnalyst #競泳 #アスリート
""";
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('今日のサマリー', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    _buildModernActionBtn(
                      icon: Icons.copy_all_outlined,
                      onTap: _copySummaryToClipboard,
                      tooltip: 'コピー',
                    ),
                    const SizedBox(width: 8),
                    _buildModernActionBtn(
                      icon: Icons.share_outlined,
                      onTap: _shareSummary,
                      tooltip: '共有',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Stack(
              clipBehavior: Clip.none,
              children: [
                // PC用オフスクリーンキャプチャ (幅1400px, 高さは動的)
                Positioned(
                  left: 5000,
                  top: 0,
                  child: IgnorePointer(
                    child: UnconstrainedBox(
                      child: Screenshot(
                        controller: _posterScreenshotController,
                        child: SizedBox(
                          width: 1400,
                          child: _buildSummaryPosterWidget(context, true, true),
                        ),
                      ),
                    ),
                  ),
                ),
                // スマホ用オフスクリーンキャプチャ (幅480px, 高さは動的)
                Positioned(
                  left: 7000,
                  top: 0,
                  child: IgnorePointer(
                    child: UnconstrainedBox(
                      child: Screenshot(
                        controller: _mobilePosterScreenshotController,
                        child: SizedBox(
                          width: 480,
                          child: _buildSummaryPosterWidget(context, true, true, isMobilePoster: true),
                        ),
                      ),
                    ),
                  ),
                ),
                Screenshot(
                  controller: _screenshotController,
                  child: _buildSummaryPosterWidget(context, false, constraints.maxWidth > 550),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        );
      }
    );
  }

  Widget _buildSummaryPosterWidget(BuildContext context, bool isPosterMode, bool useTwoColumns, {bool isMobilePoster = false}) {
    // derived variables
    final int totalPoolDuration = widget.poolRecords.fold(0, (sum, r) => sum + r.durationMinutes);
    final int totalPoolDistance = widget.poolRecords.fold(0, (sum, r) {
      final dist = r.subjectiveMetrics['total_distance'] as num?;
      return sum + (dist?.toInt() ?? 0);
    });
    final poolDist = totalPoolDistance > 0 ? '$totalPoolDistance m' : '0 m';
    final poolDuration = totalPoolDuration > 0 ? '$totalPoolDuration min' : '';
    final double avgFeeling = widget.poolRecords.isEmpty ? 0 : 
        widget.poolRecords.fold(0.0, (sum, r) => sum + (r.subjectiveMetrics['feeling'] ?? 0.0)) / widget.poolRecords.length;
    final poolDistanceLabel = totalPoolDistance > 0 
        ? '$poolDist ($poolDuration)${avgFeeling > 0 ? ' [Cond: ${avgFeeling.toStringAsFixed(1)}]' : ''}' 
        : '未入力';

    final poolMenuLabel = widget.poolRecords.isNotEmpty
        ? widget.poolRecords.map((r) {
            final content = r.details.map((d) => (d['content'] as String?)?.trim() ?? '').where((s) => s.isNotEmpty).join(', ');
            final condition = r.subjectiveMetrics['condition'] as String?;
            return (condition != null && condition.isNotEmpty) ? '$condition\n$content' : content;
          }).where((s) => s.isNotEmpty).join('\n')
        : '未入力';
    final poolSubjective = widget.poolRecords.isNotEmpty 
        ? (widget.poolRecords.fold(0.0, (sum, r) => sum + (r.subjectiveMetrics['feeling']?.toDouble() ?? 0.0)) / widget.poolRecords.length).round().toString()
        : '-';

    final drylandMenuLabel = widget.drylandRecords.isNotEmpty
        ? widget.drylandRecords.map((r) {
            if (r.details.isEmpty) return '記録あり';
            final menuTexts = r.details.where((d) => d['type'] == 'menu_text').map((d) => (d['content'] as String?)?.trim() ?? '記録あり').where((s) => s.isNotEmpty);
            if (menuTexts.isNotEmpty) return menuTexts.join(', ');
            
            final sets = r.details.where((d) => d['type'] == 'dryland_set');
            if (sets.isNotEmpty) {
              final exercises = <String>{};
              for (var s in sets) { exercises.add('${s['exercise']} ${s['weight']}kg'); }
              return exercises.join(', ');
            }
            return '記録あり';
          }).join('\n')
        : '未入力';

    final drylandSubjective = widget.drylandRecords.isNotEmpty
        ? (widget.drylandRecords.fold(0.0, (sum, r) => sum + (r.subjectiveMetrics['feeling']?.toDouble() ?? 0.0)) / widget.drylandRecords.length).round().toString()
        : '-';

    double proteinValue = 0.0;
    double fatValue = 0.0;
    double carbsValue = 0.0;
    for (var r in widget.nutritionRecords) {
      proteinValue += r.subjectiveMetrics['protein']?.toDouble() ?? 0.0;
      fatValue += r.subjectiveMetrics['fat']?.toDouble() ?? 0.0;
      carbsValue += r.subjectiveMetrics['carbs']?.toDouble() ?? 0.0;
    }
    
    final double totalCalories = (proteinValue * 4) + (fatValue * 9) + (carbsValue * 4);

    // 週間計画から今日の必要量を算出（またはプロフィールからデフォルト値を取得）
    final currentUser = widget.user;
    int targetP = currentUser?.baseProfile['targetProtein'] ?? 150;
    int targetF = currentUser?.baseProfile['targetFat'] ?? 70;
    int targetC = currentUser?.baseProfile['targetCarbs'] ?? 400;
    int targetCalInt = currentUser?.baseProfile['targetCalories'] ?? 2500;

    if (widget.latestPlan != null) {
      final logicalToday = AppDateUtils.logicalToday();
      final weekdayStr = ['月曜','火曜','水曜','木曜','金曜','土曜','日曜'][logicalToday.weekday - 1];
      final todaysPlan = widget.latestPlan!.dailyPlans.where((p) => p.dateStr.contains(weekdayStr)).firstOrNull;
      if (todaysPlan != null) {
        targetP = todaysPlan.targetProtein > 0 ? todaysPlan.targetProtein : targetP;
        targetF = todaysPlan.targetFat > 0 ? todaysPlan.targetFat : targetF;
        targetC = todaysPlan.targetCarbs > 0 ? todaysPlan.targetCarbs : targetC;
        targetCalInt = todaysPlan.targetCalories > 0 ? todaysPlan.targetCalories : targetCalInt;
      }
    }

    // 記録自体に目標値が保存されている場合は、それを最優先（永続化対応）
    final latestWithTarget = widget.nutritionRecords.where((r) => r.dailyTargets != null).firstOrNull;
    if (latestWithTarget != null) {
      targetP = latestWithTarget.dailyTargets!['protein'] ?? targetP;
      targetF = latestWithTarget.dailyTargets!['fat'] ?? targetF;
      targetC = latestWithTarget.dailyTargets!['carbs'] ?? targetC;
      targetCalInt = latestWithTarget.dailyTargets!['calories'] ?? targetCalInt;
    }
    final double targetCalories = targetCalInt.toDouble();
    final int totalSleepMinutes = widget.sleepRecords.fold(0, (sum, r) => sum + r.durationMinutes);
    final sleepStr = totalSleepMinutes > 0 
      ? '${(totalSleepMinutes / 60).floor()}h ${totalSleepMinutes % 60}m'
      : '未入力';

    // 栄養素タイルの推定高さ計算
    double nutritionTileHeight = 6.0 + (widget.nutritionRecords.length * 2.5) + 4.0;
    if (widget.nutritionRecords.isEmpty) nutritionTileHeight = 5.0;

    // 水中タイルの推定高さ
    double poolTileHeight = 4.0 + (poolMenuLabel.length / 25.0);
    
    // 陸上タイルの推定高さ
    double drylandTileHeight = 3.5 + (drylandMenuLabel.length / 25.0);

    // AI評価の推定高さ
    double aiTileHeight = (_aiEvaluation != null) ? (3.0 + (_aiEvaluation!.length / 35.0)) : 0.0;

        // 各セクションのウィジェット構築（フラグを反映）
        final poolSection = _buildSummarySection(
          context,
          icon: Icons.pool,
          label: isPosterMode ? 'Swim' : '水中トレーニング',
          color: AppColors.pool,
          isPoster: isPosterMode,
          topTrailing: isPosterMode ? poolDistanceLabel : null,
          children: [
            if (!isPosterMode) ...[
              _DetailRow(label: '総練習時間', value: poolDistanceLabel),
              if (widget.poolRecords.isNotEmpty)
                _DetailRow(
                  label: 'コンディション',
                  value: '${(widget.poolRecords.fold(0.0, (sum, r) => sum + (r.subjectiveMetrics['feeling'] ?? 0.0)) / widget.poolRecords.length).toStringAsFixed(1)} / 10',
                ),
              const SizedBox(height: 8),
              ...widget.poolRecords.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('${r.durationMinutes}分', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        const Icon(Icons.sentiment_satisfied, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('${r.subjectiveMetrics['feeling']?.round() ?? '-'} / 10', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                    _ExpandableText(r.details.isNotEmpty ? (r.details.first['content'] ?? '記録あり') : '記録あり', forceExpanded: false),
                  ],
                ),
              )),
            ] else
              // ポスター用：水中メニューを段組み表示（テキストが長い場合）
              Builder(builder: (context) {
                final lines = poolMenuLabel.split('\n').where((l) => l.trim().isNotEmpty).toList();
                
                // ポスター用：水中メニューを段組み表示
                if (isPosterMode && !isMobilePoster) {
                  if (lines.length > 15) {
                    // 2段組み（PCポスターでの可読性重視）
                    final mid = (lines.length / 2).ceil();
                    final col1 = lines.sublist(0, mid).join('\n');
                    final col2 = lines.sublist(mid).join('\n');
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(col1, style: const TextStyle(fontSize: 10, height: 1.3))),
                        const SizedBox(width: 8),
                        Expanded(child: Text(col2, style: const TextStyle(fontSize: 10, height: 1.3))),
                      ],
                    );
                  }
                } else if (isMobilePoster && lines.length > 20) {
                  // モバイルポスターでの2段組み
                  final mid = (lines.length / 2).ceil();
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(lines.sublist(0, mid).join('\n'), style: const TextStyle(fontSize: 9, height: 1.3))),
                      const SizedBox(width: 4),
                      Expanded(child: Text(lines.sublist(mid).join('\n'), style: const TextStyle(fontSize: 9, height: 1.3))),
                    ],
                  );
                }
                return Text(poolMenuLabel, style: const TextStyle(fontSize: 12, height: 1.5));
              }),
          ],
        );

        final drylandSection = _buildSummarySection(
          context,
          icon: Icons.fitness_center,
          label: isPosterMode ? 'Dryland' : '陸上トレーニング',
          color: AppColors.dryland,
          isPoster: isPosterMode,
          topTrailing: isPosterMode ? '$drylandSubjective/10' : null,
          children: [
            if (!isPosterMode) ...[
              _DetailRow(label: '主観平均', value: '$drylandSubjective / 10'),
              const SizedBox(height: 8),
              ...widget.drylandRecords.map((r) {
                final String menu = () {
                  if (r.details.isEmpty) return '記録あり';
                  final menuTextItem = r.details.where((d) => d['type'] == 'menu_text').firstOrNull;
                  if (menuTextItem != null && menuTextItem['content'] != null) return menuTextItem['content'] as String;
                  final sets = r.details.where((d) => d['type'] == 'dryland_set');
                  if (sets.isNotEmpty) {
                    final exercises = <String>{};
                    for (var s in sets) { exercises.add('${s['exercise']} ${s['weight']}kg'); }
                    return exercises.join(', ');
                  }
                  return '記録あり';
                }();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.fitness_center, size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          const Text('内容', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          const Icon(Icons.flash_on, size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('疲労 ${r.subjectiveMetrics['feeling']?.round() ?? '-'} / 10', style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                      _ExpandableText(menu, forceExpanded: false),
                    ],
                  ),
                );
              }),
            ] else
              // ポスター用：陸トレメニューを段組み表示（テキストが長い場合）
              Builder(builder: (context) {
                final lines = drylandMenuLabel.split('\n').where((l) => l.trim().isNotEmpty).toList();
                
                // ポスター用：陸トレメニューを段組み表示
                if (isPosterMode && !isMobilePoster) {
                  if (lines.length > 10) {
                    // 2段組み
                    final mid = (lines.length / 2).ceil();
                    final col1 = lines.sublist(0, mid).join('\n');
                    final col2 = lines.sublist(mid).join('\n');
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(col1, style: const TextStyle(fontSize: 10, height: 1.3))),
                        const SizedBox(width: 8),
                        Expanded(child: Text(col2, style: const TextStyle(fontSize: 10, height: 1.3))),
                      ],
                    );
                  }
                } else if (isMobilePoster && lines.length > 15) {
                  // モバイルポスターでの2段組み
                  final mid = (lines.length / 2).ceil();
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(lines.sublist(0, mid).join('\n'), style: const TextStyle(fontSize: 9, height: 1.3))),
                      const SizedBox(width: 4),
                      Expanded(child: Text(lines.sublist(mid).join('\n'), style: const TextStyle(fontSize: 9, height: 1.3))),
                    ],
                  );
                }
                return Text(drylandMenuLabel, style: const TextStyle(fontSize: 12, height: 1.5));
              }),
          ],
        );

        final nutritionSection = _buildSummarySection(
          context,
          icon: Icons.restaurant,
          label: isPosterMode ? 'Nutrition Status' : '栄養状態',
          color: AppColors.carbs,
          isPoster: isPosterMode,
          children: [
            // Poster mode: Skip meal details to save space
            if (!isPosterMode) ...[
              if (widget.nutritionRecords.isEmpty) 
                const _DetailRow(label: '食事内容', value: '未入力'),
              ...widget.nutritionRecords.map((r) {
                final double p = (r.subjectiveMetrics['protein'] as num?)?.toDouble() ?? 0.0;
                final double f = (r.subjectiveMetrics['fat'] as num?)?.toDouble() ?? 0.0;
                final double c = (r.subjectiveMetrics['carbs'] as num?)?.toDouble() ?? 0.0;
                final kcal = (p * 4 + f * 9 + c * 4).round();
                
                return _DetailRow(
                  label: r.subjectiveMetrics['meal_label'] as String? ?? '未分類', 
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _ExpandableText(
                            r.details.isNotEmpty ? r.details.first['content'] : '記録あり',
                            forceExpanded: isPosterMode,
                          )),
                          const SizedBox(width: 8),
                          Text('$kcal kcal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigoAccent.withValues(alpha: 0.8))),
                        ],
                      ),
                    ],
                  )
                );
              }),
              const SizedBox(height: 12),
            ],
            _PfcStatusRow(
              label: isPosterMode ? 'Protein (P)' : 'タンパク質 (P)', 
              value: proteinValue, 
              maxValue: targetP.toDouble(), 
              color: AppColors.protein, 
              status: (targetP > 0 && proteinValue >= targetP) ? (isPosterMode ? 'Goal' : '達成') : (isPosterMode ? 'Short' : '不足'),
              isPoster: isPosterMode,
            ),
            _PfcStatusRow(
              label: isPosterMode ? 'Fat (F)' : '脂質 (F)', 
              value: fatValue, 
              maxValue: targetF.toDouble(), 
              color: AppColors.fat, 
              status: (targetF > 0 && fatValue >= targetF) ? (isPosterMode ? 'Goal' : '達成') : (isPosterMode ? 'Short' : '不足'),
              isPoster: isPosterMode,
            ),
            _PfcStatusRow(
              label: isPosterMode ? 'Carbs (C)' : '炭水化物 (C)', 
              value: carbsValue, 
              maxValue: targetC.toDouble(), 
              color: AppColors.carbs, 
              status: (targetC > 0 && carbsValue >= targetC) ? (isPosterMode ? 'Goal' : '達成') : (isPosterMode ? 'Short' : '不足'),
              isPoster: isPosterMode,
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: isPosterMode ? 8.0 : 4.0),
              child: Divider(height: 1, color: isPosterMode ? Colors.white10 : null),
            ),
            _PfcStatusRow(
              label: isPosterMode ? 'Energy (kcal)' : 'エネルギー (kcal)', 
              value: totalCalories, 
              maxValue: targetCalories > 0 ? targetCalories : 2500, 
              color: Colors.purpleAccent, 
              status: (targetCalories > 0 && totalCalories >= targetCalories) ? (isPosterMode ? 'Goal' : '達成') : (isPosterMode ? 'Short' : '不足'),
              isPoster: isPosterMode,
            ),
          ],
        );

        final sleepSection = _buildSummarySection(
          context,
          icon: Icons.nightlight_round,
          label: isPosterMode ? 'Sleep & Recovery' : '睡眠時間',
          color: AppColors.sleep,
          isPoster: isPosterMode,
          topTrailing: isPosterMode ? sleepStr : null,
          children: [
            if (widget.sleepRecords.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isPosterMode) ...[
                    Text(
                      sleepStr,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: _ExpandableText(
                            widget.sleepRecords.length == 1 
                                ? (widget.sleepRecords.first.details.isNotEmpty ? widget.sleepRecords.first.details.first['content'] : '良質な睡眠を確保しました')
                                : '${widget.sleepRecords.length}件の記録に基づいています',
                            forceExpanded: false,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          sleepStr,
                          style: const TextStyle(
                            fontSize: 22, 
                            fontWeight: FontWeight.w900, 
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('未入力', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
          ],
        );

        // AI評価タイル
        Widget? aiSection;
        if (_aiEvaluation != null) {
          aiSection = _buildSummarySection(
            context,
            icon: Icons.wb_twilight,
            label: isPosterMode ? 'Coach Insights' : 'AIコーチの評価',
            color: AppColors.pool,
            isPoster: isPosterMode,
            children: [
              Text(
                _aiEvaluation!,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          );
        }

        // 2カラム：PCでの通常表示やポスター表示（以前の3カラムは幅が狭いため廃止）
        Widget contentLayout;
        if (useTwoColumns) {
          // 栄養状態以外のタイルで2カラムを構成
          final tiles = [
            _LayoutTile(widget: poolSection, height: poolTileHeight),
            _LayoutTile(widget: drylandSection, height: drylandTileHeight),
            _LayoutTile(widget: sleepSection, height: 3.5),
            if (aiSection != null) _LayoutTile(widget: aiSection, height: aiTileHeight),
          ];

          final leftColWidgets = <Widget>[];
          final rightColWidgets = <Widget>[];
          double leftH = 0, rightH = 0;
          for (var tile in tiles) {
            if (leftH <= rightH) {
              leftColWidgets.add(tile.widget);
              leftColWidgets.add(const SizedBox(height: 16));
              leftH += tile.height;
            } else {
              rightColWidgets.add(tile.widget);
              rightColWidgets.add(const SizedBox(height: 16));
              rightH += tile.height;
            }
          }
          
          contentLayout = Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: leftColWidgets)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(children: rightColWidgets)),
                ],
              ),
              const SizedBox(height: 8),
              nutritionSection, // 栄養状態のみ最下部で全幅を使用
            ],
          );
        } else {
          // シングルカラム
          contentLayout = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              poolSection, const SizedBox(height: 8),
              drylandSection, const SizedBox(height: 8),
              sleepSection, const SizedBox(height: 8),
              if (aiSection != null) ...[aiSection, const SizedBox(height: 8)],
              nutritionSection, // シングルカラムでも最下部に配置
            ],
          );
        }

        
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final Color posterBgColor = isDarkMode ? const Color(0xFF0F172A) : Colors.white;
        final Color posterHeaderColor = isDarkMode ? Colors.white : const Color(0xFF0F172A);
        final Color posterSubHeaderColor = isDarkMode ? Colors.white70 : Colors.black54;

        final Widget body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ヘッダー部分
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPosterMode ? 'DAILY SUMMARY' : 'ACHIEVEMENT',
                      style: TextStyle(
                        fontSize: isPosterMode ? (isMobilePoster ? 24 : 32) : 24, 
                        fontWeight: FontWeight.w900, 
                        letterSpacing: 1.5,
                        color: isPosterMode ? posterHeaderColor : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPosterMode 
                        ? '${AppDateUtils.logicalToday().month}/${AppDateUtils.logicalToday().day} 成果報告'
                        : '${AppDateUtils.logicalToday().year}/${AppDateUtils.logicalToday().month}/${AppDateUtils.logicalToday().day}',
                      style: TextStyle(
                        fontSize: isPosterMode ? (isMobilePoster ? 16 : 18) : 22, 
                        fontWeight: FontWeight.bold,
                        color: isPosterMode ? posterSubHeaderColor : null,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isPosterMode ? 16 : 12, vertical: isPosterMode ? 8 : 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    'AquaAnalyst AI',
                    style: TextStyle(color: Colors.white, fontSize: isPosterMode ? 14 : 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (isPosterMode) const SizedBox(height: 32) else const SizedBox(height: 24),
                
            contentLayout,
            
            if (isPosterMode) const SizedBox(height: 24) else const SizedBox(height: 24),
            // Attribution is now handled by the Positioned widget in the Stack
          ],
        );

        final double horizontalPadding = isPosterMode ? (isMobilePoster ? 16.0 : 32.0) : 24.0;
        final double verticalPadding = isPosterMode ? (isMobilePoster ? 32.0 : 32.0) : 24.0;

        // スマホ幅: FittedBoxを使わず、はみ出しを許可する
        // PC幅: FittedBoxを使わず、高さを動的に伸ばして1ページに収める
        // ヘッダー・フッター・タイルのサイズは固定（縮小しない）

        return Container(
                width: isMobilePoster ? 480 : (isPosterMode ? 1400 : null),
                // PC版：高さを固定せず動的に伸ばす（内容量に応じて）
                // スマホ版：高さを固定せず、はみ出しOK
                height: isMobilePoster ? 853.0 : (isPosterMode ? null : null),
                constraints: (!isPosterMode) ? const BoxConstraints(minWidth: 320, maxWidth: 650) : null,
                decoration: BoxDecoration(
                  color: isPosterMode ? posterBgColor : null,
                  gradient: isPosterMode ? null : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDarkMode
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [Colors.white, const Color(0xFFF1F5F9)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: isPosterMode ? null : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: isPosterMode 
                        ? (isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05))
                        : (isDarkMode
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.blue.withValues(alpha: 0.1)),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    if (!isPosterMode) Positioned(
                      right: -20,
                      top: -20,
                      child: Icon(
                        Icons.emoji_events_outlined,
                        size: 150,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.04),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding + 40),
                      child: body,
                    ),
                    Positioned(
                      bottom: 16,
                      right: horizontalPadding,
                      child: Text(
                        'Generated by AquaAnalyst AI',
                        style: TextStyle(
                          fontSize: isMobilePoster ? 10 : 12,
                          color: isDarkMode ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.3),
                          fontStyle: FontStyle.italic,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              );
  }


  Widget _buildModernActionBtn({required IconData icon, required VoidCallback onTap, required String tooltip}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        onPressed: onTap,
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildSummarySection(BuildContext context, {
    required IconData icon, 
    required String label, 
    required Color color, 
    required List<Widget> children, 
    bool isPoster = false,
    String? topTrailing,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final effectiveColor = isLight ? AppColors.getEffectiveColor(context, color) : color;
    
    // ポスターモード時は大文字化
    final displayLabel = isPoster ? label.toUpperCase() : label;
    
    return Container(
      decoration: BoxDecoration(
        color: isPoster 
            ? (isLight ? Colors.white : const Color(0xFF1E293B).withValues(alpha: 0.4))
            : effectiveColor.withValues(alpha: isLight ? 0.08 : 0.03),
        borderRadius: BorderRadius.circular(isPoster ? 12 : 16),
        border: Border.all(
          color: isPoster
              ? (isLight ? Colors.blue.withValues(alpha: 0.1) : const Color(0xFF334155).withValues(alpha: 0.8))
              : effectiveColor.withValues(alpha: isLight ? 0.3 : 0.15)
        ),
      ),
      padding: EdgeInsets.all(isPoster ? 12 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!isPoster) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: effectiveColor, size: 20),
                ),
                const SizedBox(width: 12),
              ] else ...[
                Icon(icon, color: effectiveColor, size: 16),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  displayLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isPoster ? 12 : 15,
                    fontWeight: isPoster ? FontWeight.w900 : FontWeight.bold,
                    letterSpacing: isPoster ? 1.2 : null,
                    color: isPoster
                        ? effectiveColor.withValues(alpha: 0.9)
                        : (Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.9) : Colors.black87),
                  ),
                ),
              ),
              if (topTrailing != null) ...[
                const Spacer(),
                Text(
                  topTrailing,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          SizedBox(height: isPoster ? 6 : 16), // 12から6に短縮
          ...children,
        ],
      ),
    );
  }
}

class _ActivityCalendar extends ConsumerStatefulWidget {
  const _ActivityCalendar({super.key});

  @override
  ConsumerState<_ActivityCalendar> createState() => _ActivityCalendarState();
}

class _ActivityCalendarState extends ConsumerState<_ActivityCalendar> {
  DateTime _currentMonth = DateTime.now();

  List<DateTime> _getDaysInMonth() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_currentMonth.year, _currentMonth.month);
    final firstWeekday = firstDay.weekday; // 1(Mon) to 7(Sun)
    
    List<DateTime> days = [];
    final paddingDays = firstWeekday == 7 ? 0 : firstWeekday;
    for (int i = 0; i < paddingDays; i++) {
        days.add(firstDay.subtract(Duration(days: paddingDays - i)));
    }
    
    for (int i = 0; i < daysInMonth; i++) {
      days.add(firstDay.add(Duration(days: i)));
    }
    
    final remainingSpace = 42 - days.length; 
    final lastDay = days.last;
    if (remainingSpace > 0 && remainingSpace < 7) {
      for (int i = 1; i <= remainingSpace; i++) {
          days.add(lastDay.add(Duration(days: i)));
      }
    }
    return days;
  }


  void _showRecordDetails(BuildContext context, DateTime date, List<TrainingRecord> dayRecords) {
    if (dayRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${date.month}/${date.day} は記録がありません。'), duration: const Duration(seconds: 1)),
      );
      return;
    }

    // カテゴリごとに整理
    final poolRecords = dayRecords.where((r) => r.type == 'pool').toList();
    final drylandRecords = dayRecords.where((r) => r.type == 'dryland').toList();
    final nutritionRecords = dayRecords.where((r) => r.type == 'nutrition').toList();
    final sleepRecords = dayRecords.where((r) => r.type == 'sleep').toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) => SafeArea(
            child: Column(
              children: [
                // ハンドル
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.event, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('${date.year}年${date.month}月${date.day}日のアクティビティ', 
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      // 水中トレーニングブロック
                      _buildCategoryBlock(
                        context,
                        title: '水中トレーニング',
                        icon: Icons.pool,
                        color: AppColors.pool,
                        records: poolRecords,
                        summary: poolRecords.isEmpty ? '記録なし' : '${poolRecords.fold(0, (sum, r) => sum + r.durationMinutes)}分',
                        contentPreview: poolRecords.map((r) => r.details.firstOrNull?['content'] ?? '記録あり').join(', '),
                        onTapRecord: (r) { Navigator.pop(ctx); _showEditRecordDialog(context, r); },
                      ),
                      const SizedBox(height: 12),
                      
                      // 陸上トレーニングブロック
                      _buildCategoryBlock(
                        context,
                        title: '陸上トレーニング',
                        icon: Icons.fitness_center,
                        color: AppColors.dryland,
                        records: drylandRecords,
                        summary: drylandRecords.isEmpty ? '記録なし' : '${drylandRecords.length}件の記録',
                        contentPreview: drylandRecords.map((r) {
                          final menu = r.details.where((d) => d['type'] == 'menu_text').firstOrNull;
                          return menu?['content'] ?? '記録あり';
                        }).join(', '),
                        onTapRecord: (r) { Navigator.pop(ctx); _showEditRecordDialog(context, r); },
                      ),
                      const SizedBox(height: 12),
                      
                      // 栄養状態ブロック
                      _buildCategoryBlock(
                        context,
                        title: '栄養状態',
                        icon: Icons.restaurant,
                        color: AppColors.carbs,
                        records: nutritionRecords,
                        summary: nutritionRecords.isEmpty ? '記録なし' : () {
                          double p = 0, f = 0, c = 0;
                          for (var r in nutritionRecords) {
                            p += r.subjectiveMetrics['protein']?.toDouble() ?? 0;
                            f += r.subjectiveMetrics['fat']?.toDouble() ?? 0;
                            c += r.subjectiveMetrics['carbs']?.toDouble() ?? 0;
                          }
                          return 'P:${p.toInt()} F:${f.toInt()} C:${c.toInt()}';
                        }(),
                        contentPreview: nutritionRecords.map((r) => r.subjectiveMetrics['meal_label'] ?? '未分類').join(', '),
                        onTapRecord: (r) { Navigator.pop(ctx); _showEditRecordDialog(context, r); },
                      ),
                      const SizedBox(height: 12),
                      
                      // 睡眠時間ブロック
                      _buildCategoryBlock(
                        context,
                        title: '睡眠時間',
                        icon: Icons.bedtime,
                        color: AppColors.sleep,
                        records: sleepRecords,
                        summary: sleepRecords.isEmpty ? '記録なし' : () {
                          final totalMins = sleepRecords.fold(0, (sum, r) => sum + r.durationMinutes);
                          return '${(totalMins / 60).floor()}時間 ${totalMins % 60}分';
                        }(),
                        contentPreview: sleepRecords.isEmpty ? '' : '記録あり',
                        onTapRecord: (r) { Navigator.pop(ctx); _showEditRecordDialog(context, r); },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildCategoryBlock(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<TrainingRecord> records,
    required String summary,
    required String contentPreview,
    required Function(TrainingRecord) onTapRecord,
  }) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final effectiveColor = isLight ? AppColors.getEffectiveColor(context, color) : color;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: effectiveColor.withValues(alpha: isLight ? 0.3 : 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: effectiveColor.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(icon, size: 20, color: effectiveColor),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: effectiveColor)),
                const Spacer(),
                if (records.isNotEmpty)
                  Text(summary, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: effectiveColor)),
              ],
            ),
          ),
          if (records.isEmpty)
             const Padding(
               padding: EdgeInsets.all(16.0),
               child: Text('記録がありません', style: TextStyle(color: Colors.grey, fontSize: 13)),
             )
          else
            ...records.map((r) => Material(
              color: Colors.transparent,
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(
                  r.type == 'nutrition' ? (r.subjectiveMetrics['meal_label'] ?? '未分類') : (r.details.firstOrNull?['content'] ?? '記録あり'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right, size: 16),
                onTap: () => onTapRecord(r),
              ),
            )),
        ],
      ),
    );
  }

  void _showEditRecordDialog(BuildContext context, TrainingRecord record) {
    showDialog(
      context: context,
      builder: (ctx) {
        final GlobalKey<dynamic> formKey = GlobalKey();
        return AlertDialog(
          title: Text(
            '記録の編集 (${record.type == 'pool' ? '水中' : record.type == 'dryland' ? '陸トレ' : '栄養'})',
            style: const TextStyle(fontSize: 16),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: record.type == 'nutrition'
                ? NutritionForm(key: formKey, initialRecord: record, isDialog: true, onSaveSuccess: () => Navigator.pop(ctx))
                : TrainingForm(key: formKey, initialRecord: record, isDialog: true, onSaveSuccess: () => Navigator.pop(ctx)),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    title: const Text('削除の確認'),
                    content: const Text('この記録を削除してもよろしいですか？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await FirestoreService().deleteTrainingRecord(record.id);
                  if (record.type == 'dryland') {
                    await FirestoreService().generateInitialDrylandPbs();
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('記録を削除しました。')));
                  }
                }
              },
              child: const Text('削除', style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () {
                final dynamic state = formKey.currentState;
                if (state != null) {
                  // ignore: avoid_dynamic_calls
                  state.saveRecord();
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final weeklyPlans = ref.watch(weeklyPlansProvider).value ?? [];
    final days = _getDaysInMonth();
    final today = DateTime.now();
    final weekDays = ['日', '月', '火', '水', '木', '金', '土'];

    return PremiumCard(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
                  });
                },
              ),
              Text('${_currentMonth.year}年 ${_currentMonth.month}月', style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekDays.map((w) => Text(w, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))).toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.0,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final date = days[index];
              final isCurrentMonth = date.month == _currentMonth.month;
              final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
              
              final dateKey = "${date.year}-${date.month}-${date.day}";
              final groupedRecords = ref.watch(recordsByEffectiveDayProvider);
              final dayRecords = groupedRecords[dateKey] ?? [];
              
              final hasPool = dayRecords.any((r) => r.type == 'pool');
              final hasDryland = dayRecords.any((r) => r.type == 'dryland');
              
              bool pOk = false, fOk = false, cOk = false;
              final nutRecords = dayRecords.where((r) => r.type == 'nutrition' && r.subjectiveMetrics['is_body_composition'] != true);
              if (nutRecords.isNotEmpty) {
                double dP = 0, dF = 0, dC = 0;
                for (var r in nutRecords) {
                  dP += r.subjectiveMetrics['protein']?.toDouble() ?? 0.0;
                  dF += r.subjectiveMetrics['fat']?.toDouble() ?? 0.0;
                  dC += r.subjectiveMetrics['carbs']?.toDouble() ?? 0.0;
                }

                // その日の目標値を取得（曜日に基づく）
                final weekdayStr = ['月','火','水','木','金','土','日'][date.weekday - 1];
                int targetP = 150, targetF = 70, targetC = 400;

                 // その日を含む計画を検索
                 final planForDay = weeklyPlans.where((p) => 
                   (p.startDate.isBefore(date) || p.startDate.isAtSameMomentAs(date)) && 
                   (p.endDate.isAfter(date) || p.endDate.isAtSameMomentAs(date))
                 ).firstOrNull;
 
                 if (planForDay != null) {
                   final dp = planForDay.dailyPlans.where((p) => p.dateStr.contains(weekdayStr)).firstOrNull;
                   if (dp != null) {
                     targetP = dp.targetProtein > 0 ? dp.targetProtein : targetP;
                     targetF = dp.targetFat > 0 ? dp.targetFat : targetF;
                     targetC = dp.targetCarbs > 0 ? dp.targetCarbs : targetC;
                   }
                 }
 
                 // 記録自体に目標値が保存されている場合は、それを最優先する
                 final latestWithTarget = nutRecords.where((r) => r.dailyTargets != null).firstOrNull;
                 if (latestWithTarget != null) {
                   targetP = latestWithTarget.dailyTargets!['protein'] ?? targetP;
                   targetF = latestWithTarget.dailyTargets!['fat'] ?? targetF;
                   targetC = latestWithTarget.dailyTargets!['carbs'] ?? targetC;
                 }
 
                 pOk = targetP > 0 && dP >= targetP;
                 fOk = targetF > 0 && dF >= targetF;
                 cOk = targetC > 0 && dC >= targetC;
              }

              return GestureDetector(
                onTap: () => _showRecordDetails(context, date, dayRecords),
                child: Container(
                  decoration: BoxDecoration(
                    color: isToday ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isToday ? Border.all(color: Theme.of(context).colorScheme.primary) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          color: isCurrentMonth ? Theme.of(context).colorScheme.onSurface : Colors.grey.withValues(alpha: 0.5),
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 1,
                        runSpacing: 1,
                        alignment: WrapAlignment.center,
                        children: [
                          if (hasPool) Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.pool, shape: BoxShape.circle)),
                          if (hasDryland) Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.dryland, shape: BoxShape.circle)),
                          if (pOk) Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.protein, shape: BoxShape.circle)),
                          if (fOk) Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.fat, shape: BoxShape.circle)),
                          if (cOk) Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.carbs, shape: BoxShape.circle)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  final String text;
  final int maxLines;
  final bool forceExpanded;
  const _ExpandableText(this.text, {this.maxLines = 3, this.forceExpanded = false});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty || widget.text == '未入力') {
      return const Text('未入力', style: TextStyle(fontSize: 13, color: Colors.grey));
    }

    final bool effectivelyExpanded = _isExpanded || widget.forceExpanded;
    final lines = widget.text.split('\n').length;
    final isLongText = lines > widget.maxLines || widget.text.length > 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: effectivelyExpanded ? null : widget.maxLines,
          overflow: effectivelyExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        if (isLongText && !widget.forceExpanded)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
              child: Text(
                effectivelyExpanded ? '閉じる' : '続きを読む...',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
class _LayoutTile {
  final Widget widget;
  final double height;
  _LayoutTile({required this.widget, required this.height});
}
