import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  final TextEditingController _totalTimeController = TextEditingController();

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

  Future<void> _runOcr() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => _isOcrLoading = true);
    try {
      final bytes = await image.readAsBytes();
      final extension = image.path.split('.').last.toLowerCase();
      final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';

      final result = await _firestoreService.analyzeAnalysisSheetWithGemini(bytes, mimeType);
      
      if (result != null) {
        setState(() {
          final rawEvent = EventUtils.normalizeEventName(result['event']?.toString() ?? '');
          if (_eventOptions.contains(rawEvent)) {
            _event = rawEvent;
          } else if (rawEvent.isNotEmpty) {
            // 見つからない場合はアラートを表示し、選択は維持する
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('種目識別の通知'),
                  content: Text('写真から「$rawEvent」を識別しましたが、登録済みの種目リストにありません。手動で選択してください。'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                  ],
                ),
              );
            }
          }

          if (result['course'] != null) {
            final rawCourse = result['course']?.toString() ?? '';
            if (rawCourse.contains('25') || rawCourse.contains('短')) {
              _course = '短水路 (25m)';
            } else if (rawCourse.contains('50') || rawCourse.contains('長')) {
              _course = '長水路 (50m)';
            }
          }
          
          if (result['laps'] != null) {
            _laps.clear();
            for (var lapData in result['laps']) {
              final lap = _LapEntry(section: lapData['section'] ?? '');
              lap.timeController.text = lapData['time']?.toString() ?? '';
              lap.strokeController.text = lapData['stroke']?.toString() ?? '';
              lap.underwaterController.text = lapData['underwater']?.toString() ?? '';
              _laps.add(lap);
            }
            // 累計タイムを再計算
            for (int i = 0; i < _laps.length; i++) {
              double prevCum = i > 0 ? _parseTime(_laps[i-1].cumulativeController.text) : 0;
              double currentLap = _parseTime(_laps[i].timeController.text);
              _laps[i].cumulativeController.text = _formatTime(prevCum + currentLap);
            }
            if (_laps.isNotEmpty) {
              _totalTimeController.text = _laps.last.cumulativeController.text;
            }
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('解析が完了しました')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  double _parseTime(String text) {
    if (text.isEmpty) return 0;
    final parts = text.split(':');
    if (parts.length == 2) {
      final min = double.tryParse(parts[0]) ?? 0;
      final sec = double.tryParse(parts[1]) ?? 0;
      return min * 60 + sec;
    }
    return double.tryParse(text) ?? 0;
  }

  String _formatTime(double seconds) {
    if (seconds <= 0) return '';
    final min = (seconds / 60).floor();
    final sec = seconds % 60;
    if (min > 0) {
      return '$min:${sec.toStringAsFixed(2).padLeft(5, '0')}';
    }
    return sec.toStringAsFixed(2);
  }

  void _calculateTimesFromLap(int index) {
    double cumulative = 0;
    if (index > 0) {
      cumulative = _parseTime(_laps[index - 1].cumulativeController.text);
    }
    double lap = _parseTime(_laps[index].timeController.text);
    _laps[index].cumulativeController.text = _formatTime(cumulative + lap);

    // 以降の全てのラップを再計算
    for (int i = index + 1; i < _laps.length; i++) {
      double prevCum = _parseTime(_laps[i - 1].cumulativeController.text);
      double currentLap = _parseTime(_laps[i].timeController.text);
      _laps[i].cumulativeController.text = _formatTime(prevCum + currentLap);
    }
    
    // トータルタイムも更新
    if (_laps.isNotEmpty) {
      _totalTimeController.text = _laps.last.cumulativeController.text;
    }
  }

  void _calculateTimesFromCumulative(int index) {
    double prevCum = 0;
    if (index > 0) {
      prevCum = _parseTime(_laps[index - 1].cumulativeController.text);
    }
    double currentCum = _parseTime(_laps[index].cumulativeController.text);
    _laps[index].timeController.text = _formatTime(currentCum - prevCum);

    // 以降の全てのラップを再計算
    for (int i = index + 1; i < _laps.length; i++) {
      double pc = _parseTime(_laps[i - 1].cumulativeController.text);
      double lap = _parseTime(_laps[i].timeController.text);
      _laps[i].cumulativeController.text = _formatTime(pc + lap);
    }

    if (_laps.isNotEmpty) {
      _totalTimeController.text = _laps.last.cumulativeController.text;
    }
  }

  void _generateLaps() {
    _laps.clear();
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
    final startController = TextEditingController();
    final endController = TextEditingController();

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('ラップ区間を分割・追加'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('既存の区間を分割して新しいラップを挿入します。', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(
                    controller: startController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '開始 (m)', border: OutlineInputBorder()),
                  )),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-')),
                  Expanded(child: TextField(
                    controller: endController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '終了 (m)', border: OutlineInputBorder()),
                  )),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            FilledButton(
              onPressed: () {
                final s = int.tryParse(startController.text);
                final e = int.tryParse(endController.text);
                if (s != null && e != null && e > s) {
                  Navigator.pop(ctx, {'start': s, 'end': e});
                }
              }, 
              child: const Text('分割・挿入'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      final s = result['start']!;
      final e = result['end']!;

      setState(() {
        // 既存のリストから、新しい区間が含まれるべき位置を探す
        int insertIndex = -1;
        for (int i = 0; i < _laps.length; i++) {
          final parts = _laps[i].sectionController.text.replaceAll('m', '').split('-');
          if (parts.length != 2) continue;
          final lapStart = int.tryParse(parts[0]) ?? -1;
          final lapEnd = int.tryParse(parts[1]) ?? -1;

          if (s >= lapStart && e <= lapEnd) {
            // この区間を分割する
            final oldLap = _laps[i];
            _laps.removeAt(i);

            // 分割後の区間を作成
            // 1. 開始がずれている場合 (例: 0-25 を 10-25 にする場合、0-10 を作る)
            if (s > lapStart) {
              _laps.insert(i++, _LapEntry(section: '$lapStart-${s}m'));
            }
            
            // 2. 指定された新しい区間
            final newLap = _LapEntry(section: '$s-${e}m');
            _laps.insert(i++, newLap);

            // 3. 終了が余っている場合 (例: 0-25 を 0-10 にする場合、10-25 を作る)
            if (e < lapEnd) {
              _laps.insert(i, _LapEntry(section: '$e-${lapEnd}m'));
            }
            
            insertIndex = i; // 計算開始位置
            break;
          }
        }

        // どこにも当てはまらない場合は末尾に追加
        if (insertIndex == -1) {
          _laps.add(_LapEntry(section: '$s-${e}m'));
        }
        
        // 全体の計算をやり直す
        _calculateTimesFromCumulative(0);
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
                  Row(
                    children: [
                      // 日付
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_today, color: Colors.tealAccent),
                          title: const Text('記録日', style: TextStyle(fontSize: 14)),
                          subtitle: Text(
                            '${_selectedDate.year}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
                          ),
                          onTap: () => _selectDate(context),
                        ),
                      ),
                      // トータルタイム (強調)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(context).colorScheme.primaryContainer),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('TOTAL TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                              TextField(
                                controller: _totalTimeController,
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                  hintText: '0:00.00',
                                  hintStyle: TextStyle(fontSize: 20, color: Colors.white24),
                                ),
                                keyboardType: TextInputType.datetime,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                          onPressed: _runOcr,
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
                        onPressed: _generateLaps,
                        icon: const Icon(Icons.refresh),
                        label: const Text('リセット'),
                      ),
                      TextButton.icon(
                        onPressed: _addCustomLap,
                        icon: const Icon(Icons.add),
                        label: const Text('末尾に追加'),
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
                        SizedBox(width: 50, child: Text('区間', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                        SizedBox(width: 4),
                        Expanded(flex: 3, child: Text('累計', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                        SizedBox(width: 4),
                        Expanded(flex: 3, child: Text('ラップ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                        SizedBox(width: 4),
                        Expanded(flex: 2, child: Text('Str', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                        SizedBox(width: 4),
                        Expanded(flex: 2, child: Text('水中(m)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                        SizedBox(width: 4),
                        Expanded(flex: 4, child: Text('備考', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
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
          const SizedBox(height: 32),

          // 登録ボタン
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : () async {
                setState(() => _isSaving = true);
                try {
                  // 保存前に累計ベースで計算を再同期 (累計優先)
                  _calculateTimesFromCumulative(0);
                  
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
                        'distance': _totalDistance,
                        'total_time': _totalTimeController.text,
                      },
                      {'type': 'laps', 'data': _laps.map((l) => {
                        'section': l.sectionController.text,
                        'cumulative': l.cumulativeController.text,
                        'time': l.timeController.text,
                        'stroke': l.strokeController.text,
                        'underwater': l.underwaterController.text,
                        'memo': l.memoController.text,
                      }).toList()}
                    ],
                    subjectiveMetrics: {},
                  );
                  final recordId = await _firestoreService.addTrainingRecord(record);

                  // 自己ベストの更新を試みる
                  final totalSeconds = _parseTime(_totalTimeController.text);
                  if (totalSeconds > 0) {
                    await _firestoreService.updatePersonalBestIfFaster(
                      event: EventUtils.normalizeEventName(_event),
                      value: totalSeconds,
                      date: _selectedDate,
                      trainingRecordId: recordId,
                    );
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('自己分析シートを登録しました。記録は自己ベストにも反映されます。')),
                    );
                    context.pop();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('登録に失敗しました: $e')),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isSaving = false);
                  }
                }
              },
              icon: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle),
              label: const Text('この内容で登録する', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent,
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildLapRow(int index) {
    final lap = _laps[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 50,
            child: TextField(
              controller: lap.sectionController,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 累計
          Expanded(
            flex: 3,
            child: TextField(
              controller: lap.cumulativeController,
              onChanged: (_) => _calculateTimesFromCumulative(index),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.tealAccent),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // ラップ
          Expanded(
            flex: 3,
            child: TextField(
              controller: lap.timeController,
              onChanged: (_) => _calculateTimesFromLap(index),
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: OutlineInputBorder(),
                hintText: '0:00.00',
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Str
          Expanded(
            flex: 2,
            child: TextField(
              controller: lap.strokeController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 水中
          Expanded(
            flex: 2,
            child: TextField(
              controller: lap.underwaterController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 備考
          Expanded(
            flex: 4,
            child: TextField(
              controller: lap.memoController,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.splitscreen, size: 16, color: Colors.blueAccent),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _showSplitDialog(index),
            tooltip: 'この区間を分割',
          ),
        ],
      ),
    );
  }

  void _showSplitDialog(int index) async {
    final lap = _laps[index];
    final parts = lap.sectionController.text.replaceAll('m', '').split('-');
    if (parts.length != 2) return;
    final lapStart = double.tryParse(parts[0]) ?? 0.0;
    final lapEnd = double.tryParse(parts[1]) ?? 0.0;

    final splitController = TextEditingController(text: ((lapStart + lapEnd) / 2).toString());

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${lap.sectionController.text} を分割'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('分割する地点（m）を入力してください', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: splitController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '分割地点 (m)',
                suffixText: 'm',
                hintText: '$lapStart 〜 $lapEnd の間',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(splitController.text);
              if (val != null && val > lapStart && val < lapEnd) {
                Navigator.pop(ctx, val);
              }
            },
            child: const Text('分割'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        final lap1 = _LapEntry(section: '${lapStart}-${result}m');
        final lap2 = _LapEntry(section: '${result}-${lapEnd}m');
        
        // 元のデータの属性を引き継ぐ（オプション）
        lap1.cumulativeController.text = ""; // 再計算させる
        
        _laps.removeAt(index);
        _laps.insert(index, lap1);
        _laps.insert(index + 1, lap2);
        
        _calculateTimesFromCumulative(0);
      });
    }
  }
}

class _LapEntry {
  final TextEditingController sectionController; // 区間名 (編集可能)
  final TextEditingController cumulativeController = TextEditingController(); // 累計タイム
  final TextEditingController timeController = TextEditingController();       // 区間ラップ
  final TextEditingController strokeController = TextEditingController();
  final TextEditingController underwaterController = TextEditingController();
  final TextEditingController memoController = TextEditingController();

  _LapEntry({required String section}) : sectionController = TextEditingController(text: section);
}
