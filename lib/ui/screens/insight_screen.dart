import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart' as ai;
import '../../data/models/training_insight.dart';
import '../../data/models/training_record.dart';
import '../../data/models/personal_best.dart';
import '../../data/models/goal_time.dart';
import '../../data/models/app_user.dart';
class _EventPrediction {
  final String name;
  final String predictedTime;
  final String confidenceInterval;
  final double successRate;
  final List<_LapPrediction> laps;
  final String insight;
  const _EventPrediction({required this.name, required this.predictedTime, required this.confidenceInterval, required this.successRate, required this.laps, required this.insight});
}

class _LapPrediction {
  final String section;
  final String time;
  final int strokeCount;
  const _LapPrediction({required this.section, required this.time, required this.strokeCount});
}

const _mockPredictions = [
  _EventPrediction(
    name: '50m 自由形', predictedTime: '22.95',
    confidenceInterval: '22.85s 〜 23.10s', successRate: 0.68,
    laps: [
      _LapPrediction(section: '0-25m', time: '10.85', strokeCount: 10),
      _LapPrediction(section: '25-50m', time: '12.10', strokeCount: 11),
    ],
    insight: '前半は突っ込みを抑え，ストローク効率を維持することで後半のタイムが安定します．',
  ),
  _EventPrediction(
    name: '100m 自由形', predictedTime: '50.84',
    confidenceInterval: '50.50s 〜 51.20s', successRate: 0.55,
    laps: [
      _LapPrediction(section: '0-25m', time: '11.10', strokeCount: 10),
      _LapPrediction(section: '25-50m', time: '12.50', strokeCount: 12),
      _LapPrediction(section: '50-75m', time: '13.40', strokeCount: 13),
      _LapPrediction(section: '75-100m', time: '13.84', strokeCount: 14),
    ],
    insight: '後半50m以降のラップ落ちが顕著です．タンパク質補充による超回復と持久力向上を優先してください．',
  ),
  _EventPrediction(
    name: '50m バタフライ', predictedTime: '24.65',
    confidenceInterval: '24.40s 〜 24.90s', successRate: 0.42,
    laps: [
      _LapPrediction(section: '0-25m', time: '11.40', strokeCount: 9),
      _LapPrediction(section: '25-50m', time: '13.25', strokeCount: 11),
    ],
    insight: '後半のストローク数増加が体幹持久力不足を示唆しています．ドライランドによる体幹強化が有効です．',
  ),
];

class InsightScreen extends StatefulWidget {
  const InsightScreen({super.key});
  @override
  State<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends State<InsightScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late final Stream<TrainingInsight?> _insightStream;
  late final Stream<List<TrainingRecord>> _recordsStream;
  late final Stream<List<PersonalBest>> _pbStream;
  late final Stream<AppUser?> _userStream;

  int _selectedEventIndex = 0;
  int _selectedViewIndex = 0; // 0:相関, 1:体組成, 2:タイム予測 (3:ビジョンは非表示)
  bool _isPredicting = false; // AI分析実行中フラグ

