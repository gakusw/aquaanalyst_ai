import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/firestore_service.dart';
import '../../data/models/training_record.dart';
import '../../utils/event_utils.dart';
import '../../utils/app_colors.dart';

/// 自己分析シート入力フォーム（モーダル表示用）
class AnalysisSheetForm extends StatefulWidget {
  final bool isDialog;
  final VoidCallback? onSaveSuccess;
  const AnalysisSheetForm({super.key, this.isDialog = false, this.onSaveSuccess});

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
  final ScrollController _horizontalScrollController = ScrollController();

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

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
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
            _calculateTimesFromCumulative(0);
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
      builder: (ctx) => AlertDialog(
        title: const Text('ラップ区間を追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: TextField(controller: startController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '開始 (m)'))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-')),
                Expanded(child: TextField(controller: endController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '終了 (m)'))),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () {
              final s = int.tryParse(startController.text);
              final e = int.tryParse(endController.text);
              if (s != null && e != null && e > s) Navigator.pop(ctx, {'start': s, 'end': e});
            }, 
            child: const Text('追加'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _laps.add(_LapEntry(section: '${result['start']}-${result['end']}m'));
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
    final content = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, color: AppColors.skyBlue, size: 20),
              const SizedBox(width: 8),
              if (_isOcrLoading)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton.icon(
                  onPressed: _runOcr,
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('写真解析', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _selectDate(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('記録日', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        '${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.skyBlue),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TOTAL TIME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    TextField(
                      controller: _totalTimeController,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.skyBlue),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                        hintText: '',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _event,
                  decoration: const InputDecoration(
                    labelText: '種目',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  items: _eventOptions.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _event = val;
                      final match = RegExp(r'(\d+)m').firstMatch(val);
                      if (match != null) {
                        _totalDistance = int.tryParse(match.group(1) ?? '100') ?? 100;
                        _generateLaps();
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('水路', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    DropdownButton<String>(
                      value: _course,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: ['短水路 (25m)', '長水路 (50m)'].map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
                      onChanged: (val) => setState(() {
                        _course = val!;
                        _generateLaps();
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12.0), child: Divider(height: 1)),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ラップ詳細', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(onPressed: _generateLaps, icon: const Icon(Icons.refresh, size: 18), visualDensity: VisualDensity.compact),
                  IconButton(onPressed: _addCustomLap, icon: const Icon(Icons.add_circle_outline, size: 18), visualDensity: VisualDensity.compact),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0), // Scrollbar padding
                child: SizedBox(
                  width: 600,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(4)),
                        child: const Row(
                          children: [
                            SizedBox(width: 50, child: Text('区分', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                            SizedBox(width: 4),
                            SizedBox(width: 80, child: Text('Rap', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                            SizedBox(width: 4),
                            SizedBox(width: 80, child: Text('Sprit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                            SizedBox(width: 4),
                            SizedBox(width: 50, child: Text('Str', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                            SizedBox(width: 4),
                            SizedBox(width: 50, child: Text('UW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                            SizedBox(width: 4),
                            Expanded(child: Text('備考', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                            SizedBox(width: 40),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...List.generate(_laps.length, (i) => _buildLapRow(i)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );

    if (widget.isDialog) return content;
    return Scaffold(
      appBar: AppBar(
        title: Text(
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
      body: content,
    );
  }

  Future<void> saveRecord() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      _calculateTimesFromCumulative(0);
      final record = TrainingRecord(
        id: '', date: _selectedDate, type: 'analysis', durationMinutes: 0,
        details: [
          {'type': 'event_info', 'event': EventUtils.normalizeEventName(_event), 'course': _course, 'distance': _totalDistance, 'total_time': _totalTimeController.text},
          {'type': 'laps', 'data': _laps.map((l) => {'section': l.sectionController.text, 'cumulative': l.cumulativeController.text, 'time': l.timeController.text, 'stroke': l.strokeController.text, 'underwater': l.underwaterController.text, 'memo': l.memoController.text}).toList()}
        ],
        subjectiveMetrics: {},
      );
      final recordId = await _firestoreService.addTrainingRecord(record);
      final totalSeconds = _parseTime(_totalTimeController.text);
      if (totalSeconds > 0) {
        await _firestoreService.updatePersonalBestIfFaster(event: EventUtils.normalizeEventName(_event), value: totalSeconds, date: _selectedDate, trainingRecordId: recordId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登録しました')));
        if (widget.onSaveSuccess != null) widget.onSaveSuccess!(); else context.pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('登録失敗: $e')));
    } finally { if (mounted) setState(() => _isSaving = false); }
  }

  Widget _buildLapRow(int index) {
    final lap = _laps[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          SizedBox(width: 50, child: TextField(controller: lap.sectionController, style: const TextStyle(fontSize: 10, color: Colors.grey), decoration: const InputDecoration(isDense: true, border: InputBorder.none))),
          const SizedBox(width: 4),
          SizedBox(width: 80, child: TextField(controller: lap.cumulativeController, onChanged: (_) => _calculateTimesFromCumulative(index), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.skyBlue), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(4), border: OutlineInputBorder()))),
          const SizedBox(width: 4),
          SizedBox(width: 80, child: TextField(controller: lap.timeController, onChanged: (_) => _calculateTimesFromLap(index), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(4), border: OutlineInputBorder(), hintText: ''))),
          const SizedBox(width: 4),
          SizedBox(width: 50, child: TextField(controller: lap.strokeController, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 12), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(4), border: OutlineInputBorder()))),
          const SizedBox(width: 4),
          SizedBox(width: 50, child: TextField(controller: lap.underwaterController, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(4), border: OutlineInputBorder()))),
          const SizedBox(width: 4),
          Expanded(child: TextField(controller: lap.memoController, style: const TextStyle(fontSize: 11), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(4), border: OutlineInputBorder()))),
          SizedBox(width: 40, child: IconButton(icon: const Icon(Icons.splitscreen, size: 16, color: Colors.blueAccent), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _showSplitDialog(index))),
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
        content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: splitController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '分割地点 (m)', suffixText: 'm', border: OutlineInputBorder()))]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')), TextButton(onPressed: () { final val = double.tryParse(splitController.text); if (val != null && val > lapStart && val < lapEnd) Navigator.pop(ctx, val); }, child: const Text('分割'))],
      ),
    );
    if (result != null) {
      setState(() {
        final lap1 = _LapEntry(section: '${lapStart}-${result}m');
        final lap2 = _LapEntry(section: '${result}-${lapEnd}m');
        _laps.removeAt(index);
        _laps.insert(index, lap1);
        _laps.insert(index + 1, lap2);
        _calculateTimesFromCumulative(0);
      });
    }
  }
}

class _LapEntry {
  final TextEditingController sectionController;
  final TextEditingController cumulativeController = TextEditingController();
  final TextEditingController timeController = TextEditingController();
  final TextEditingController strokeController = TextEditingController();
  final TextEditingController underwaterController = TextEditingController();
  final TextEditingController memoController = TextEditingController();
  _LapEntry({required String section}) : sectionController = TextEditingController(text: section);
}
