import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/training_record.dart';
import '../../data/models/personal_best.dart';
import '../widgets/add_record_fab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late final Stream<List<TrainingRecord>> _recordsStream;
  late final Stream<List<PersonalBest>> _pbsStream;

  @override
  void initState() {
    super.initState();
    _recordsStream = _firestoreService.getTrainingRecordsStream(limit: 50);
    _pbsStream = _firestoreService.getPersonalBestsStream();
  }

  @override
  Widget build(BuildContext context) {
    // 栄養バランスチャート用モックデータ
    final List<double> currentNutritionData = [7.0, 5.0, 8.0, 6.0, 9.0];
    final List<double> targetNutritionData = [9.0, 7.0, 8.0, 9.0, 10.0];

    return Scaffold(
      appBar: AppBar(
        title: const Text('ホーム'),
      ),
      body: StreamBuilder<List<TrainingRecord>>(
        stream: _recordsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allRecords = snapshot.data ?? [];
          final now = DateTime.now();
          // 今日の記録のみを抽出
          final todayRecords = allRecords.where((record) {
            return record.date.year == now.year &&
                   record.date.month == now.month &&
                   record.date.day == now.day;
          }).toList();

          // 記録カテゴリ別のデータを集約
          final poolRecord = todayRecords.where((r) => r.type == 'pool').firstOrNull;
          final drylandRecord = todayRecords.where((r) => r.type == 'dryland').firstOrNull;
          final nutritionRecord = todayRecords.where((r) => r.type == 'nutrition').firstOrNull;
          
          return StreamBuilder<List<PersonalBest>>(
            stream: _pbsStream,
            builder: (context, pbSnapshot) {
              final allPbs = pbSnapshot.data ?? [];
              
              // 最新の自己ベストをカテゴリーと種目ごとに抽出
              final Map<String, PersonalBest> latestSwimPbs = {};
              final Map<String, PersonalBest> latestDrylandPbs = {};
              final Map<String, List<PersonalBest>> swimPbHistory = {};
              final Map<String, List<PersonalBest>> drylandPbHistory = {};
              
              for (var pb in allPbs.reversed) { // 古い順から処理して最新で上書き
                if (pb.category == 'swim') {
                  latestSwimPbs[pb.event] = pb;
                  swimPbHistory.putIfAbsent(pb.event, () => []).add(pb);
                } else if (pb.category == 'dryland') {
                  latestDrylandPbs[pb.event] = pb;
                  drylandPbHistory.putIfAbsent(pb.event, () => []).add(pb);
                }
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // 今日のサマリー
                _TodaySummaryCard(
                  poolRecord: poolRecord,
                  drylandRecord: drylandRecord,
                  nutritionRecords: todayRecords.where((r) => r.type == 'nutrition').toList(),
                ),
                const SizedBox(height: 24),

                // アクティビティカレンダーを追加
                _ActivityCalendar(records: allRecords),
                
                const SizedBox(height: 24),
                const Text('右上の「+」ボタンからトレーニング・食事・分析シートを記録できます',
                    style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 24),

            // 現在の自己ベスト
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('現在の自己ベスト', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle, color: Colors.teal), onPressed: () => _showAddPbDialog(context, 'swim')),
              ],
            ),
            const SizedBox(height: 16),
            if (latestSwimPbs.isEmpty) const Text('自己ベストがまだ登録されていません。', style: TextStyle(color: Colors.grey)),
            ...latestSwimPbs.values.toList().reversed.map((pb) => 
               _buildBestTimeCard(context, pb.event, pb.value.toStringAsFixed(2), '${pb.date.year}/${pb.date.month}/${pb.date.day}', swimPbHistory[pb.event]!)
            ),
            const SizedBox(height: 24),

            // ウエイトトレーニングの自己ベスト
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ウエイトトレーニング自己ベスト', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add_circle, color: Colors.orange), onPressed: () => _showAddPbDialog(context, 'dryland')),
              ],
            ),
            const SizedBox(height: 16),
            if (latestDrylandPbs.isEmpty) const Text('自己ベストがまだ登録されていません。', style: TextStyle(color: Colors.grey)),
            ...latestDrylandPbs.values.toList().reversed.map((pb) => 
               _buildWeightBestCard(context, pb.event, '${pb.value.toStringAsFixed(1)} kg', '${pb.date.year}/${pb.date.month}/${pb.date.day}', drylandPbHistory[pb.event]!)
            ),
            const SizedBox(height: 24),

            // 現在の体組成（自己ベスト下）
            const Text('現在の体組成', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionLabel(icon: Icons.monitor_weight, label: '直近の計測値 (2026/03/01)', color: Colors.purpleAccent),
                    const SizedBox(height: 12),
                    const _DetailRow(label: '体重', value: '69.3 kg'),
                    const _DetailRow(label: '骨格筋量', value: '35.5 kg'),
                    const _DetailRow(label: '体脂肪率', value: '11.2 %'),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 4),
                    Text('変化（先月比）', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                    const SizedBox(height: 4),
                    Row(children: const [
                      Icon(Icons.arrow_downward, color: Colors.greenAccent, size: 14),
                      SizedBox(width: 4),
                      Text('体重 -0.9 kg', style: TextStyle(fontSize: 13, color: Colors.greenAccent)),
                      SizedBox(width: 16),
                      Icon(Icons.arrow_upward, color: Colors.blueAccent, size: 14),
                      SizedBox(width: 4),
                      Text('骨格筋量 +1.3 kg', style: TextStyle(fontSize: 13, color: Colors.blueAccent)),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),            // レーダーチャート領域（栄養バランス）
            const Text(
              '最新の栄養バランス',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: RadarChart(
                RadarChartData(
                  radarTouchData: RadarTouchData(enabled: false),
                  titlePositionPercentageOffset: 0.2,
                  tickCount: 5,
                  ticksTextStyle: const TextStyle(color: Colors.transparent),
                  gridBorderData: BorderSide(color: Colors.grey.withOpacity(0.5), width: 1.5),
                  radarBorderData: const BorderSide(color: Colors.transparent),
                  getTitle: (index, angle) {
                    final titles = ['タンパク質(P)', '脂質(F)', '炭水化物(C)', 'リカバリー', '水分'];
                    return RadarChartTitle(text: titles[index], angle: 0);
                  },
                  dataSets: [
                    RadarDataSet(
                      fillColor: Colors.blue.withOpacity(0.4),
                      borderColor: Colors.blue,
                      entryRadius: 3,
                      dataEntries: targetNutritionData.map((e) => RadarEntry(value: e)).toList(),
                      borderWidth: 2,
                    ),
                    RadarDataSet(
                      fillColor: Colors.amber.withOpacity(0.4),
                      borderColor: Colors.amber,
                      entryRadius: 3,
                      dataEntries: currentNutritionData.map((e) => RadarEntry(value: e)).toList(),
                      borderWidth: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 凡例
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendItem(color: Colors.amber, text: '現在'),
                SizedBox(width: 24),
                _LegendItem(color: Colors.blue, text: '目標'),
              ],
            ),
            const SizedBox(height: 32),


            // 折れ線グラフ (体重・筋量推移モック)
            const Text(
              '体組成推移 (過去12ヶ月・月次)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '※ 実測日に記録。未記録の月は直前の値を引き継ぎます。',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minX: 1,
                  maxX: 12,
                  minY: 33,
                  maxY: 72,
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (val, meta) => Text(
                          val.toInt().toString(),
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (val, meta) {
                          const months = ['', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月', '1月', '2月', '3月'];
                          if (val.toInt() < 1 || val.toInt() > 12) return const SizedBox.shrink();
                          return Text(
                            months[val.toInt()],
                            style: TextStyle(
                              fontSize: 9,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24),
                    ),
                  ),
                  lineBarsData: [
                    // 体重 (月次実測値のみ)
                    LineChartBarData(
                      spots: const [
                        FlSpot(1, 71.2),
                        FlSpot(2, 70.8),
                        FlSpot(4, 70.5),
                        FlSpot(6, 70.1),
                        FlSpot(8, 69.8),
                        FlSpot(10, 69.5),
                        FlSpot(12, 69.3),
                      ],
                      isCurved: true,
                      color: Colors.teal,
                      barWidth: 3,
                      dotData: const FlDotData(show: false), // ドットを消して丸みをすっきり見せる
                    ),
                    // 骨格筋量 (月次実測値のみ)
                    LineChartBarData(
                      spots: const [
                        FlSpot(1, 34.2),
                        FlSpot(2, 34.5),
                        FlSpot(4, 34.8),
                        FlSpot(6, 35.1),
                        FlSpot(8, 35.4),
                        FlSpot(10, 35.5),
                        FlSpot(12, 35.5),
                      ],
                      isCurved: true,
                      color: Colors.orange,
                      barWidth: 3,
                      dotData: const FlDotData(show: false), // 同上
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 折れ線グラフの凡例
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendItem(color: Colors.teal, text: '体重 (kg)'),
                SizedBox(width: 24),
                _LegendItem(color: Colors.orange, text: '骨格筋量 (kg)'),
              ],
            ),
            const SizedBox(height: 80), // FABが被らないよう余白
          ],
        ),
      );
     }, // StreamBuilder.builder PB
    ); // PB StreamBuilder
   }, // StreamBuilder.builder Records
  ), // StreamBuilder Records
 ); // Scaffold
}

  void _showAddPbDialog(BuildContext context, String category) {
    final eventController = TextEditingController();
    final valueController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(category == 'swim' ? '水泳のPBを追加' : '陸トレのPBを追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: eventController, decoration: InputDecoration(labelText: category == 'swim' ? '種目 (例: 50m Fr)' : '種目 (例: ベンチプレス)')),
            TextField(controller: valueController, decoration: InputDecoration(labelText: category == 'swim' ? 'タイム (秒)' : '重量 (kg)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
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
                  event: eventController.text,
                  value: val,
                  date: DateTime.now(),
                );
                await _firestoreService.savePersonalBest(pb);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showPbHistoryDialog(BuildContext context, String event, List<PersonalBest> history, {required bool isTime}) {
    if (history.isEmpty) return;
    
    // Y軸設定のために最小・最大値を計算
    final values = history.map((e) => e.value).toList();
    final minY = values.reduce((a, b) => a < b ? a : b) * 0.95;
    final maxY = values.reduce((a, b) => a > b ? a : b) * 1.05;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('$event の推移', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: history.length == 1
                ? const Center(child: Text('データが1件のみのためグラフ化できません。', style: TextStyle(color: Colors.grey, fontSize: 13)))
                : LineChart(
                    LineChartData(
                      minY: minY,
                      maxY: maxY,
                      minX: 0,
                      maxX: (history.length - 1).toDouble(),
                      lineBarsData: [
                        LineChartBarData(
                          spots: history.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value)).toList(),
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
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= history.length) return const SizedBox.shrink();
                              final date = history[index].date;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text('${date.month}/${date.day}', style: const TextStyle(fontSize: 10)),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBestTimeCard(BuildContext context, String event, String time, String date, List<PersonalBest> history) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.timer, color: Colors.white)),
        title: Text(event, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(time, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal.shade300)),
        subtitle: Text(date),
        onTap: () => _showPbHistoryDialog(context, event, history, isTime: true),
      ),
    );
  }

  Widget _buildWeightBestCard(BuildContext context, String event, String weight, String date, List<PersonalBest> history) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.fitness_center, color: Colors.white)),
        title: Text(event, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(weight, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange.shade300)),
        subtitle: Text('達成日: $date'),
        onTap: () => _showPbHistoryDialog(context, event, history, isTime: false),
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
        Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
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
  final List<TrainingRecord> nutritionRecords;

  const _TodaySummaryCard({
    required this.poolRecord,
    required this.drylandRecord,
    required this.nutritionRecords,
  });

  @override
  State<_TodaySummaryCard> createState() => _TodaySummaryCardState();
}