  Future<void> _runAiPrediction(
    BuildContext context, 
    List<TrainingRecord> records, 
    List<PersonalBest> pbs, 
    AppUser? user
  ) async {
    setState(() => _isPredicting = true);
    
    try {
      // 最近のデータを抽出 (直近20件または30日分程度)
      final recentRecords = records.take(20).toList();
      
      // 体組成データの抽出
      final bodyComp = recentRecords
          .where((r) => r.type == 'nutrition')
          .map((r) => {
            'date': r.date.toIso8601String(),
            'weight': r.subjectiveMetrics['weight'],
            'muscle_mass': r.subjectiveMetrics['muscle_mass'],
            'body_fat': r.subjectiveMetrics['body_fat'],
          })
          .toList();

      // 競泳PBの抽出
      final swimPbs = pbs
          .where((pb) => pb.category == 'swim')
          .map((pb) => {
            'event': pb.event,
            'value': pb.value,
            'date': pb.date.toIso8601String(),
          })
          .toList();

      // 目標タイムの取得
      final goalTimesSnapshot = await _firestoreService.getGoalTimesStream().first;
      final goalTimes = goalTimesSnapshot.map((gt) => {
        'event': gt.event,
        'value': gt.value,
      }).toList();

      // 練習内容の要约
      final trainingSummary = recentRecords
          .where((r) => r.type == 'pool' || r.type == 'dryland')
          .map((r) => {
            'type': r.type,
            'date': r.date.toIso8601String(),
            'duration': r.durationMinutes,
            'feeling': r.subjectiveMetrics['feeling'],
            'content': r.details.isNotEmpty ? r.details.first['content'] : '',
          })
          .toList();

      final prompt = """
あなたは超一流の競泳データアナリスト兼コーチです。以下のユーザーデータを基に、統計的かつ生理学的な見地から次戦のタイムを予測し、JSON形式で回答してください。

【ユーザーデータ】
- 選手としてのビジョン: ${user?.vision ?? '未設定'}
- 最新の自己ベスト: $swimPbs
- ユーザーが設定した目標タイム: $goalTimes
- 直近の体組成推移: $bodyComp
- 最近の練習内容と主観評価: $trainingSummary

【回答形式 (JSON)】
以下の構造を持つJSONオブジェクトのみを出力してください。Markdownのコードブロックなどは含めないでください。
{
  "overallInsight": "全体の分析（現在のコンディションや成長傾向）",
  "agentThinkingSteps": ["分析ステップ1", "分析ステップ2", "分析ステップ3", "分析ステップ4"],
  "predictions": [
    {
      "eventName": "種目名 (自己ベストにある種目名を正確に使用)",
      "predictedTime": "予想タイム (秒)",
      "confidenceInterval": "信頼区間 (例: 22.8s 〜 23.1s)",
      "successRate": 0.0〜1.0 (ユーザーが設定した「目標タイム」を達成できる確率。目標タイムが未設定の種目の場合は、自己ベスト更新の確率。),
      "specificInsight": "その種目に対する具体的なアドバイス（1-2文）",
      "laps": [
        { "section": "区間 (例: 0-25m)", "time": "区間タイム", "strokeCount": 推定ストローク数 }
      ]
    }
  ]
}

※ 注意: 予測タイムは、筋量、練習内容（強度や距離）、主観的な疲労度、過去のPBからの期間などを考慮してリアリティのある数値を算出してください。
""";

      final modelId = user?.baseProfile['aiModel'] as String? ?? ai.GeminiService.modelFlash;
      final response = await ai.GeminiService().generateContent(
        prompt, 
        modelId: modelId,
        responseMimeType: 'application/json',
      );

      if (response == null || response.isEmpty) throw Exception('AIからの応答が空でした。');

      // JSONパース
      final Map<String, dynamic> data = jsonDecode(response);
      
      final insight = TrainingInsight(
        id: '', // Firestore保存時に自動生成
        createdAt: DateTime.now(),
        overallInsight: data['overallInsight'] ?? '',
        agentThinkingSteps: List<String>.from(data['agentThinkingSteps'] ?? []),
        predictions: (data['predictions'] as List<dynamic>?)?.map((p) => EventPrediction(
          eventName: p['eventName'] ?? '',
          predictedTime: p['predictedTime']?.toString() ?? '',
          confidenceInterval: p['confidenceInterval'] ?? '',
          successRate: (p['successRate'] as num?)?.toDouble() ?? 0.0,
          specificInsight: p['specificInsight'] ?? '',
          laps: (p['laps'] as List<dynamic>?)?.map((l) => LapPrediction(
            section: l['section'] ?? '',
            time: l['time']?.toString() ?? '',
            strokeCount: (l['strokeCount'] as num?)?.toInt() ?? 0,
          )).toList() ?? [],
        )).toList() ?? [],
      );

      // 保存
      await _firestoreService.saveTrainingInsight(insight);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AIタイム予測が完了しました。')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分析に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isPredicting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _insightStream = _firestoreService.getLatestInsightStream();
    _recordsStream = _firestoreService.getTrainingRecordsStream(limit: 50);
    _pbStream = _firestoreService.getPersonalBestsStream();
    _userStream = _firestoreService.getUserProfileStream();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return StreamBuilder<TrainingInsight?>(
      stream: _insightStream,
      builder: (context, insightSnapshot) {
        return StreamBuilder<List<TrainingRecord>>(
          stream: _recordsStream,
          builder: (context, recordsSnapshot) {
            return StreamBuilder<List<PersonalBest>>(
              stream: _pbStream,
              builder: (context, pbsSnapshot) {
                return StreamBuilder<AppUser?>(
                  stream: _userStream,
                  builder: (context, userSnapshot) {
                    final insightData = insightSnapshot.data;
                    final recordsData = recordsSnapshot.data ?? [];
                    final pbsData = pbsSnapshot.data ?? [];
                    final userData = userSnapshot.data;

                    if (insightSnapshot.connectionState == ConnectionState.waiting && insightData == null) {
                      return const Scaffold(body: Center(child: CircularProgressIndicator()));
                    }

                    return Scaffold(
                      appBar: AppBar(
                        title: const Text('インサイト（分析・洞察）'),
                        actions: [
                          if (isDesktop)
                            TextButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('レポートを出力しました')));
                              },
                              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                              label: const Text('レポート出力', style: TextStyle(color: Colors.white)),
                            ),
                        ],
                      ),
                      body: Column(
                        children: [
                          _buildAgentThinkingLog(context, insightData),
                          Expanded(
                            child: isDesktop 
                                ? _buildDesktopDashboard(context, insightData, recordsData, pbsData, userData) 
                                : _buildMobileToggleView(context, insightData, recordsData, pbsData, userData),
                          ),
                        ],
                      ),
                    );
                  }
                );
              }
            );
          }
        );
      }
    );
  }

  // --- エージェント思考ログ ---
  Widget _buildAgentThinkingLog(BuildContext context, TrainingInsight? insight) {
    final steps = insight?.agentThinkingSteps ?? [];
    if (steps.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      child: ExpansionTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(Icons.psychology, size: 18, color: Theme.of(context).colorScheme.primary),
        title: Text(
          'AI Thinking Log (${steps.length} steps)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),
                const SizedBox(height: 8),
                Text(
                  steps.join('\n'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.grey,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- スマホ向けトグルビュー ---
  Widget _buildMobileToggleView(BuildContext context, TrainingInsight? insight, List<TrainingRecord> records, List<PersonalBest> pbs, AppUser? user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.scatter_plot, size: 18), label: Text('相関')),
              ButtonSegment(value: 1, icon: Icon(Icons.fitness_center, size: 18), label: Text('身体・栄養')),
              ButtonSegment(value: 2, icon: Icon(Icons.timer, size: 18), label: Text('タイム予測')),
              // ButtonSegment(value: 3, icon: Icon(Icons.track_changes, size: 18), label: Text('ビジョン')),
            ],
            selected: {_selectedViewIndex},
            onSelectionChanged: (Set<int> newSelection) {
              setState(() => _selectedViewIndex = newSelection.first);
            },
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),

          if (_selectedViewIndex == 0) _buildCorrelationView(context, insight, records),
          if (_selectedViewIndex == 1) _buildBodyNutritionView(context, insight, records),
          if (_selectedViewIndex == 2) _buildPredictionView(context, insight, records, pbs, user),
          // if (_selectedViewIndex == 3) _buildVisionAlignmentView(context, insight, user),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- PC向けダッシュボード ---
  Widget _buildDesktopDashboard(BuildContext context, TrainingInsight? insight, List<TrainingRecord> records, List<PersonalBest> pbs, AppUser? user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCorrelationView(context, insight, records)),
              const SizedBox(width: 24),
              Expanded(child: _buildBodyNutritionView(context, insight, records)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildPredictionView(context, insight, records, pbs, user)),
              // const SizedBox(width: 24),
              // Expanded(child: _buildVisionAlignmentView(context, insight, user)),
            ],
          ),
        ],
      ),
    );
  }

  // ============== A. 相関分析ビュー ==============
  Widget _buildCorrelationView(BuildContext context, TrainingInsight? insight, List<TrainingRecord> records) {
    // 実際に過去の主観評価と練習時間（分）の相関をプロット
    final scatterSpots = records.where((r) => r.subjectiveMetrics.containsKey('feeling')).map((r) {
      final feeling = (r.subjectiveMetrics['feeling'] as num?)?.toDouble() ?? 5.0;
      final duration = r.durationMinutes.toDouble();
      return ScatterSpot(feeling, duration, dotPainter: FlDotCirclePainter(color: Colors.blueAccent, radius: 4));
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('主観・客観 相関分析', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('感覚の良さと実際の練習ボリューム(分)の相関', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: scatterSpots.isEmpty 
                ? const Center(child: Text('データが不足しています', style: TextStyle(color: Colors.grey)))
                : ScatterChart(
                    ScatterChartData(
                      scatterSpots: scatterSpots,
                      minX: 1, maxX: 10, minY: 0, maxY: 180,
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10))),
                          axisNameWidget: const Text('主観的感覚 (1-10)', style: TextStyle(fontSize: 12)),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10))),
                          axisNameWidget: const Text('時間 (分)', style: TextStyle(fontSize: 12)),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: true),
                    ),
                  ),
            ),
            const SizedBox(height: 16),
            if (insight?.overallInsight != null && insight!.overallInsight.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.insights, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(insight.overallInsight, style: const TextStyle(fontSize: 12, height: 1.4)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============== B. 身体組成・栄養インパクトビュー ==============
  Widget _buildBodyNutritionView(BuildContext context, TrainingInsight? insight, List<TrainingRecord> records) {
    // 栄養記録のメモから体重と骨格筋量を抽出してグラフ化
    final List<FlSpot> weightSpots = [];
    final List<FlSpot> muscleSpots = [];
    final weightRegex = RegExp(r'体重:\s*([0-9.]+)\s*kg');
    final muscleRegex = RegExp(r'骨格筋量:\s*([0-9.]+)\s*kg');

    final nutritionRecords = records.where((r) => r.type == 'nutrition').toList().reversed.toList();
    for (int i = 0; i < nutritionRecords.length; i++) {
      final record = nutritionRecords[i];
      for (final detail in record.details) {
        if (detail['type'] == 'memo') {
          final content = detail['content'] as String;
          final wMatch = weightRegex.firstMatch(content);
          final mMatch = muscleRegex.firstMatch(content);
          if (wMatch != null) {
            weightSpots.add(FlSpot(i.toDouble(), double.parse(wMatch.group(1)!)));
          }
          if (mMatch != null) {
            muscleSpots.add(FlSpot(i.toDouble(), double.parse(mMatch.group(1)!)));
          }
        }
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('身体・栄養 インパクト', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('体組成の変化と栄養主観評価の推移', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: weightSpots.isEmpty && muscleSpots.isEmpty
                ? const Center(child: Text('体組成計のデータがありません', style: TextStyle(color: Colors.grey)))
                : LineChart(
                    LineChartData(
                      lineBarsData: [
                        LineChartBarData(
                          spots: weightSpots,
                          isCurved: true, color: Colors.blue, barWidth: 3, dotData: const FlDotData(show: true),
                        ),
                        LineChartBarData(
                          spots: muscleSpots,
                          isCurved: true, color: Colors.green, barWidth: 3, dotData: const FlDotData(show: true),
                        ),
                      ],
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
                    ),
                  ),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, color: Colors.blue, size: 10), SizedBox(width: 4), Text('体重(kg)', style: TextStyle(fontSize: 10)),
                SizedBox(width: 12),
                Icon(Icons.circle, color: Colors.green, size: 10), SizedBox(width: 4), Text('骨格筋量(kg)', style: TextStyle(fontSize: 10)),
              ],
            ),
            const SizedBox(height: 16),
            const Text('重要な相関パターンの発見:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.fitness_center, color: Colors.blue),
              title: Text('データ分析中...', style: TextStyle(fontSize: 14)),
              subtitle: Text('十分なデータが集まると、筋量とパフォーマンスの相関がここに表示されます。', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // ============== C. 統計的タイム予測ビュー ==============
  Widget _buildPredictionView(
    BuildContext context, 
    TrainingInsight? insight, 
    List<TrainingRecord> records, 
    List<PersonalBest> pbs, 
    AppUser? user
  ) {
    // 1. PBから競泳種目のみを抽出
    final Set<String> eventNames = pbs
        .where((pb) => pb.category == 'swim')
        .map((pb) => pb.event)
        .toSet();
    
    if (insight?.predictions != null) {
      // 予測データがある場合も、その種目が競泳カテゴリに属するか、あるいは既存のPBに含まれるか確認が必要だが、
      // ここではユーザーの要望通り「競泳種目のみ」にするため、PBにある種目名を優先し、
      // 予測データはそれらに紐づくもののみ表示する。
      final swimPredictionEvents = insight!.predictions
          .map((p) => p.eventName)
          .where((name) => eventNames.contains(name));
      eventNames.addAll(swimPredictionEvents);
    }
    final sortedEvents = eventNames.toList()..sort();

    if (_selectedEventIndex >= sortedEvents.length) {
      _selectedEventIndex = 0;
    }

    final String selectedEvent = sortedEvents.isNotEmpty ? sortedEvents[_selectedEventIndex] : '種目未登録';
    
    // 2. 選択された種目のPB履歴を抽出（グラフ用）
    final historySpots = pbs
        .where((pb) => pb.event == selectedEvent && pb.category == 'swim')
        .toList()
        .reversed
        .map((pb) => FlSpot(pb.date.millisecondsSinceEpoch.toDouble(), pb.value))
        .toList();

    // 3. AI予測データのマッチング
    final prediction = insight?.predictions.firstWhere(
      (p) => p.eventName == selectedEvent,
      orElse: () => EventPrediction(
        eventName: selectedEvent,
        predictedTime: '---',
        confidenceInterval: '---',
        successRate: 0.0,
        laps: [],
        specificInsight: historySpots.length < 2 
            ? '現在1件のベストタイムから成長曲線をシミュレーションしています。練習データが蓄積されるほど精度が向上します。'
            : 'この種目のAI分析データはまだ生成されていません。',
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('統計的タイム推移と予測', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('自己ベストの推移とAIによる次戦予測', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            
            // 種目選択
            const Text('対象種目', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            sortedEvents.isEmpty 
              ? const Text('自己ベストがまだ登録されていません', style: TextStyle(fontSize: 12, color: Colors.grey))
              : Wrap(
                  spacing: 8,
                  children: List.generate(sortedEvents.length, (index) {
                    return ChoiceChip(
                      label: Text(sortedEvents[index]),
                      selected: _selectedEventIndex == index,
                      onSelected: (_) => setState(() => _selectedEventIndex = index),
                      selectedColor: Colors.teal,
                    );
                  }),
                ),
            const SizedBox(height: 24),

            // 推移グラフ
            if (historySpots.isNotEmpty)
              SizedBox(
                height: 120,
                child: LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: historySpots,
                        isCurved: false, color: Colors.teal, barWidth: 2, dotData: const FlDotData(show: true),
                      ),
                    ],
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // 予測セクション
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('目標達成確率', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('${((prediction?.successRate ?? 0) * 100).toInt()}%',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                            color: (prediction?.successRate ?? 0) >= 0.6 ? Colors.green : Colors.orange)),
                  ],
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('AI予測タイム', style: TextStyle(fontSize: 12, color: Colors.grey)),
                       if (_isPredicting)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (prediction?.predictedTime != null && 
                               prediction!.predictedTime.isNotEmpty && 
                               prediction.predictedTime != '---')
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${prediction.predictedTime} s', 
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)
                            ),
                            Text(
                              '95% CI: ${prediction.confidenceInterval}', 
                              style: const TextStyle(fontSize: 11, color: Colors.grey)
                            ),
                          ],
                        )
                      else
                        const Text('予測データなし', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // 予測実行ボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isPredicting ? null : () => _runAiPrediction(context, records, pbs, user),
                icon: _isPredicting 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome),
                label: Text(_isPredicting ? '分析中...' : '最新データでAIタイム予測を実行'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                '※ ボタンを押すとAIが最新の記録を分析します（数十秒かかります）',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: prediction?.successRate ?? 0.0, 
              backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
              color: (prediction?.successRate ?? 0) >= 0.6 ? Colors.green : Colors.orange,
              minHeight: 8, borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 16),

            if (prediction != null && prediction.laps.isNotEmpty)
              ExpansionTile(
                title: const Text('詳細な予測ラップを見る', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                children: [
                  DataTable(
                    columns: const [
                      DataColumn(label: Text('区間')),
                      DataColumn(label: Text('予想タイム')),
                      DataColumn(label: Text('Str数')),
                    ],
                    rows: prediction.laps.map((lap) => DataRow(cells: [
                      DataCell(Text(lap.section)),
                      DataCell(Text(lap.time, style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(lap.strokeCount.toString())),
                    ])).toList(),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(prediction.specificInsight, style: const TextStyle(fontSize: 13, height: 1.5)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ============== D. ビジョン・アライメントビュー ==============
  Widget _buildVisionAlignmentView(BuildContext context, TrainingInsight? insight, AppUser? user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ビジョン・アライメント', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('目標とする「なりたい選手像」と現在地のギャップ', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   const Text('設定ビジョン', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                   const SizedBox(height: 4),
                   Text(user?.vision != null && user!.vision.isNotEmpty ? '「${user.vision}」' : 'ビジョン未設定', 
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ]
              )
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 220,
              child: RadarChart(
                RadarChartData(
                  radarTouchData: RadarTouchData(enabled: false),
                  titlePositionPercentageOffset: 0.15,
                  tickCount: 4,
                  ticksTextStyle: const TextStyle(color: Colors.transparent),
                  gridBorderData: BorderSide(color: Colors.grey.withOpacity(0.5), width: 1),
                  radarBorderData: const BorderSide(color: Colors.transparent),
                  getTitle: (index, angle) {
                    final titles = ['後半のStr維持力', 'ラスト15mのキック', '乳酸耐性(タイム低下率)', '前半の無駄のなさ'];
                    return RadarChartTitle(text: titles[index], angle: 0);
                  },
                  dataSets: [
                    RadarDataSet(
                      fillColor: Colors.blue.withOpacity(0.2), borderColor: Colors.blue,
                      entryRadius: 2, borderWidth: 1.5,
                      dataEntries: [5, 5, 5, 5].map((e) => RadarEntry(value: e.toDouble())).toList(),
                    ),
                    RadarDataSet(
                      fillColor: Colors.green.withOpacity(0.4), borderColor: Colors.green,
                      entryRadius: 3, borderWidth: 2,
                      dataEntries: [3, 2, 4, 4].map((e) => RadarEntry(value: e.toDouble())).toList(),
                    ),
                  ],
                )
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, color: Colors.green, size: 12), SizedBox(width: 4), Text('現在地', style: TextStyle(fontSize: 12)),
                SizedBox(width: 16),
                Icon(Icons.circle, color: Colors.blue, size: 12), SizedBox(width: 4), Text('ビジョン要求レベル', style: TextStyle(fontSize: 12)),
              ],
            ),
            const Divider(height: 32),
            const Text('今すぐ改善すべき1つのアクション:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
            const SizedBox(height: 8),
            const Text('分析データに基づき、あなたのビジョン達成に必要な最短ルートのアクションをエージェントがここに提案します。',
              style: TextStyle(fontSize: 14, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
