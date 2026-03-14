import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/training_record.dart';
import '../../utils/event_utils.dart';
import '../widgets/stable_text_field.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
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

  Future<void> _runOcr() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isOcrLoading = true);
    try {
      final bytes = await pickedFile.readAsBytes();
      final mimeType = pickedFile.mimeType ?? 'image/jpeg';
      final prompt = """
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
      final prompt = """
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
    return Scaffold(
      appBar: AppBar(title: const Text('トレーニングメニュー入力')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // OCRボタン
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('練習メニュー画像解析', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('ホワイトボードの写真からメニューテキストを自動抽出します'),
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

            // メニューテキストエリア
            StableTextField(
              controller: _menuController,
              lines: 15, // かなり長文まで対応
              hintText: '例: W-up 400\nKick 100x4 (2:00) 1E1H\nPull 100x4 (1:30) 1E1H\nSwim 50x8 (0:45) Hard\n...',
              labelText: '本日の練習メニュー',
            ),
            const SizedBox(height: 16),

            // 練習時間（分）
            const Text('練習時間 (分)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例: 120',
              ),
            ),
            const SizedBox(height: 24),

            // 主なセット間タイム
            const Text('主なセット間タイム', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _timeController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例: 50m x 8 -> Avg 28.5 (28.1 - 29.0)',
              ),
            ),
            const SizedBox(height: 24),

            // 主観感覚（水中 1-10）
            const Text('水中主観感覚 (1: 絶不調 〜 10: 絶好調)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.sentiment_very_dissatisfied, color: Colors.grey),
                Expanded(
                  child: Slider(
                    value: _subjectiveFeeling,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: _subjectiveFeeling.round().toString(),
                    onChanged: (val) {
                      setState(() => _subjectiveFeeling = val);
                    },
                  ),
                ),
                const Icon(Icons.sentiment_very_satisfied, color: Colors.orange),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),

            // 陸上トレーニング・ドライランド
            const Row(
              children: [
                Icon(Icons.fitness_center, color: Colors.tealAccent),
                SizedBox(width: 8),
                Text('陸上トレーニング・ドライランド', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            // 画像解析ボタン（陸上）
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('メニューを写真から取り込む', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('ホワイトボードやノートの写真から自動テキスト抽出'),
                        ],
                      ),
                    ),
                    _isDrylLandOcrLoading
                        ? const CircularProgressIndicator()
                        : ElevatedButton.icon(
                            onPressed: _runDrylLandOcr,
                            icon: const Icon(Icons.document_scanner),
                            label: const Text('写真から取り込む'),
                          ),
                  ],
                ),
              ),
            ),
            StableTextField(
              controller: _drylLandController,
              lines: 8,
              hintText: '例: ベンチプレス 60kg x 10回 x 3セット\n懸垂 15回 x 3セット',
              labelText: '陸上トレーニング内容',
            ),
            const SizedBox(height: 16),
            const Text('陸上主観感覚 (疲労度・筋の張り 1-10)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.battery_alert, color: Colors.grey),
                Expanded(
                  child: Slider(
                    value: _drylLandFeeling,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: _drylLandFeeling.round().toString(),
                    onChanged: (val) {
                      setState(() => _drylLandFeeling = val);
                    },
                  ),
                ),
                const Icon(Icons.battery_full, color: Colors.green),
              ],
            ),
            const SizedBox(height: 32),

            // 陸上トレーニング構造化パース用ヘルパー
            // Input: "ベンチプレス\n1セット目 60kg 10回\n2セット目..."
            // Output: [{'type': 'dryland_set', 'exercise': 'ベンチプレス', 'weight': 60.0, 'reps': 10, 'set_num': 1}, ...]

            // 保存ボタン
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : () async {
                  setState(() => _isSaving = true);
                  try {
                    // 入力内容からTrainingRecordを作成
                    final rawMenu = _menuController.text;
                    final normalizedMenu = EventUtils.normalizeEventName(rawMenu);
                    final poolDetails = normalizedMenu.isNotEmpty ? [{'type': 'menu_text', 'content': normalizedMenu}] : <Map<String, dynamic>>[];
                    
                    if (_timeController.text.isNotEmpty) {
                      final normalizedTime = EventUtils.normalizeEventName(_timeController.text);
                      poolDetails.add({'type': 'main_set_time', 'content': normalizedTime});
                    }
                    final poolTime = int.tryParse(_durationController.text) ?? 0;
                    
                    if (poolDetails.isNotEmpty || poolTime > 0) {
                      final poolRecord = TrainingRecord(
                        id: '', // Firestore側で自動生成
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
                      // 構造化パースの試行
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
                          // 数値が含まれる場合はセットとして処理
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
                      
                      // 元のテキストも検索用に保存
                      drylandDetails.add({'type': 'menu_text', 'content': drylandText});

                      final drylandRecord = TrainingRecord(
                        id: '',
                        date: DateTime.now(),
                        type: 'dryland',
                        details: drylandDetails,
                        subjectiveMetrics: {'feeling': _drylLandFeeling},
                      );
                      await _firestoreService.addTrainingRecord(drylandRecord);
                      // 保存後に陸上トレーニングの自己ベスト自動更新を実行
                      await _firestoreService.generateInitialDrylandPbs();
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('トレーニング記録を保存しました')),
                      );
                      Navigator.pop(context);
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
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(_isSaving ? '保存中...' : 'データを記録して分析へ'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
