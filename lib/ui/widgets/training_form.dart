import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/training_record.dart';
import '../../utils/event_utils.dart';
import '../widgets/stable_text_field.dart';
import '../../utils/app_colors.dart';

class TrainingForm extends StatefulWidget {
  final bool isDialog;
  final VoidCallback? onSaveSuccess;
  const TrainingForm({super.key, this.onSaveSuccess, this.isDialog = false});

  @override
  State<TrainingForm> createState() => _TrainingFormState();
}

class _TrainingFormState extends State<TrainingForm> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _menuController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _drylLandController = TextEditingController();
  double _subjectiveFeeling = 5.0; // 水中主観感覚 1-10
  double _drylLandFeeling = 5.0; // 陸上主観感覚 1-10
  bool _isOcrLoading = false;
  bool _isDrylLandOcrLoading = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _menuController.dispose();
    _durationController.dispose();
    _timeController.dispose();
    _drylLandController.dispose();
    super.dispose();
  }

  Future<void> _runOcr() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isOcrLoading = true);
    try {
      final bytes = await pickedFile.readAsBytes();
      final mimeType = pickedFile.mimeType ?? 'image/jpeg';
      const prompt = """
画像内の水泳の練習メニュー表を読み取って抽出してください。
印刷されたメニュー表、手書きのホワイトボード、アプリのスクリーンショットなど、どのような形式の画像からでも対応してください。

以下のルールを厳守して人間が読みやすい形式に整形してください：
1. 「Category|Distance...」のような表のヘッダー行や、「|||」のようなエクセルの枠線・空セルの記号はすべて除外してください。
2. ページ下部の「Strength Table」などの補足情報は読み取らないでください。
3. 種目（W-Up, Drill, Kick, Swim, Down等）、距離、本数、サイクルタイム、指定強度や補足説明だけを抜き出し、シンプルなテキスト（例: W-Up 300 x 1 6:00 A1）として出力してください。
4. プロンプトに対するAIの返答（挨拶や解説）や不要な装飾は一切省き、抽出したメニュー内容のみを出力してください。
""";

      final result = await GeminiService().generateContentWithImage(prompt, bytes, mimeType, modelId: GeminiService.modelFlash);
      
      if (!mounted) return;
      if (result != null && result.isNotEmpty && !result.startsWith('AIの処理中')) {
        setState(() {
          _menuController.text = result;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ホワイトボードの読み取りが完了しました')),
        );
      } else {
        throw Exception(result ?? '解析失敗');
      }
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errMsg)),
      );
    } finally {
      if (mounted) {
        setState(() => _isOcrLoading = false);
      }
    }
  }

  Future<void> _runDrylLandOcr() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isDrylLandOcrLoading = true);
    
    try {
      final bytes = await pickedFile.readAsBytes();
      final mimeType = pickedFile.mimeType ?? 'image/jpeg';
      const prompt = """
画像内の陸上トレーニング（筋トレなど）の記録をテキストとして抽出してください。
ホワイトボードの手書きメニューや、トレーニング記録アプリのスクリーンショットなど、どのような形式の画像でも対応してください。

システムで自己ベストなどを自動認識するため、以下の点に注意して整形してください。
1. 各トレーニングの「種目名」を1行目に書く
2. その下に各セットの情報を「1セット目 30.0kg 10回」のように書く
3. 種目が変わる場合は、新しい種目名を1行書いてからセット情報を続ける
4. AIの挨拶や解説文などは一切含めないこと

出力例：
ベンチプレス
1セット目 60.0kg 10回
2セット目 60.0kg 8回
スクワット
1セット目 80.0kg 12回
""";

      final result = await GeminiService().generateContentWithImage(prompt, bytes, mimeType, modelId: GeminiService.modelFlash);
      
      if (!mounted) return;
      if (result != null && result.isNotEmpty && !result.startsWith('AIの処理中')) {
        setState(() {
          _drylLandController.text = result;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('陸上トレーニングメニューの読み取りが完了しました')),
        );
      } else {
        throw Exception(result ?? '解析失敗');
      }
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errMsg)),
      );
    } finally {
      if (mounted) {
        setState(() => _isDrylLandOcrLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 水中トレーニングセクション
          Row(
            children: [
              Icon(Icons.waves, color: AppColors.skyBlue, size: 20),
              const SizedBox(width: 8),
              const Text('水中トレーニング', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
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
          const SizedBox(height: 8),
          
          const Text('練習メニュー', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          StableTextField(
            controller: _menuController,
            lines: 8,
            hintText: '',
            // labelText は省いて上に Text で表示
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('練習時間', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    TextField(
                      controller: _durationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('重要セットタイム', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    TextField(
                      controller: _timeController,
                      decoration: const InputDecoration(
                        hintText: '',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          const Text('水中主観感覚 (1-10)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Row(
            children: [
              Text(_subjectiveFeeling.round().toString(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.skyBlue)),
              Expanded(
                child: Slider(
                  value: _subjectiveFeeling,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (val) => setState(() => _subjectiveFeeling = val),
                ),
              ),
            ],
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16.0),
            child: Divider(height: 1),
          ),

          // 陸上トレーニングセクション
          Row(
            children: [
              const Icon(Icons.fitness_center, color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 8),
              const Text('陸上トレーニング', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_isDrylLandOcrLoading)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton.icon(
                  onPressed: _runDrylLandOcr,
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('写真解析', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
            ],
          ),
          const SizedBox(height: 8),

          const Text('トレーニング内容', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          StableTextField(
            controller: _drylLandController,
            lines: 6,
            hintText: '',
          ),
          const SizedBox(height: 16),

          const Text('疲労度・筋の張り (1-10)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Row(
            children: [
              Text(_drylLandFeeling.round().toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
              Expanded(
                child: Slider(
                  value: _drylLandFeeling,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (val) => setState(() => _drylLandFeeling = val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> saveRecord() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final rawMenu = _menuController.text;
      final normalizedMenu = EventUtils.normalizeEventName(rawMenu);
      final List<Map<String, dynamic>> poolDetails = normalizedMenu.isNotEmpty ? [{'type': 'menu_text', 'content': normalizedMenu}] : [];
      
      if (_timeController.text.isNotEmpty) {
        final normalizedTime = EventUtils.normalizeEventName(_timeController.text);
        poolDetails.add({'type': 'main_set_time', 'content': normalizedTime});
      }
      final poolTime = int.tryParse(_durationController.text) ?? 0;
      
      if (poolDetails.isNotEmpty || poolTime > 0) {
        final poolRecord = TrainingRecord(
          id: '', 
          date: DateTime.now(),
          type: 'pool',
          durationMinutes: poolTime,
          details: poolDetails,
          subjectiveMetrics: {'feeling': _subjectiveFeeling},
        );
        await _firestoreService.addTrainingRecord(poolRecord);
      }

      final drylandText = _drylLandController.text.trim();
      final List<Map<String, dynamic>> drylandDetails = [];
      
      if (drylandText.isNotEmpty) {
        final lines = drylandText.split('\n');
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
              drylandDetails.add({
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
        
        drylandDetails.add({'type': 'menu_text', 'content': drylandText});

        final drylandRecord = TrainingRecord(
          id: '',
          date: DateTime.now(),
          type: 'dryland',
          details: drylandDetails,
          subjectiveMetrics: {'feeling': _drylLandFeeling},
        );
        await _firestoreService.addTrainingRecord(drylandRecord);
        await _firestoreService.generateInitialDrylandPbs();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('トレーニング記録を保存しました')),
        );
        if (widget.onSaveSuccess != null) {
          widget.onSaveSuccess!();
        } else {
          Navigator.pop(context);
        }
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
  }
}