class _TodaySummaryCardState extends State<_TodaySummaryCard> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isEditing = false;
  bool _isSaving = false;

  final TextEditingController _poolTimeController = TextEditingController();
  final TextEditingController _poolMenuController = TextEditingController();
  double _poolFeeling = 5.0;
  final TextEditingController _drylandMenuController = TextEditingController();
  double _drylandFeeling = 5.0;

  List<TextEditingController> _nutritionControllers = [];
  List<double> _nutritionProtein = [];
  List<double> _nutritionCarbs = [];
  List<String> _nutritionLabels = [];

  String? _aiEvaluation;
  bool _isAiLoading = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(_TodaySummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing) {
      _initControllers();
    }
  }

  void _initControllers() {
    _poolTimeController.text = (widget.poolRecord?.durationMinutes ?? 0).toString();
    _poolMenuController.text = (widget.poolRecord?.details.isNotEmpty == true) ? widget.poolRecord!.details.first['content'] : '';
    _poolFeeling = widget.poolRecord?.subjectiveMetrics['feeling']?.toDouble() ?? 5.0;
    
    _drylandMenuController.text = (widget.drylandRecord?.details.isNotEmpty == true) ? widget.drylandRecord!.details.first['content'] : '';
    _drylandFeeling = widget.drylandRecord?.subjectiveMetrics['feeling']?.toDouble() ?? 5.0;

    for (var c in _nutritionControllers) { c.dispose(); }
    _nutritionControllers = [];
    _nutritionProtein = [];
    _nutritionCarbs = [];
    _nutritionLabels = [];
    for (var r in widget.nutritionRecords) {
      _nutritionControllers.add(TextEditingController(text: r.details.isNotEmpty ? r.details.first['content'] : ''));
      _nutritionProtein.add(r.subjectiveMetrics['protein']?.toDouble() ?? 3.0);
      _nutritionCarbs.add(r.subjectiveMetrics['carbs']?.toDouble() ?? 3.0);
      _nutritionLabels.add(r.subjectiveMetrics['meal_label'] as String? ?? '未分類');
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      if (widget.poolRecord != null) {
        final currentDetails = List<Map<String, dynamic>>.from(widget.poolRecord!.details);
        if (currentDetails.isNotEmpty) {
           currentDetails[0]['content'] = _poolMenuController.text;
        } else if (_poolMenuController.text.isNotEmpty) {
           currentDetails.add({'type': 'menu_text', 'content': _poolMenuController.text});
        }
        final subjective = Map<String, dynamic>.from(widget.poolRecord!.subjectiveMetrics);
        subjective['feeling'] = _poolFeeling;

        await _firestoreService.updateTrainingRecord(widget.poolRecord!.id, {
          'durationMinutes': int.tryParse(_poolTimeController.text) ?? widget.poolRecord!.durationMinutes,
          'details': currentDetails,
          'subjectiveMetrics': subjective,
        });
      }
      if (widget.drylandRecord != null) {
        final currentDetails = List<Map<String, dynamic>>.from(widget.drylandRecord!.details);
        if (currentDetails.isNotEmpty) {
           currentDetails[0]['content'] = _drylandMenuController.text;
        } else if (_drylandMenuController.text.isNotEmpty) {
           currentDetails.add({'type': 'menu_text', 'content': _drylandMenuController.text});
        }
        final subjective = Map<String, dynamic>.from(widget.drylandRecord!.subjectiveMetrics);
        subjective['feeling'] = _drylandFeeling;

        await _firestoreService.updateTrainingRecord(widget.drylandRecord!.id, {
          'details': currentDetails,
          'subjectiveMetrics': subjective,
        });
      }
      
      for (int i = 0; i < widget.nutritionRecords.length; i++) {
        final r = widget.nutritionRecords[i];
        final currentDetails = List<Map<String, dynamic>>.from(r.details);
        if (currentDetails.isNotEmpty) {
           currentDetails[0]['content'] = _nutritionControllers[i].text;
        } else if (_nutritionControllers[i].text.isNotEmpty) {
           currentDetails.add({'type': 'memo', 'content': _nutritionControllers[i].text});
        }
        final subjective = Map<String, dynamic>.from(r.subjectiveMetrics);
        subjective['protein'] = _nutritionProtein[i];
        subjective['carbs'] = _nutritionCarbs[i];
        subjective['meal_label'] = _nutritionLabels[i];

        await _firestoreService.updateTrainingRecord(r.id, {
          'details': currentDetails,
          'subjectiveMetrics': subjective,
        });
      }

      setState(() => _isEditing = false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失敗: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _generateAiEvaluation(String nutritionMenu, double p, double f, double c) async {
    setState(() => _isAiLoading = true);
    try {
      final prompt = """
あなたは水泳のAIコーチです。以下の本日の食事内容とメニュー内容から、本日の栄養状態に対する1-2文の簡潔なフィードバックを行ってください。
【食事内容（合算）】
$nutritionMenu
【PFC自己評価（各15点満点）】
P: $p, F: $f, C: $c

評価は具体的に不足している栄養素を補うアドバイスか、よく摂れている点に対する称賛を含めてください。
""";
      final result = await GeminiService().generateContent(prompt);
      if (mounted) {
        setState(() => _aiEvaluation = result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI評価の取得に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _isAiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // derived variables
    final poolDistanceLabel = widget.poolRecord != null && widget.poolRecord!.durationMinutes > 0 
      ? '${widget.poolRecord!.durationMinutes} 分' : '未入力';
    final poolMenuLabel = widget.poolRecord != null && widget.poolRecord!.details.isNotEmpty 
      ? widget.poolRecord!.details.first['content'] ?? '記録あり' : '未入力';
    final poolSubjective = widget.poolRecord?.subjectiveMetrics['feeling']?.round()?.toString() ?? '-';

    final drylandMenuLabel = widget.drylandRecord != null && widget.drylandRecord!.details.isNotEmpty
      ? widget.drylandRecord!.details.first['content'] ?? '記録あり' : '未入力';
    final drylandSubjective = widget.drylandRecord?.subjectiveMetrics['feeling']?.round()?.toString() ?? '-';

    double proteinValue = 0.0;
    double carbsValue = 0.0;
    String allNutritionMenu = '';
    for (var r in widget.nutritionRecords) {
      proteinValue += r.subjectiveMetrics['protein']?.toDouble() ?? 0.0;
      carbsValue += r.subjectiveMetrics['carbs']?.toDouble() ?? 0.0;
      if (r.details.isNotEmpty) {
        final content = r.details.first['content'] as String;
        if (allNutritionMenu.isNotEmpty) allNutritionMenu += '\n';
        allNutritionMenu += '【${r.subjectiveMetrics['meal_label'] ?? '未分類'}】\n$content';
      }
    }

    return Container(
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
              if (!_isEditing)
                IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => setState(() => _isEditing = true))
              else
                _isSaving 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: _save, child: const Text('完了')),
            ],
          ),
          Divider(color: Theme.of(context).colorScheme.primaryContainer, height: 24),
          const _SectionLabel(icon: Icons.pool, label: '水中トレーニング', color: Colors.blueAccent),
          const SizedBox(height: 8),
          if (_isEditing) ...[
             Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: TextField(controller: _poolTimeController, decoration: const InputDecoration(labelText: '時間 (分)', isDense: true, border: OutlineInputBorder()), keyboardType: TextInputType.number),
            ),
             Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: TextField(controller: _poolMenuController, decoration: const InputDecoration(labelText: '内容', isDense: true, border: OutlineInputBorder()), maxLines: null),
            ),
             Padding(
              padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主観感覚 (1-10): ${_poolFeeling.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12)),
                  Slider(
                    value: _poolFeeling,
                    min: 1,
                    max: 10,
                    divisions: 18,
                    onChanged: (val) => setState(() => _poolFeeling = val),
                  ),
                ],
              ),
            ),
          ] else ...[
            _DetailRow(label: '時間/詳細', value: poolDistanceLabel),
            _DetailRow(label: '内容', child: _ExpandableText(poolMenuLabel)),
            _DetailRow(label: '主観感覚', value: '$poolSubjective / 10'),
          ],
          const SizedBox(height: 16),
          const _SectionLabel(icon: Icons.fitness_center, label: '陸上トレーニング', color: Colors.green),
          const SizedBox(height: 8),
          if (_isEditing) ...[
             Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: TextField(controller: _drylandMenuController, decoration: const InputDecoration(labelText: '内容', isDense: true, border: OutlineInputBorder()), maxLines: null),
            ),
             Padding(
              padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('疲労度 (1-10): ${_drylandFeeling.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12)),
                  Slider(
                    value: _drylandFeeling,
                    min: 1,
                    max: 10,
                    divisions: 18,
                    onChanged: (val) => setState(() => _drylandFeeling = val),
                  ),
                ],
              ),
            ),
          ] else ...[
            _DetailRow(label: '内容', child: _ExpandableText(drylandMenuLabel)),
            _DetailRow(label: '疲労度', value: '$drylandSubjective / 10'),
          ],
          const SizedBox(height: 16),
          const _SectionLabel(icon: Icons.restaurant, label: '栄養状態 (合算)', color: Colors.orangeAccent),
          const SizedBox(height: 8),
          
          if (_isEditing) ...[
            for (int i = 0; i < widget.nutritionRecords.length; i++) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
                child: DropdownButtonFormField<String>(
                  value: ['朝食', '昼食', '夕食', '間食', '未分類'].contains(_nutritionLabels[i]) ? _nutritionLabels[i] : '未分類',
                  decoration: const InputDecoration(labelText: '食事ラベル', isDense: true, border: OutlineInputBorder()),
                  items: ['朝食', '昼食', '夕食', '間食', '未分類'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (val) => setState(() => _nutritionLabels[i] = val!),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TextField(controller: _nutritionControllers[i], decoration: const InputDecoration(labelText: '内容', isDense: true, border: OutlineInputBorder()), maxLines: null),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('タンパク質: ${_nutritionProtein[i].toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)),
                          Slider(value: _nutritionProtein[i], min: 1, max: 5, divisions: 4, onChanged: (val) => setState(() => _nutritionProtein[i] = val)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('炭水化物: ${_nutritionCarbs[i].toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)),
                          Slider(value: _nutritionCarbs[i], min: 1, max: 5, divisions: 4, onChanged: (val) => setState(() => _nutritionCarbs[i] = val)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
            ],
            if (widget.nutritionRecords.isEmpty) const Text('今日の食事記録はありません。', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ] else ...[
            if (widget.nutritionRecords.isEmpty) 
               const _DetailRow(label: '食事内容', value: '未入力'),
            for (var r in widget.nutritionRecords)
               _DetailRow(
                 label: r.subjectiveMetrics['meal_label'] as String? ?? '未分類', 
                 child: _ExpandableText(r.details.isNotEmpty ? r.details.first['content'] : '記録あり')
               ),
          ],
          
          const SizedBox(height: 8),
          _PfcStatusRow(label: 'タンパク質 (P)', value: proteinValue, maxValue: 15, color: Colors.redAccent, status: proteinValue >= 12 ? '達成' : (proteinValue >= 8 ? '適正' : '不足')),
          const _PfcStatusRow(label: '脂質 (F)', value: 8, maxValue: 15, color: Colors.amberAccent, status: '適正'), // モック
          _PfcStatusRow(label: '炭水化物 (C)', value: carbsValue, maxValue: 15, color: Colors.redAccent, status: carbsValue >= 12 ? '達成' : (carbsValue >= 8 ? '適正' : '不足')),
          const SizedBox(height: 16),
          if (_aiEvaluation != null)
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                border: Border.all(color: Colors.blueAccent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wb_twilight, color: Colors.blueAccent, size: 20),
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
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.nutritionRecords.isEmpty || _isAiLoading 
                    ? null 
                    : () => _generateAiEvaluation(allNutritionMenu, proteinValue, 8.0, carbsValue),
                icon: _isAiLoading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.psychology, size: 18),
                label: const Text('AIから今日の栄養評価をもらう'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityCalendar extends StatefulWidget {
  final List<TrainingRecord> records;

  const _ActivityCalendar({required this.records});

  @override
  State<_ActivityCalendar> createState() => _ActivityCalendarState();
}

class _ActivityCalendarState extends State<_ActivityCalendar> {
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

  Widget _buildNutrientBadge(String label, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
    );
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
                  ...dayRecords.map((r) {
                    final typeStr = r.type == 'pool' ? '🏊 水中トレーニング' : (r.type == 'dryland' ? '🏋 陸トレ' : '🍎 栄養');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(typeStr),
                      subtitle: Text('${r.durationMinutes != null ? '${r.durationMinutes}分 ' : ''}${r.details}'),
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

  @override
  Widget build(BuildContext context) {
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
                
                final dayRecords = widget.records.where((r) => 
                  r.date.year == date.year && r.date.month == date.month && r.date.day == date.day
                ).toList();
                
                final hasPool = dayRecords.any((r) => r.type == 'pool');
                final hasDryland = dayRecords.any((r) => r.type == 'dryland');
                
                final nutritionRecord = dayRecords.where((r) => r.type == 'nutrition').firstOrNull;
                final proteinOk = (nutritionRecord?.subjectiveMetrics['protein']?.toDouble() ?? 0.0) >= 4;
                final carbsOk = (nutritionRecord?.subjectiveMetrics['carbs']?.toDouble() ?? 0.0) >= 4;

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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hasPool) Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
                            if (hasDryland) Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                          ],
                        ),
                        if (proteinOk || carbsOk) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (proteinOk) _buildNutrientBadge('P', Colors.redAccent),
                              if (carbsOk) _buildNutrientBadge('C', Colors.orange),
                            ],
                          ),
                        ],
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
