import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/services/firestore_service.dart';
import '../../data/models/training_insight.dart';
import '../widgets/add_record_fab.dart';
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
  int _selectedEventIndex = 0;
  int _selectedViewIndex = 0; // 0:相関, 1:体組成, 2:タイム予測, 3:ビジョン
  bool _showPredictedTime = false; // 予測タイムレンジ表示フラグ

  @override
  void initState() {
    super.initState();
    _insightStream = _firestoreService.getLatestInsightStream();
  }

  @override
  Widget build(BuildContext context) {
    // 画面幅に応じてPCダッシュボードレイアウトかスマホトグルかを判定
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return StreamBuilder<TrainingInsight?>(
      stream: _insightStream,
      builder: (context, snapshot) {
        final insightData = snapshot.data;
        
        return Scaffold(
          appBar: AppBar(
            title: const Text('インサイト（分析・洞察）'),
            actions: [
              if (isDesktop)
                TextButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('パーソナル・アナリシス・レポート(PDF)を出力しました')));
                  },
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                  label: const Text('レポート出力', style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
          body: Column(
            children: [
              // 1. エージェントの「思考の断片」表示領域
              _buildAgentThinkingLog(context, insightData),

              // 2. メインコンテンツ領域
              Expanded(
                child: isDesktop 
                    ? _buildDesktopDashboard(context, insightData) 
                    : _buildMobileToggleView(context, insightData),
              ),
            ],
          ),
        );
      }
    );
  }

  // --- エージェント思考ログ ---
  Widget _buildAgentThinkingLog(BuildContext context, TrainingInsight? insight) {
    final steps = insight?.agentThinkingSteps ?? [
      '> 過去3ヶ月の自由形データを走査中...',
      '> 筋量増加と乳酸閾値の相関を確認．',
      '> ユーザーの主観データ「キャッチが滑る」という記述が，高強度練習時に頻発していることを検出．',
      '> 結論：現在の技術的課題は筋疲労時のフォーム保持能力にあると推論．',
    ];

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Agent Thinking...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            steps.join('\n'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey, height: 1.4),
          ),
        ],
      ),
    );
  }

  // --- スマホ向けトグルビュー ---
  Widget _buildMobileToggleView(BuildContext context, TrainingInsight? insight) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ビュー切り替えトグル
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.scatter_plot, size: 18), label: Text('相関')),
              ButtonSegment(value: 1, icon: Icon(Icons.fitness_center, size: 18), label: Text('身体・栄養')),
              ButtonSegment(value: 2, icon: Icon(Icons.timer, size: 18), label: Text('タイム予測')),
              ButtonSegment(value: 3, icon: Icon(Icons.track_changes, size: 18), label: Text('ビジョン')),
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

          // 選択されたビューの表示
          if (_selectedViewIndex == 0) _buildCorrelationView(context, insight),
          if (_selectedViewIndex == 1) _buildBodyNutritionView(context, insight),
          if (_selectedViewIndex == 2) _buildPredictionView(context, insight),
          if (_selectedViewIndex == 3) _buildVisionAlignmentView(context, insight),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- PC向けダッシュボード ---
  Widget _buildDesktopDashboard(BuildContext context, TrainingInsight? insight) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildCorrelationView(context, insight)),
              const SizedBox(width: 24),
              Expanded(child: _buildBodyNutritionView(context, insight)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildPredictionView(context, insight)),
              const SizedBox(width: 24),
              Expanded(child: _buildVisionAlignmentView(context, insight)),
            ],
          ),
        ],
      ),
    );
  }

  // ============== A. 相関分析ビュー ==============
  Widget _buildCorrelationView(BuildContext context, TrainingInsight? insight) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('主観・客観 相関分析', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('感覚の良さと実際のストローク効率(DPS)のズレ', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: ScatterChart(
                ScatterChartData(
                  scatterSpots: [
                    ScatterSpot(3, 1.8, dotPainter: FlDotCirclePainter(color: Colors.blueAccent, radius: 4)),
                    ScatterSpot(4, 2.0, dotPainter: FlDotCirclePainter(color: Colors.blueAccent, radius: 4)),
                    ScatterSpot(5, 1.9, dotPainter: FlDotCirclePainter(color: Colors.blueAccent, radius: 4)),
                    ScatterSpot(6, 2.3, dotPainter: FlDotCirclePainter(color: Colors.blueAccent, radius: 4)),
                    ScatterSpot(7, 2.1, dotPainter: FlDotCirclePainter(color: Colors.blueAccent, radius: 4)),
                    ScatterSpot(8, 2.5, dotPainter: FlDotCirclePainter(color: Colors.orangeAccent, radius: 6)), // 注目点
                    ScatterSpot(9, 2.2, dotPainter: FlDotCirclePainter(color: Colors.blueAccent, radius: 4)),
                  ],
                  minX: 1, maxX: 10, minY: 1.5, maxY: 3.0,
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10))),
                      axisNameWidget: const Text('主観的感覚 (1-10)', style: TextStyle(fontSize: 12)),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 10))),
                      axisNameWidget: const Text('DPS (m/str)', style: TextStyle(fontSize: 12)),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: true, drawHorizontalLine: true),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.insights, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('【洞察】あなたが「感覚が8(とても良い)」と記録した時、DPSは急上昇(2.5)していますが、同時にタイムが低下する「空回り」現象が起きています。テンポが落ちすぎている可能性があります。',
                      style: TextStyle(fontSize: 12, height: 1.4)),
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
  Widget _buildBodyNutritionView(BuildContext context, TrainingInsight? insight) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('身体・栄養 インパクト', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('体組成の変化がパフォーマンス後半に与える影響', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            // 簡単なモック複合グラフ表現
            Container(
              height: 150,
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
              child: const Center(child: Text('[複合チャート: 筋量推移 vs 後半50mラップタイム]', style: TextStyle(color: Colors.grey))),
            ),
            const SizedBox(height: 16),
            const Text('重要な相関パターンの発見:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.arrow_upward, color: Colors.blue),
              title: Text('骨格筋量 +0.5kg の影響', style: TextStyle(fontSize: 14)),
              subtitle: Text('過去2ヶ月で筋量が増加した結果、100mの後半50mのラップ落ちが以前より 4.2% 改善されています。', style: TextStyle(fontSize: 12)),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.warning, color: Colors.orange),
              title: Text('炭水化物不足とスタミナ', style: TextStyle(fontSize: 14)),
              subtitle: Text('「炭水化物摂取(主観)が2以下」の翌日の高強度練習では、目標タイムからの乖離が平均+1.5秒大きくなります。', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // ============== C. 統計的タイム予測ビュー ==============
  Widget _buildPredictionView(BuildContext context, TrainingInsight? insight) {
    // AIデータがあればそれを使用、なければモックを使用
    final List<dynamic> predictionList = insight?.predictions ?? _mockPredictions;
    if (_selectedEventIndex >= predictionList.length) {
      _selectedEventIndex = 0;
    }
    final prediction = predictionList[_selectedEventIndex];
    final String pName = prediction is EventPrediction ? prediction.eventName : (prediction as _EventPrediction).name;
    final double pSuccessRate = prediction is EventPrediction ? prediction.successRate : (prediction as _EventPrediction).successRate;
    final String pPredictedTime = prediction is EventPrediction ? prediction.predictedTime : (prediction as _EventPrediction).predictedTime;
    final String pConfidenceInterval = prediction is EventPrediction ? prediction.confidenceInterval : (prediction as _EventPrediction).confidenceInterval;
    final String pSpecificInsight = prediction is EventPrediction ? prediction.specificInsight : (prediction as _EventPrediction).insight;
    final List<dynamic> pLaps = prediction is EventPrediction ? prediction.laps : (prediction as _EventPrediction).laps;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('統計的タイム予測', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('客観的データに基づく次戦での現実的な予測値', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            
            // 種目選択
            const Text('対象種目', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List.generate(predictionList.length, (index) {
                final item = predictionList[index];
                final String name = item is EventPrediction ? item.eventName : item.name;
                return ChoiceChip(
                  label: Text(name),
                  selected: _selectedEventIndex == index,
                  onSelected: (_) => setState(() => _selectedEventIndex = index),
                  selectedColor: Colors.teal,
                );
              }),
            ),
            const SizedBox(height: 24),

            // 目標達成確率とサマリー
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('目標達成確率', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('${(pSuccessRate * 100).toInt()}%',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                            color: pSuccessRate >= 0.6 ? Colors.green : Colors.orange)),
                  ],
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('予測タイム', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      if (_showPredictedTime)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('$pPredictedTime s', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                            Text('95% CI: $pConfidenceInterval', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _showPredictedTime = true),
                          icon: const Icon(Icons.visibility),
                          label: const Text('予測タイムを表示'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: pSuccessRate, 
              backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
              color: pSuccessRate >= 0.6 ? Colors.green : Colors.orange,
              minHeight: 8, borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 16),
            
            // 希望的観測の排除メッセージ
            if (pSuccessRate < 0.5)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), border: Border.all(color: Colors.red.withOpacity(0.5)), borderRadius: BorderRadius.circular(8)),
                child: const Text('【警告】現在の準備状況・データ推移では、自己ベストまたは設定目標の達成確率は50%を下回っています。抜本的なアプローチの修正（休息または泳ぎの修正）が必要です。',
                  style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold, height: 1.4)),
              ),

            // ラップ予測（デフォルトは閉じる＝現実直視用）
            ExpansionTile(
              title: const Text('詳細な予測ラップ・チャートを見る', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              initiallyExpanded: false,
              collapsedBackgroundColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              children: [
                const SizedBox(height: 16),
                if (_showPredictedTime)
                  Text('最も確率の高い予測タイム: $pPredictedTime s', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                DataTable(
                  headingRowColor: MaterialStateProperty.all(Colors.teal.withOpacity(0.1)),
                  columns: const [
                    DataColumn(label: Text('区間')),
                    DataColumn(label: Text('予想タイム')),
                    DataColumn(label: Text('Str数')),
                  ],
                  rows: pLaps.map((lap) {
                    final section = lap is LapPrediction ? lap.section : (lap as _LapPrediction).section;
                    final time = lap is LapPrediction ? lap.time : (lap as _LapPrediction).time;
                    final str = lap is LapPrediction ? lap.strokeCount : (lap as _LapPrediction).strokeCount;
                    return DataRow(cells: [
                      DataCell(Text(section)),
                      DataCell(Text(time, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold))),
                      DataCell(Text(str.toString())),
                    ]);
                  }).toList(),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.auto_graph, color: Theme.of(context).colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(pSpecificInsight, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, height: 1.5)),
                    ),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============== D. ビジョン・アライメントビュー ==============
  Widget _buildVisionAlignmentView(BuildContext context, TrainingInsight? insight) {
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
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text('設定ビジョン', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                   SizedBox(height: 4),
                   Text('「後半に強い、粘り勝つスプリンター」', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            const Text('「ラスト15mのキック」のスコアが著しく不足しています。今日の練習から、メインセットのラスト12.5mは壁まで必ずノーブレスト＆ハードキックを入れるルールを追加してください。',
              style: TextStyle(fontSize: 14, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
