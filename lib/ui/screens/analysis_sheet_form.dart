import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/firestore_service.dart';
import '../../data/models/training_record.dart';
import '../../utils/event_utils.dart';

/// 自己分析シート入力フォーム（モーダル表示用）
class AnalysisSheetForm extends StatefulWidget {
  const AnalysisSheetForm({super.key});

  @override
  State<AnalysisSheetForm> createState() => _AnalysisSheetFormState();
}

class _AnalysisSheetFormState extends State<AnalysisSheetForm> {
  final FirestoreService _firestoreService = FirestoreService();
  DateTime _selectedDate = DateTime.now();
  String _event = '100m 自由形';
  String _course = '短水路 (25m)';
  int _totalDistance = 100;
  bool _isOcrLoading = false;
  bool _isSaving = false;

  final List<_LapEntry> _laps = [];

  final List<String> _eventOptions = [
    '50m 自由形',
    '100m 自由形',
    '200m 自由形',
    '400m 自由形',
    '800m 自由形',
    '1500m 自由形',
    '50m 背泳ぎ',
    '100m 背泳ぎ',
    '200m 背泳ぎ',
    '50m 平泳ぎ',
    '100m 平泳ぎ',
    '200m 平泳ぎ',
    '50m バタフライ',
    '100m バタフライ',
    '200m バタフライ',
    '200m 個人メドレー',
    '400m 個人メドレー',
  ];

  @override
  void initState() {
    super.initState();
    _generateLaps();
  }

  void _runOcrMock() async {
    setState(() => _isOcrLoading = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    //モック: 100m自由形短水路のデータを自動入力
    setState(() {
      _isOcrLoading = false;
      _event = '100m 自由形';
      _course = '短水路 (25m)';
      _totalDistance = 100;
      _generateLaps();
      if (_laps.length >= 4) {
        _laps[0].timeController.text = '10.85';
        _laps[1].timeController.text = '12.10';
        _laps[2].timeController.text = '13.20';
        _laps[3].timeController.text = '13.84';
        _laps[0].strokeController.text = '10';
        _laps[1].strokeController.text = '12';
        _laps[2].strokeController.text = '13';
        _laps[3].strokeController.text = '14';
        _laps[0].underwaterController.text = '5.5';
        _laps[1].underwaterController.text = '4.8';
        _laps[2].underwaterController.text = '4.5';
        _laps[3].underwaterController.text = '4.2';
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('タイマー・スコアボードの読み取りが完了しました')),
    );
  }

  void _generateLaps() {
    _laps.clear();
    // 距離に応じてデフォルトのラップ区間を自動生成
    int lapSize = _course.contains('25m') ? 25 : 50;
    int lapCount = (_totalDistance / lapSize).round();
    int start = 0;
    for (int i = 0; i < lapCount; i++) {
      int end = start + lapSize;
      _laps.add(_LapEntry(section: '$start-${end}m'));
      start = end;
    }
  }

  void _addCustomLap() async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int? dist;
        return AlertDialog(
          title: const Text('ラップ区間を追加'),
          content: TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '区間距離 (m)', border: OutlineInputBorder()),
            onChanged: (v) => dist = int.tryParse(v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(ctx, dist), child: const Text('追加')),
          ],
        );
      },
    );
    if (result != null && result > 0) {
      setState(() {
        final lastEnd = _laps.isNotEmpty
            ? int.tryParse(_laps.last.section.split('-').last.replaceAll('m', '')) ?? 0
            : 0;
        _laps.add(_LapEntry(section: '$lastEnd-${lastEnd + result}m'));
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自己分析シート'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () async {
              setState(() => _isSaving = true);
              try {
                final record = TrainingRecord(
                  id: '',
                  date: _selectedDate,
                  type: 'analysis',
                  durationMinutes: 0,
                  details: [
                    {
                      'type': 'event_info', 
                      'event': EventUtils.normalizeEventName(_event), 
                      'course': _course, 
                      'distance': _totalDistance
                    },
                    {'type': 'laps', 'data': _laps.map((l) => {
                      'section': l.section,
                      'time': l.timeController.text,
                      'stroke': l.strokeController.text,
                      'underwater': l.underwaterController.text,
                      'memo': l.memoController.text,
                    }).toList()}
                  ],
                  subjectiveMetrics: {},
                );
                await _firestoreService.addTrainingRecord(record);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('分析シートを保存しました')),
                  );
                  context.pop();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('保存に失敗しました: $e')),
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
              : const Text('保存', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // ---- 基本情報 ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('基本情報', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  // 日付
                  ListTile(
                    leading: const Icon(Icons.calendar_today, color: Colors.tealAccent),
                    title: const Text('記録日'),
                    trailing: Text(
                      '${_selectedDate.year}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
                    ),
                    onTap: () => _selectDate(context),
                  ),
                  const Divider(),
                  // 種目
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: DropdownButtonFormField<String>(
                      value: _event,
                      decoration: const InputDecoration(
                        labelText: '種目',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.pool),
                      ),
                      items: _eventOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() {
                          _event = val;
                          // 種目名から距離を自動抽出
                          final match = RegExp(r'(\d+)m').firstMatch(val);
                          if (match != null) {
                            _totalDistance = int.tryParse(match.group(1) ?? '100') ?? 100;
                            _generateLaps();
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 水路
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: '短水路 (25m)', label: Text('短水路 (25m)')),
                      ButtonSegment(value: '長水路 (50m)', label: Text('長水路 (50m)')),
                    ],
                    selected: {_course},
                    onSelectionChanged: (s) => setState(() {
                      _course = s.first;
                      _generateLaps();
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 写真から取り込み
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('タイムペーパー・スコアボード写真から取り込み', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          'レース結果記録票やスコアボードの写真からラップデータを自動入力します',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _isOcrLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton.icon(
                          onPressed: _runOcrMock,
                          icon: const Icon(Icons.document_scanner),
                          label: const Text('写真から取り込む'),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ---- ラップ入力テーブル ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ラップ詳細', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      TextButton.icon(
                        onPressed: _addCustomLap,
                        icon: const Icon(Icons.add),
                        label: const Text('ラップ追加'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // ヘッダー
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                    child: const Row(
                      children: [
                        SizedBox(width: 70, child: Text('区間', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 8),
                        Expanded(child: Text('タイム', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 8),
                        Expanded(child: Text('Str数', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 8),
                        Expanded(child: Text('水中動作(m)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        SizedBox(width: 8),
                        Expanded(child: Text('備考', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // 各ラップ行
                  ...List.generate(_laps.length, (i) => _buildLapRow(i)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLapRow(int index) {
    final lap = _laps[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 70,
            child: Text(lap.section, style: const TextStyle(fontSize: 12, color: Colors.tealAccent)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: lap.timeController,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: '0:00.00',
                hintStyle: TextStyle(fontSize: 11),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: lap.strokeController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: '10',
                hintStyle: TextStyle(fontSize: 11),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: lap.underwaterController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: '5.0',
                hintStyle: TextStyle(fontSize: 11),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: lap.memoController,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: '備考',
                hintStyle: TextStyle(fontSize: 11),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LapEntry {
  final String section;
  final TextEditingController timeController = TextEditingController();
  final TextEditingController strokeController = TextEditingController();
  final TextEditingController underwaterController = TextEditingController();
  final TextEditingController memoController = TextEditingController();

  _LapEntry({required this.section});
}
