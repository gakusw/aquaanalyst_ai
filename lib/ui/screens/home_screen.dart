import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/firestore_service.dart';
import '../../data/models/training_record.dart';
import '../../data/models/personal_best.dart';
import '../../data/models/goal_time.dart';
import '../../data/models/weekly_plan.dart';
import '../../data/models/app_user.dart';
import '../../utils/event_utils.dart';
import '../../utils/date_utils.dart';
import '../../utils/app_colors.dart';
import '../../data/providers/providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  int _bodyCompOffset = 1; // デフォルトで今月を右から2番目にするためのオフセット
  bool _showMonthlyBadges = true; // バッジ表示切替フラグ

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
        title: const Text('ホーム'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                    // バッジ統計ウィジェット
                    _BadgeCountSection(
                      showMonthly: _showMonthlyBadges,
                      onToggle: (val) => setState(() => _showMonthlyBadges = val),
                    ),
                    const SizedBox(height: 24),

                    // 今日のサマリー
                    _TodaySummaryCard(
                      poolRecord: poolRecord,
                      drylandRecord: drylandRecord,
                      nutritionRecords: todayRecords.where((r) => 
                        r.type == 'nutrition' && 
                        r.subjectiveMetrics['is_body_composition'] != true
                      ).toList(),
                      sleepRecord: todayRecords.where((r) => r.type == 'sleep').firstOrNull,
                      user: user,
                      latestPlan: plan,
                    ),
                    const SizedBox(height: 24),

                    // アクティビティカレンダー
                    const _ActivityCalendar(),
                    const SizedBox(height: 24),

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
            
            const SizedBox(height: 80), // FAB が被らないよう余白
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showBodyCompositionHistory(context, bodyCompRecords),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(icon: Icons.monitor_weight, label: '直近の計測値 ($dateStr)', color: Colors.purpleAccent),
              const SizedBox(height: 12),
              _DetailRow(label: '体重', value: weight > 0 ? '$weight kg' : '未入力'),
              _DetailRow(label: '骨格筋量', value: muscle > 0 ? '$muscle kg' : '未入力'),
              _DetailRow(label: '体脂肪率', value: fat > 0 ? '$fat %' : '未入力'),
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
              const SizedBox(height: 8),
              const Center(child: Text('タップして推移を表示', style: TextStyle(fontSize: 10, color: Colors.grey))),
            ],
          ),
        ),
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
              Icon(Icons.bedtime, color: Colors.pinkAccent),
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
            ElevatedButton(
              onPressed: () async {
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
                
                await _firestoreService.addTrainingRecord(record);
                if (ctx.mounted) {
                  context.go('/home'); 
                  Navigator.pop(ctx);
                }
              },
              child: const Text('保存'),
            ),
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
            ElevatedButton(
              onPressed: () async {
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
                  await _firestoreService.savePersonalBest(pb);
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('保存'),
            ),
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
            const Icon(Icons.info_outline, size: 48, color: Colors.grey),
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
            color: Colors.teal.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BEST TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.light ? Colors.teal.shade900 : Colors.tealAccent)),
                  Text(_formatSeconds(pb.value), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.light ? Colors.teal.shade900 : Colors.tealAccent)),
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
                        Text('(${lap['time'] ?? ''})', style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.light ? Colors.teal.shade800 : Colors.tealAccent)),
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
    
    final minX = xValues.length == 1 ? xValues.first - 86400000 : xValues.reduce((a, b) => a < b ? a : b);
    final maxX = xValues.length == 1 ? xValues.first + 86400000 : xValues.reduce((a, b) => a > b ? a : b);
    
    final minY = yValues.reduce((a, b) => a < b ? a : b) - 1.0;
    final maxY = yValues.reduce((a, b) => a > b ? a : b) + 1.0;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: isTime ? Colors.teal : Colors.orange,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
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
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(AppDateUtils.getChartLabel(value), style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
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
    
    final minX = xValues.length == 1 ? xValues.first - 86400000 : xValues.reduce((a, b) => a < b ? a : b);
    final maxX = xValues.length == 1 ? xValues.first + 86400000 : xValues.reduce((a, b) => a > b ? a : b);

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
                          spots: weightSpots, color: Colors.blue, barWidth: 3, dotData: const FlDotData(show: true), isCurved: true,
                        ),
                      if (muscleSpots.isNotEmpty)
                        LineChartBarData(
                          spots: muscleSpots, color: Colors.green, barWidth: 3, dotData: const FlDotData(show: true), isCurved: true,
                        ),
                      if (normalizedFatSpots.isNotEmpty)
                        LineChartBarData(
                          spots: normalizedFatSpots, color: Colors.orange, barWidth: 3, dotData: const FlDotData(show: true), isCurved: true,
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
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(AppDateUtils.getChartLabel(v), style: const TextStyle(fontSize: 9)),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
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

  Widget _buildBestTimeCard(BuildContext context, PersonalBest pb, List<PersonalBest> history) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.timer, color: Colors.white)),
        title: Text(pb.event, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(pb.value.toStringAsFixed(2), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent.withOpacity(0.8))),
        subtitle: Text('${pb.date.year}/${pb.date.month}/${pb.date.day}'),
        onTap: () => _showPbHistoryDialog(context, pb.event, history, isTime: true),
        onLongPress: () => _showPbOptionsDialog(context, pb),
      ),
    );
  }

  Widget _buildWeightBestCard(BuildContext context, PersonalBest pb, List<PersonalBest> history) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.fitness_center, color: Colors.white)),
        title: Text(pb.event, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text('${pb.value.toStringAsFixed(1)} kg', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amber.withOpacity(0.8))),
        subtitle: Text('達成日: ${pb.date.year}/${pb.date.month}/${pb.date.day}'),
        onTap: () => _showPbHistoryDialog(context, pb.event, history, isTime: false),
        onLongPress: () => _showPbOptionsDialog(context, pb),
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

  Widget _buildGoalTimeCard(BuildContext context, GoalTime gt) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.flag, color: Colors.white)),
        title: Text(gt.event, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(gt.value.toStringAsFixed(2), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent.withOpacity(0.7))),
        subtitle: const Text('目標タイム'),
        onLongPress: () => _showGoalOptionsDialog(context, gt),
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
        isCurved: true,
        color: Colors.teal,
        barWidth: 3,
        dotData: const FlDotData(show: true),
      ),
      LineChartBarData(
        spots: muscleSpots,
        isCurved: true,
        color: Colors.orange,
        barWidth: 3,
        dotData: const FlDotData(show: true),
      ),
    ];
  }

  LineChartData _buildBodyCompChartData(List<TrainingRecord> allRecords) {
    final now = DateTime.now();
    final baseMonth = DateTime(now.year, now.month - _bodyCompOffset + 1, 1);
    const months = ['', '1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'];
    final monthLabels = <String>[];
    for (int i = 11; i >= 0; i--) {
      final d = DateTime(baseMonth.year, baseMonth.month - i, 1);
      monthLabels.add(months[d.month]);
    }

    final bars = _buildBodyCompLineBars(allRecords);
    double minY = 30;
    double maxY = 80;
    final allYValues = bars.expand((b) => b.spots.map((s) => s.y)).toList();
    if (allYValues.isNotEmpty) {
      final actualMin = allYValues.reduce((a, b) => a < b ? a : b);
      final actualMax = allYValues.reduce((a, b) => a > b ? a : b);
      minY = (actualMin - 5).clamp(0, 200).toDouble();
      maxY = (actualMax + 5).clamp(minY + 10, 300).toDouble();
    }

    return LineChartData(
      minX: 1, maxX: 12, minY: minY, maxY: maxY,
      gridData: const FlGridData(show: true),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54))),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (val, meta) {
              final idx = val.toInt() - 1;
              if (idx < 0 || idx >= 12) return const SizedBox.shrink();
              return Text(monthLabels[idx], style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)));
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24))),
      lineBarsData: bars,
    );
  }
  String _formatSeconds(double seconds) {
    if (seconds <= 0) return '0.00';
    final int min = (seconds / 60).floor();
    final double sec = seconds % 60;
    if (min == 0) return sec.toStringAsFixed(2);
    return '$min:${sec.toStringAsFixed(2).padLeft(5, '0')}';
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
    final labelColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: TextStyle(color: labelColor, fontSize: 13))),
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
  const _PfcStatusRow({required this.label, required this.value, required this.maxValue, required this.color, required this.status});
  @override
  Widget build(BuildContext context) {
    final labelColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    final bgColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.08);
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
        Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class _BadgeCountSection extends ConsumerWidget {
  final bool showMonthly;
  final Function(bool) onToggle;
  const _BadgeCountSection({super.key, required this.showMonthly, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsByEffectiveDay = ref.watch(recordsByEffectiveDayProvider);
    final latestPlan = ref.watch(latestWeeklyPlanProvider).value;
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

      // 目標値（その曜日のものを取得）
      final dt = DateTime(y, m, d);
      final weekdayStr = ['月','火','水','木','金','土','日'][dt.weekday - 1];
      int targetP = 150, targetF = 70, targetC = 400; // デフォルト
      if (latestPlan != null) {
        final dp = latestPlan!.dailyPlans.where((p) => p.dateStr.contains(weekdayStr)).firstOrNull;
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

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('バッジコレクション', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('今月', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: false, label: Text('累計', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {showMonthly},
                  onSelectionChanged: (val) => onToggle(val.first),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _BadgeCountItem(icon: Icons.pool, color: AppColors.pool, count: showMonthly ? poolMonth : poolTotal, label: '水中'),
                _BadgeCountItem(icon: Icons.fitness_center, color: AppColors.dryland, count: showMonthly ? drylandMonth : drylandTotal, label: '陸トレ'),
                _BadgeCountItem(icon: Icons.restaurant, color: AppColors.protein, count: showMonthly ? pMonth : pTotal, label: 'P'),
                _BadgeCountItem(icon: Icons.restaurant, color: AppColors.fat, count: showMonthly ? fMonth : fTotal, label: 'F'),
                _BadgeCountItem(icon: Icons.restaurant, color: AppColors.carbs, count: showMonthly ? cMonth : cTotal, label: 'C'),
              ],
            ),
          ],
        ),
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
        border: Border.all(color: color.withOpacity(0.2)),
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
class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;
  const _LegendItem({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _TodaySummaryCard extends StatefulWidget {
  final TrainingRecord? poolRecord;
  final TrainingRecord? drylandRecord;
  final TrainingRecord? sleepRecord;
  final List<TrainingRecord> nutritionRecords;
  final AppUser? user;
  final WeeklyPlan? latestPlan;
  final VoidCallback? onAddSleepPressed;

  const _TodaySummaryCard({
    required this.poolRecord,
    required this.drylandRecord,
    required this.sleepRecord,
    required this.nutritionRecords,
    this.user,
    this.latestPlan,
    this.onAddSleepPressed,
  });

  @override
  State<_TodaySummaryCard> createState() => _TodaySummaryCardState();
}

class _TodaySummaryCardState extends State<_TodaySummaryCard> {
  final String? _aiEvaluation = null;
  final ScreenshotController _screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(_TodaySummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  Future<void> _shareSummary() async {
    try {
      // スクリーンショットを撮影
      final image = await _screenshotController.capture(
        delay: const Duration(milliseconds: 10),
        pixelRatio: 2.0, // 高画質化
      );

      if (image != null) {
        final directory = await getTemporaryDirectory();
        final imagePath = await File('${directory.path}/summary.png').create();
        await imagePath.writeAsBytes(image);

        await Share.shareXFiles(
          [XFile(imagePath.path)],
          text: '今日のスイム・コンディショニングサマリー #AquaAnalystAI',
        );
      }
    } catch (e) {
      debugPrint('Error sharing summary image: $e');
      // フォールバックとして従来のテキスト共有を行う
      _shareSummaryText();
    }
  }

  void _shareSummaryText() {
    final poolDist = widget.poolRecord != null ? '${widget.poolRecord!.durationMinutes}分' : '未入力';
    final poolMenu = widget.poolRecord != null && widget.poolRecord!.details.isNotEmpty
        ? widget.poolRecord!.details.first['content'] ?? '記録あり' : '未入力';

    String drylandMenu = '未入力';
    if (widget.drylandRecord != null && widget.drylandRecord!.details.isNotEmpty) {
      final menuTextItem = widget.drylandRecord!.details.where((d) => d['type'] == 'menu_text').firstOrNull;
      if (menuTextItem != null) {
        drylandMenu = menuTextItem['content'] as String;
      } else {
        final sets = widget.drylandRecord!.details.where((d) => d['type'] == 'dryland_set');
        if (sets.isNotEmpty) {
          final exercises = <String>{};
          for (var s in sets) { exercises.add('${s['exercise']} ${s['weight']}kg'); }
          drylandMenu = exercises.join(', ');
        }
      }
    }

    double p = 0, f = 0, c = 0;
    for (var r in widget.nutritionRecords) {
      p += r.subjectiveMetrics['protein']?.toDouble() ?? 0.0;
      f += r.subjectiveMetrics['fat']?.toDouble() ?? 0.0;
      c += r.subjectiveMetrics['carbs']?.toDouble() ?? 0.0;
    }

    int targetP = 150, targetF = 70, targetC = 400;
    if (widget.latestPlan != null) {
      final logicalToday = AppDateUtils.logicalToday();
      final weekdayStr = ['月','火','水','木','金','土','日'][logicalToday.weekday - 1];
      final todaysPlan = widget.latestPlan!.dailyPlans.where((p) => p.dateStr.contains(weekdayStr)).firstOrNull;
      if (todaysPlan != null) {
        targetP = todaysPlan.targetProtein > 0 ? todaysPlan.targetProtein : targetP;
        targetF = todaysPlan.targetFat > 0 ? todaysPlan.targetFat : targetF;
        targetC = todaysPlan.targetCarbs > 0 ? todaysPlan.targetCarbs : targetC;
      }
    }

    final sleepStr = widget.sleepRecord != null
        ? '${(widget.sleepRecord!.durationMinutes / 60).floor()}時間 ${widget.sleepRecord!.durationMinutes % 60}分'
        : '未入力';

    final text = """
🌊 今日の AquaAnalyst 成果！

【水中】$poolDist ($poolMenu)
【陸トレ】$drylandMenu
【栄養】P: ${p.toInt()}/${targetP}g (${p >= targetP ? '達成' : '不足'}), F: ${f.toInt()}/${targetF}g, C: ${c.toInt()}/${targetC}g
【睡眠】$sleepStr

#AquaAnalyst #競泳 #アスリート
""";

    Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    // derived variables
    final poolDistanceLabel = widget.poolRecord != null && widget.poolRecord!.durationMinutes > 0 
      ? '${widget.poolRecord!.durationMinutes} 分' : '未入力';
    final poolMenuLabel = widget.poolRecord != null && widget.poolRecord!.details.isNotEmpty 
      ? widget.poolRecord!.details.first['content'] ?? '記録あり' : '未入力';
    final poolSubjective = widget.poolRecord?.subjectiveMetrics['feeling']?.round()?.toString() ?? '-';

    final drylandMenuLabel = () {
      if (widget.drylandRecord == null || widget.drylandRecord!.details.isEmpty) return '未入力';
      // menu_text タイプからコンテンツを取得
      final menuTextItem = widget.drylandRecord!.details.where((d) => d['type'] == 'menu_text').firstOrNull;
      if (menuTextItem != null && menuTextItem['content'] != null) return menuTextItem['content'] as String;
      // menu_text がない場合は dryland_set からサマリーを生成
      final sets = widget.drylandRecord!.details.where((d) => d['type'] == 'dryland_set');
      if (sets.isNotEmpty) {
        final exercises = <String>{};
        for (var s in sets) { exercises.add('${s['exercise']} ${s['weight']}kg'); }
        return exercises.join(', ');
      }
      return '記録あり';
    }();
    final drylandSubjective = widget.drylandRecord?.subjectiveMetrics['feeling']?.round()?.toString() ?? '-';

    double proteinValue = 0.0;
    double fatValue = 0.0;
    double carbsValue = 0.0;
    String allNutritionMenu = '';
    for (var r in widget.nutritionRecords) {
      proteinValue += r.subjectiveMetrics['protein']?.toDouble() ?? 0.0;
      fatValue += r.subjectiveMetrics['fat']?.toDouble() ?? 0.0;
      carbsValue += r.subjectiveMetrics['carbs']?.toDouble() ?? 0.0;
      if (r.details.isNotEmpty) {
        final content = r.details.first['content'] as String;
        if (allNutritionMenu.isNotEmpty) allNutritionMenu += '\n';
        allNutritionMenu += '【${r.subjectiveMetrics['meal_label'] ?? '未分類'}】\n$content';
      }
    }

    // 週間計画から今日の必要量を算出
    int targetP = 150, targetF = 70, targetC = 400; // デフォルト値
    if (widget.latestPlan != null) {
      final logicalToday = AppDateUtils.logicalToday();
      final weekdayStr = ['月','火','水','木','金','土','日'][logicalToday.weekday - 1];
      final todaysPlan = widget.latestPlan!.dailyPlans.where((p) => p.dateStr.contains(weekdayStr)).firstOrNull;
      if (todaysPlan != null) {
        targetP = todaysPlan.targetProtein > 0 ? todaysPlan.targetProtein : targetP;
        targetF = todaysPlan.targetFat > 0 ? todaysPlan.targetFat : targetF;
        targetC = todaysPlan.targetCarbs > 0 ? todaysPlan.targetCarbs : targetC;
      }
    }

    // カロリー計算 (P*4, F*9, C*4)
    final double totalCalories = (proteinValue * 4) + (fatValue * 9) + (carbsValue * 4);
    final double targetCalories = (targetP * 4.0) + (targetF * 9.0) + (targetC * 4.0);

    return Screenshot(
      controller: _screenshotController,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).colorScheme.primaryContainer),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), spreadRadius: 1, blurRadius: 4)],
        ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('今日のサマリー', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              IconButton(
                onPressed: _shareSummary,
                icon: const Icon(Icons.share, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                tooltip: 'SNSに共有',
              ),
            ],
          ),
          Divider(color: Theme.of(context).colorScheme.primaryContainer, height: 24),
          
          // 水中トレーニング
          _buildSummarySection(
            context,
            icon: Icons.pool,
            label: '水中トレーニング',
            color: AppColors.pool,
            children: [
              _DetailRow(label: '時間/詳細', value: poolDistanceLabel),
              _DetailRow(label: '内容', child: _ExpandableText(poolMenuLabel)),
              _DetailRow(label: '主観感覚', value: '$poolSubjective / 10'),
            ],
          ),
          const SizedBox(height: 16),
          
          // 陸上トレーニング
          _buildSummarySection(
            context,
            icon: Icons.fitness_center,
            label: '陸上トレーニング',
            color: AppColors.dryland,
            children: [
              _DetailRow(label: '内容', child: _ExpandableText(drylandMenuLabel)),
              _DetailRow(label: '疲労度', value: '$drylandSubjective / 10'),
            ],
          ),
          const SizedBox(height: 16),
          
          // 栄養状態
          _buildSummarySection(
            context,
            icon: Icons.restaurant,
            label: '栄養状態',
            color: AppColors.carbs,
            children: [
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
                          Expanded(child: _ExpandableText(r.details.isNotEmpty ? r.details.first['content'] : '記録あり')),
                          const SizedBox(width: 8),
                          Text('$kcal kcal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigoAccent.withOpacity(0.8))),
                        ],
                      ),
                    ],
                  )
                );
              }),
              const SizedBox(height: 12),
              _PfcStatusRow(
                label: 'タンパク質 (P)', 
                value: proteinValue, 
                maxValue: targetP.toDouble(), 
                color: AppColors.protein, 
                status: (targetP > 0 && proteinValue >= targetP) ? '達成' : '不足'
              ),
              _PfcStatusRow(
                label: '脂質 (F)', 
                value: fatValue, 
                maxValue: targetF.toDouble(), 
                color: AppColors.fat, 
                status: (targetF > 0 && fatValue >= targetF) ? '達成' : '不足'
              ),
              _PfcStatusRow(
                label: '炭水化物 (C)', 
                value: carbsValue, 
                maxValue: targetC.toDouble(), 
                color: AppColors.carbs, 
                status: (targetC > 0 && carbsValue >= targetC) ? '達成' : '不足'
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4.0),
                child: Divider(height: 1),
              ),
              _PfcStatusRow(
                label: 'エネルギー (kcal)', 
                value: totalCalories, 
                maxValue: targetCalories > 0 ? targetCalories : 2500, 
                color: Colors.purpleAccent, 
                status: (targetCalories > 0 && totalCalories >= targetCalories) ? '達成' : '不足'
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 睡眠時間
          _buildSummarySection(
            context,
            icon: Icons.bedtime,
            label: '睡眠時間',
            color: AppColors.sleep,
            children: [
              if (widget.sleepRecord != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailRow(
                      label: '実績',
                      value: '${(widget.sleepRecord!.durationMinutes / 60).floor()}時間 ${widget.sleepRecord!.durationMinutes % 60}分',
                    ),
                    Text(
                      '時間: ${() {
                        final start = DateTime.parse(widget.sleepRecord!.subjectiveMetrics['sleep_start'] as String);
                        final end = DateTime.parse(widget.sleepRecord!.subjectiveMetrics['sleep_end'] as String);
                        return '${start.month}/${start.day} ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} 〜 ${end.month}/${end.day} ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
                      }()}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('未入力', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    TextButton.icon(
                      onPressed: widget.onAddSleepPressed,
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('睡眠記録を入力', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppColors.sleep,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          if (_aiEvaluation != null)
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: AppColors.pool.withOpacity(0.1),
                border: Border.all(color: AppColors.pool.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wb_twilight, color: AppColors.pool, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _aiEvaluation!,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            )
        ],
      ),
    );
  }

  Widget _buildSummarySection(BuildContext context, {required IconData icon, required String label, required Color color, required List<Widget> children}) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final effectiveColor = isLight ? AppColors.getEffectiveColor(context, color) : color;
    
    return Container(
      decoration: BoxDecoration(
        color: effectiveColor.withOpacity(isLight ? 0.08 : 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: effectiveColor.withOpacity(isLight ? 0.3 : 0.15)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(icon: icon, label: label, color: effectiveColor),
          const SizedBox(height: 12),
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

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${date.year}年${date.month}月${date.day}日の記録', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ...dayRecords.where((r) => r.type != 'body_composition' && r.subjectiveMetrics['is_body_composition'] != true).map((r) {
                    final typeStr = r.type == 'pool' ? '🏊 水中トレーニング' : (r.type == 'dryland' ? '🏋 陸トレ' : '🍎 栄養');
                    
                    final detailsList = r.details as List<dynamic>? ?? [];
                    final previewText = detailsList.map((d) {
                      if (d['type'] == 'dryland_set') {
                        return '${d['exercise']} ${d['weight']}kg ${d['reps']}回';
                      }
                      return d['content']?.toString() ?? '';
                    }).join(' ');

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(typeStr),
                      subtitle: Text('${r.durationMinutes > 0 ? '${r.durationMinutes}分 ' : ''}$previewText'
                        .characters.take(50).toString() + (previewText.length > 50 ? '...' : '')),
                      trailing: const Icon(Icons.edit, size: 20, color: Colors.grey),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showEditRecordDialog(context, r);
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  void _showEditRecordDialog(BuildContext context, TrainingRecord record) {
    // detailsはList<Map>なので、テキストコンテントを抽出してStringにする
    final detailsList = record.details as List<dynamic>? ?? [];
    String initialText = '';
    
    final menuTextItem = detailsList.where((d) => d['type'] == 'menu_text').cast<Map<String, dynamic>?>().firstOrNull;
    if (menuTextItem != null) {
      initialText = menuTextItem['content']?.toString() ?? '';
    } else {
      // menu_text がない場合は構造化データから復元を試みる
      initialText = detailsList.map((d) {
        if (d['type'] == 'dryland_set') {
          return '${d['exercise']}\n${d['set_num']}セット目 ${d['weight']}kg ${d['reps']}回';
        }
        return d['content']?.toString() ?? '';
      }).join('\n');
    }
    
    final detailsController = TextEditingController(text: initialText);
    final durationController = TextEditingController(text: record.durationMinutes > 0 ? record.durationMinutes.toString() : '');
    final bool isNutrition = record.type == 'nutrition';
    
    // PFC用のコントローラー（栄養記録の場合のみ使用）
    final pController = TextEditingController(text: isNutrition ? (record.subjectiveMetrics['protein']?.toString() ?? '0') : '');
    final fController = TextEditingController(text: isNutrition ? (record.subjectiveMetrics['fat']?.toString() ?? '0') : '');
    final cController = TextEditingController(text: isNutrition ? (record.subjectiveMetrics['carbs']?.toString() ?? '0') : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('記録の編集 (${record.type == 'pool' ? '水中' : record.type == 'dryland' ? '陸トレ' : '栄養'})', style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isNutrition)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(
                  controller: durationController,
                  decoration: const InputDecoration(labelText: '時間 (分)'),
                  keyboardType: TextInputType.number,
                ),
              )
            else ...[
              const Text('栄養素 (g)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(child: TextField(controller: pController, decoration: const InputDecoration(labelText: 'P'), keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: fController, decoration: const InputDecoration(labelText: 'F'), keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: cController, decoration: const InputDecoration(labelText: 'C'), keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: detailsController,
              decoration: const InputDecoration(labelText: '内容・メニュー'),
              maxLines: null,
            ),
          ],
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
                )
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
            onPressed: () async {
              final newDetailsText = detailsController.text;
              final newDuration = int.tryParse(durationController.text);
              
              // 保存時は元の形式である List<Map<String, dynamic>> に戻す
              List<Map<String, dynamic>> newDetailsList = [];
              
              if (record.type == 'dryland') {
                // 陸上トレーニングの場合は再パースを行う
                final lines = newDetailsText.split('\n');
                String currentExercise = '';
                final weightRegex = RegExp(r'(\d+\.?\d*)\s*kg', caseSensitive: false);
                final repsRegex = RegExp(r'(\d+)\s*(?:回|reps)', caseSensitive: false);
                final setNumRegex = RegExp(r'(\d+)\s*(?:セット目|set)', caseSensitive: false);

                for (var line in lines) {
                  final trimmed = line.trim();
                  if (trimmed.isEmpty) continue;

                  final wMatch = weightRegex.firstMatch(trimmed);
                  final rMatch = repsRegex.firstMatch(trimmed);

                  if (wMatch != null) {
                    final weight = double.tryParse(wMatch.group(1) ?? '0') ?? 0.0;
                    final reps = int.tryParse(rMatch?.group(1) ?? '0') ?? 0;
                    final setNum = int.tryParse(setNumRegex.firstMatch(trimmed)?.group(1) ?? '1') ?? 1;

                    if (currentExercise.isNotEmpty) {
                      newDetailsList.add({
                        'type': 'dryland_set',
                        'exercise': currentExercise,
                        'weight': weight,
                        'reps': reps,
                        'set_num': setNum,
                      });
                    }
                  } else {
                    if (!trimmed.contains('続きを読む') && !trimmed.contains('閉じる')) {
                      currentExercise = trimmed
                          .replaceAll(RegExp(r'[\(（][^)）]*[\)）]'), '')
                          .trim();
                    }
                  }
                }
                newDetailsList.add({'type': 'menu_text', 'content': newDetailsText});
              } else {
                if (newDetailsText.isNotEmpty) {
                  newDetailsList.add({'type': 'menu_text', 'content': newDetailsText});
                }
              }
              
              await FirestoreService().updateTrainingRecord(record.id, {
                'details': newDetailsList,
                if (!isNutrition && newDuration != null) 'durationMinutes': newDuration,
                if (isNutrition) 'subjectiveMetrics': {
                  ...record.subjectiveMetrics,
                  'protein': double.tryParse(pController.text) ?? 0.0,
                  'fat': double.tryParse(fController.text) ?? 0.0,
                  'carbs': double.tryParse(cController.text) ?? 0.0,
                },
              });
              
              if (record.type == 'dryland') {
                await FirestoreService().generateInitialDrylandPbs();
              }
              
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('記録を更新しました。')));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestPlan = ref.watch(latestWeeklyPlanProvider).value;
    final days = _getDaysInMonth();
    final today = DateTime.now();
    final weekDays = ['日', '月', '火', '水', '木', '金', '土'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('アクティビティ履歴', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
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

                  // 目標値（曜日に基づく）
                  final weekdayStr = ['月','火','水','木','金','土','日'][date.weekday - 1];
                  int targetP = 150, targetF = 70, targetC = 400;
                  if (latestPlan != null) {
                    final dp = latestPlan.dailyPlans.where((p) => p.dateStr.contains(weekdayStr)).firstOrNull;
                    if (dp != null) {
                      targetP = dp.targetProtein > 0 ? dp.targetProtein : targetP;
                      targetF = dp.targetFat > 0 ? dp.targetFat : targetF;
                      targetC = dp.targetCarbs > 0 ? dp.targetCarbs : targetC;
                    }
                  }
                  pOk = dP >= targetP;
                  fOk = dF >= targetF;
                  cOk = dC >= targetC;
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
                            color: isCurrentMonth ? Theme.of(context).colorScheme.onSurface : Colors.grey.withOpacity(0.5),
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
      ),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  final String text;
  final int maxLines;
  const _ExpandableText(this.text, {this.maxLines = 3});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final lines = widget.text.split('\n').length;
    final isLongText = lines > widget.maxLines || widget.text.length > 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _isExpanded ? null : widget.maxLines,
          overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        if (isLongText)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
              child: Text(
                _isExpanded ? '閉じる' : '続きを読む...',
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
