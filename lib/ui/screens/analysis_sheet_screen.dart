import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';

class AnalysisSheetScreen extends StatefulWidget {
  const AnalysisSheetScreen({super.key});

  @override
  State<AnalysisSheetScreen> createState() => _AnalysisSheetScreenState();
}

class _AnalysisSheetScreenState extends State<AnalysisSheetScreen> {
  String _selectedDistance = '100m';
  String _selectedStyle = '自由形';

  final List<String> _distances = ['50m', '100m', '200m', '400m', '800m', '1500m'];
  final List<String> _styles = ['自由形', '背泳ぎ', '平泳ぎ', 'バタフライ', '個人メドレー'];

  // ダミーデータ（本来は距離に応じて動的生成）
  final List<Map<String, dynamic>> _lapData = [
    {'lap': '0-50m', 'time': '24.50', 'strokeCount': 19, 'memo': '浮き上がりスムーズ'},
    {'lap': '50-100m', 'time': '26.80', 'strokeCount': 22, 'memo': '後半バテた'},
  ];

  // 距離と種目に応じたラップラベルの生成ロジック
  void _generateLaps() {
    // 簡易的な生成ロジック
    int distance = int.tryParse(_selectedDistance.replaceAll('m', '')) ?? 100;
    int lapCount = distance ~/ 50;
    if (lapCount == 0) lapCount = 1;

    List<Map<String, dynamic>> newLaps = [];
    List<String> imStyles = ['Fly', 'Ba', 'Br', 'Fr'];

    for (int i = 0; i < lapCount; i++) {
      String baseLabel = '${i * 50}-${(i + 1) * 50}m';
      String styleLabel = '';
      
      if (_selectedStyle == '個人メドレー') {
        // 4分割のどれに当たるかを判定
        int styleIndex = (i / (lapCount / 4)).floor();
        if (styleIndex > 3) styleIndex = 3;
        styleLabel = ' (${imStyles[styleIndex]})';
      }

      newLaps.add({
        'lap': '$baseLabel$styleLabel',
        'time': '',
        'strokeCount': '',
        'memo': ''
      });
    }

    setState(() {
      _lapData.clear();
      _lapData.addAll(newLaps);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text( // Removed const from Text widget
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
            // パラメータ選択領域
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('距離: '),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: _selectedDistance,
                          items: _distances.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedDistance = val);
                              _generateLaps(); // 変更時に再生成
                            }
                          },
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('種目: '),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: _selectedStyle,
                          items: _styles.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedStyle = val);
                              _generateLaps(); // 変更時に再生成
                            }
                          },
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('AI分析へのデータ送信をシミュレートしました')),
                        );
                      },
                      icon: const Icon(Icons.analytics),
                      label: const Text('AI分析を実行'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // グリッド（データテーブル）領域
            const Text(
              'ラップタイム & パラメーター詳細',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('区間')),
                    DataColumn(label: Text('タイム (s)')),
                    DataColumn(label: Text('ストローク数')),
                    DataColumn(label: Text('感覚メモ')),
                  ],
                  rows: _lapData.map((data) {
                    return DataRow(
                      cells: [
                        DataCell(Text(data['lap'].toString())),
                        DataCell(
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              initialValue: data['time'].toString(),
                              decoration: const InputDecoration(isDense: true),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 60,
                            child: TextFormField(
                              initialValue: data['strokeCount'].toString(),
                              decoration: const InputDecoration(isDense: true),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 200,
                            child: TextFormField(
                              initialValue: data['memo'].toString(),
                              decoration: const InputDecoration(isDense: true),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _lapData.add({
                    'lap': '追加ラップ',
                    'time': '',
                    'strokeCount': '',
                    'memo': ''
                  });
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('行を追加'),
            )
          ],
        ),
      ),
    );
  }
}

