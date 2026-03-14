import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart' as ai;
import '../../data/models/training_insight.dart';
import '../../data/models/training_record.dart';
import '../../data/models/personal_best.dart';
import '../../data/models/app_user.dart';
import '../../utils/date_utils.dart';
import '../../data/providers/providers.dart';

class InsightScreen extends ConsumerStatefulWidget {
  const InsightScreen({super.key});
  @override
  ConsumerState<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends ConsumerState<InsightScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  int _selectedEventIndex = 0;
  int _selectedViewIndex = 0; // 0:種目推移, 1:身体・栄養, 2:タイム予測
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
      
      // 体組成データの抽出 (body_compositionタイプから)
      final bodyComp = recentRecords
          .where((r) => r.type == 'body_composition')
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
      final goalTimesSnapshot = ref.read(goalTimesProvider).value ?? [];
      // 2. 選択された種目のPB履歴を抽出（グラフ用）
      // Removed unused local variable 'goalTimes'

      // 履歴から目標設定日(gt.date)の時点でのタイム（またはそれに最も近い過去の最速値）を抽出
      final goalBaselineTimes = goalTimesSnapshot.map((gt) {
        // 目標設定日以前の記録から、その種目の最小値（ベスト）を探す
        final pastPbAtGoalSetting = pbs
            .where((pb) => pb.event == gt.event && (pb.date.isBefore(gt.date) || pb.date.isAtSameMomentAs(gt.date)))
            .toList();
        
        double? baselineValue;
        if (pastPbAtGoalSetting.isNotEmpty) {
          pastPbAtGoalSetting.sort((a, b) => a.value.compareTo(b.value));
          baselineValue = pastPbAtGoalSetting.first.value;
        }

        return {
          'event': gt.event,
          'goalValue': gt.value,
          'goalSetDate': gt.date.toIso8601String(),
          'baselineValueAtGoalSet': baselineValue ?? '記録なし',
        };
      }).toList();

      // 栄養記録の抽出
      final nutritionSummary = recentRecords
          .where((r) => r.type == 'nutrition')
          .map((r) {
            final detail = r.details.firstWhere((d) => d['type'] == 'memo', orElse: () => {'content': ''});
            return {
              'date': r.date.toIso8601String(),
              'meal': r.subjectiveMetrics['meal_label'] ?? '不明',
              'content': detail['content'],
              'metrics': r.subjectiveMetrics,
            };
          })
          .toList();

      // 練習内容の要約
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

      final systemInstruction = user != null 
          ? await ai.GeminiService().getCoachSystemInstruction(user, supplementaryContext: await ai.GeminiService().insightGuidelineInstruction)
          : "あなたは世界トップレベルの競泳データアナリスト兼コーチングスペシャリストです。";

      final promptTemplate = await ai.GeminiService().insightPredictionInstruction;
      final prompt = promptTemplate
          .replaceAll('{swimPbs}', swimPbs.toString())
          .replaceAll('{goalBaselineTimes}', goalBaselineTimes.toString())
          .replaceAll('{bodyComp}', bodyComp.toString())
          .replaceAll('{nutritionSummary}', nutritionSummary.toString())
          .replaceAll('{trainingSummary}', trainingSummary.toString());

      final modelId = user?.baseProfile['aiModel'] as String? ?? ai.GeminiService.modelForInsight;
      final response = await ai.GeminiService().generateContent(
        prompt, 
        systemInstruction: systemInstruction,
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
          predictedTime: p['predictedTimeSeconds']?.toString() ?? '',
          confidenceInterval: p['predictedRange'] ?? '',
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
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    // 各データを Provider から取得
    final insightAsync = ref.watch(latestInsightProvider);
    final userAsync = ref.watch(userProfileProvider);

    // インサイトデータとユーザーデータの両方が読み込み中の場合
    if (insightAsync.isLoading || userAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final insightData = insightAsync.value;
    final userData = userAsync.value;
    final recordsData = ref.watch(trainingRecordsProvider).value ?? [];
    final pbsData = ref.watch(personalBestsProvider).value ?? [];

    return Scaffold(
                      appBar: AppBar(
                        title: const Text('インサイト'),
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
                          const Divider(height: 1),
                          Expanded(
                            child: isDesktop 
                                ? _buildDesktopDashboard(context, insightData, recordsData, pbsData, userData) 
                                : _buildMobileToggleView(context, insightData, recordsData, pbsData, userData),
                          ),
                        ],
                      ),
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
              ButtonSegment(value: 0, icon: Icon(Icons.trending_up, size: 18), label: Text('種目推移')),
              ButtonSegment(value: 1, icon: Icon(Icons.fitness_center, size: 18), label: Text('身体・栄養')),
              ButtonSegment(value: 2, icon: Icon(Icons.timer, size: 18), label: Text('タイム予測')),
            ],
            selected: <int>{_selectedViewIndex},
            onSelectionChanged: (Set<int> newSelection) {
              setState(() => _selectedViewIndex = newSelection.first);
            },
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),

          if (_selectedViewIndex == 0) _buildPbTrendView(context, pbs, insight, records, user),
          if (_selectedViewIndex == 1) _buildBodyNutritionView(context, insight, records),
          if (_selectedViewIndex == 2) _buildPredictionView(context, insight, records, pbs, user),
          
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
    );
  }

  // --- PC向けダッシュボード ---
  Widget _buildDesktopDashboard(BuildContext context, TrainingInsight? insight, List<TrainingRecord> records, List<PersonalBest> pbs, AppUser? user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          _buildPbTrendView(context, pbs, insight, records, user),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildBodyNutritionView(context, insight, records)),
              const SizedBox(width: 24),
              Expanded(child: _buildPredictionView(context, insight, records, pbs, user)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBodyNutritionView(BuildContext context, TrainingInsight? insight, List<TrainingRecord> records) {
    // 身体組成データを抽出
    final bodyCompRecords = records.where((r) => r.type == 'body_composition').toList()..sort((a, b) => a.date.compareTo(b.date));
    
    final List<FlSpot> weightSpots = [];
    final List<FlSpot> muscleSpots = [];
    final List<FlSpot> fatSpots = [];
    
    for (int i = 0; i < bodyCompRecords.length; i++) {
      final r = bodyCompRecords[i];
      final w = r.subjectiveMetrics['weight']?.toDouble();
      final m = r.subjectiveMetrics['muscle_mass']?.toDouble();
      final f = r.subjectiveMetrics['body_fat']?.toDouble();
      if (w != null) weightSpots.add(FlSpot(i.toDouble(), w));
      if (m != null) muscleSpots.add(FlSpot(i.toDouble(), m));
      if (f != null) fatSpots.add(FlSpot(i.toDouble(), f));
    }

    // 睡眠データを抽出・ソートしてグラフ化
    final List<FlSpot> sleepSpots = [];
    final sleepRecords = records.where((r) => r.type == 'sleep').toList()..sort((a, b) => a.date.compareTo(b.date));
    for (int i = 0; i < sleepRecords.length; i++) {
       sleepSpots.add(FlSpot(i.toDouble(), sleepRecords[i].durationMinutes / 60.0)); // 時間単位
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('身体・栄養・睡眠 インパクト', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('体組成の変化と睡眠時間の推移', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: weightSpots.isEmpty && muscleSpots.isEmpty && fatSpots.isEmpty && sleepSpots.isEmpty
                ? const Center(child: Text('データがありません', style: TextStyle(color: Colors.grey)))
                : Builder(
                  builder: (context) {
                    // kg系（体重・筋量）の共通レンジ：左軸
                    final kgValues = (weightSpots + muscleSpots).map((s) => s.y).toList();
                    final double minKg = kgValues.isEmpty ? 45 : kgValues.reduce((a, b) => a < b ? a : b) - 2;
                    final double maxKg = kgValues.isEmpty ? 85 : kgValues.reduce((a, b) => a > b ? a : b) + 2;

                    // 数値系（体脂肪率・睡眠時間）の共通レンジ：右軸
                    final rightValues = (fatSpots + sleepSpots).map((s) => s.y).toList();
                    final double minRight = rightValues.isEmpty ? 0 : rightValues.reduce((a, b) => a < b ? a : b) - 1;
                    final double maxRight = rightValues.isEmpty ? 25 : rightValues.reduce((a, b) => a > b ? a : b) + 1;

                    // 体脂肪率をkgレンジ（描画用メインレンジ）に正規化
                    final normalizedFatSpots = fatSpots.map((s) {
                      double normalizedY;
                      if (maxRight == minRight) {
                        normalizedY = (maxKg + minKg) / 2;
                      } else {
                        normalizedY = (s.y - minRight) / (maxRight - minRight) * (maxKg - minKg) + minKg;
                      }
                      return FlSpot(s.x, normalizedY);
                    }).toList();

                    // 睡眠時間をkgレンジ（描画用メインレンジ）に正規化
                    final normalizedSleepSpots = sleepSpots.map((s) {
                      double normalizedY;
                      if (maxRight == minRight) {
                        normalizedY = (maxKg + minKg) / 2;
                      } else {
                        normalizedY = (s.y - minRight) / (maxRight - minRight) * (maxKg - minKg) + minKg;
                      }
                      return FlSpot(s.x, normalizedY);
                    }).toList();

                    return LineChart(
                      LineChartData(
                        minY: minKg,
                        maxY: maxKg,
                        clipData: const FlClipData.all(),
                        lineBarsData: [
                          if (weightSpots.isNotEmpty)
                            LineChartBarData(
                              spots: weightSpots, isCurved: true, color: Theme.of(context).brightness == Brightness.light ? Colors.blue.shade800 : Colors.blue, barWidth: 3, dotData: const FlDotData(show: true),
                            ),
                          if (muscleSpots.isNotEmpty)
                            LineChartBarData(
                              spots: muscleSpots, isCurved: true, color: Theme.of(context).brightness == Brightness.light ? Colors.green.shade800 : Colors.green, barWidth: 3, dotData: const FlDotData(show: true),
                            ),
                          if (normalizedFatSpots.isNotEmpty)
                            LineChartBarData(
                              spots: normalizedFatSpots, isCurved: true, color: Theme.of(context).brightness == Brightness.light ? Colors.orange.shade900 : Colors.orange, barWidth: 2, dotData: const FlDotData(show: true),
                              dashArray: [5, 5],
                            ),
                          if (normalizedSleepSpots.isNotEmpty)
                            LineChartBarData(
                              spots: normalizedSleepSpots, isCurved: true, color: Theme.of(context).brightness == Brightness.light ? Colors.pink.shade800 : Colors.pinkAccent, barWidth: 3, dotData: const FlDotData(show: true),
                            ),
                        ],
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              interval: 1,
                              getTitlesWidget: (v, m) => const SizedBox.shrink(), // X軸ラベルは一旦非表示（データが多いと被るため）
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 35,
                              getTitlesWidget: (v, m) => Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 9, color: Colors.blue)),
                            ),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 35,
                              getTitlesWidget: (v, m) {
                                if (maxKg == minKg) return const SizedBox.shrink();
                                // kgレンジから右軸レンジに逆換算
                                final rightVal = (v - minKg) / (maxKg - minKg) * (maxRight - minRight) + minRight;
                                return Text(rightVal.toStringAsFixed(1), style: const TextStyle(fontSize: 9, color: Colors.grey));
                              },
                            ),
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (_) => Colors.blueGrey,
                            getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                              String unit = ' kg';
                              double displayValue = s.y;
                              if (s.bar.color == Colors.orange) {
                                unit = ' %';
                                if (maxKg != minKg) {
                                  displayValue = (s.y - minKg) / (maxKg - minKg) * (maxRight - minRight) + minRight;
                                } else {
                                  displayValue = minRight;
                                }
                              } else if (s.bar.color == Colors.pinkAccent) {
                                unit = ' h';
                                if (maxKg != minKg) {
                                  displayValue = (s.y - minKg) / (maxKg - minKg) * (maxRight - minRight) + minRight;
                                } else {
                                  displayValue = minRight;
                                }
                              }
                              return LineTooltipItem('${displayValue.toStringAsFixed(1)}$unit', const TextStyle(color: Colors.white, fontSize: 10));
                            }).toList(),
                          ),
                        ),
                      ),
                      duration: Duration.zero,
                    );
                  },
                ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _LegendItem(color: Theme.of(context).brightness == Brightness.light ? Colors.blue.shade800 : Colors.blue, label: '体重 (kg)'),
                _LegendItem(color: Theme.of(context).brightness == Brightness.light ? Colors.green.shade800 : Colors.green, label: '筋肉量 (kg)'),
                _LegendItem(color: Theme.of(context).brightness == Brightness.light ? Colors.orange.shade900 : Colors.orange, label: '体脂肪率 (%)'),
                _LegendItem(color: Theme.of(context).brightness == Brightness.light ? Colors.pink.shade800 : Colors.pinkAccent, label: '睡眠時間 (h)'),
              ],
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
          children: [
            // 種目選択（スクロール可能）
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: sortedEvents.isEmpty 
                  ? [const Text('自己ベストを登録すると予測が表示されます', style: TextStyle(fontSize: 12, color: Colors.grey))]
                  : List.generate(sortedEvents.length, (index) {
                      final isSelected = _selectedEventIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(sortedEvents[index], style: TextStyle(fontSize: 12, color: isSelected ? Colors.black : Colors.white70)),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedEventIndex = index),
                          selectedColor: Colors.tealAccent,
                          backgroundColor: Colors.white10,
                        ),
                      );
                    }),
              ),
            ),
            const SizedBox(height: 16),
            
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
                              _formatSeconds(double.tryParse(prediction.predictedTime) ?? 0), 
                              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)
                            ),
                            Text(
                              prediction.confidenceInterval.isNotEmpty 
                                ? prediction.confidenceInterval 
                                : '範囲推定中...', 
                              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)
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


  // ============== A. 種目別自己ベスト推移ビュー ==============
  Widget _buildPbTrendView(
    BuildContext context, 
    List<PersonalBest> pbs, 
    TrainingInsight? insight,
    List<TrainingRecord> records,
    AppUser? user
  ) {
    final Set<String> eventNames = pbs
        .where((pb) => pb.category == 'swim')
        .map((pb) => pb.event)
        .toSet();
    
    if (insight?.predictions != null) {
      final swimPredictionEvents = insight!.predictions
          .map((p) => p.eventName)
          .where((name) => eventNames.contains(name) || name.contains('m'));
      eventNames.addAll(swimPredictionEvents);
    }
    final sortedEvents = eventNames.toList()..sort();

    if (_selectedEventIndex >= sortedEvents.length) {
      _selectedEventIndex = 0;
    }

    final String selectedEvent = sortedEvents.isNotEmpty ? sortedEvents[_selectedEventIndex] : '種目未登録';
    
    // 指定種目の履歴データを取得し、日付順（昇順）にソート
    final historyList = pbs
        .where((pb) => pb.event == selectedEvent && pb.category == 'swim')
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    
    final historySpots = historyList
        .map((pb) => FlSpot(pb.date.millisecondsSinceEpoch.toDouble(), -pb.value))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.trending_up, color: Colors.tealAccent, size: 20),
                SizedBox(width: 8),
                Text('種目別自己ベスト推移', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            
            // 種目選択（スクロール可能）
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: sortedEvents.isEmpty 
                  ? [const Text('自己ベストを登録すると推移が表示されます', style: TextStyle(fontSize: 12, color: Colors.grey))]
                  : List.generate(sortedEvents.length, (index) {
                      final isSelected = _selectedEventIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(sortedEvents[index], style: TextStyle(fontSize: 12, color: isSelected ? Colors.black : Colors.white70)),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedEventIndex = index),
                          selectedColor: Colors.tealAccent,
                          backgroundColor: Colors.white10,
                        ),
                      );
                    }),
              ),
            ),
            const SizedBox(height: 16),
  
            // 折れ線グラフ
            if (historySpots.isNotEmpty)
              Builder(
                builder: (context) {
                  final xValues = historySpots.map((s) => s.x).toList();
                  final minX = xValues.length == 1 ? xValues.first - 86400000 : xValues.reduce((a, b) => a < b ? a : b);
                  final maxX = xValues.length == 1 ? xValues.first + 86400000 : xValues.reduce((a, b) => a > b ? a : b);

                  return SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: LineChart(
                      LineChartData(
                        minX: minX,
                        maxX: maxX,
                        clipData: const FlClipData.all(),
                        lineBarsData: [
                          LineChartBarData(
                            spots: historySpots,
                            isCurved: true,
                            color: Colors.tealAccent,
                            barWidth: 3,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.tealAccent.withOpacity(0.1),
                            ),
                          ),
                        ],
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              interval: (maxX - minX) / 4 > 86400000 ? (maxX - minX) / 4 : 86400000,
                              getTitlesWidget: (value, meta) {
                                // 記録が存在する日のみを表示する
                                final isDataPoint = historySpots.any((s) => (s.x - value).abs() < 3600000); // 1時間以内の誤差を許容
                                if (!isDataPoint) return const SizedBox.shrink();

                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    AppDateUtils.getChartLabel(value),
                                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) => Text(_formatSeconds(value.abs()), style: const TextStyle(fontSize: 9, color: Colors.grey)),
                            ),
                          ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (spot) => Colors.blueGrey.withOpacity(0.8),
                        getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(_formatSeconds(s.y.abs()), const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))).toList(),
                      ),
                    ),
                  ),
                  duration: Duration.zero,
                ),
              );
            },
          )
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Text('この種目のデータがまだありません', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ),
              ),
          ],
        ),
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
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, color: color, size: 10),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}
