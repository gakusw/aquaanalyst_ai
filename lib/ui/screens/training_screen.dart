import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/training_record.dart';

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
ただし、以下のルールを厳守して人間が読みやすい形式に整形してください：
1. 「Category|Distance...」のような表のヘッダー行や、「|||」のようなエクセルの枠線・空セルの記号はすべて除外してください。
2. ページ下部の「Strength Table」などの補足情報は読み取らないでください。
3. 種目（W-Up, Drill, Kick, Swim, Down等）、距離、本数、サイクルタイム、指定強度や補足説明だけを抜き出し、シンプルなテキスト（例: W-Up 300 x 1 6:00 A1）として出力してください。
4. 挨拶や不要な装飾は省いてください。
""";

      final result = await GeminiService().generateContentWithImage(prompt, bytes, mimeType);
      
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('画像の解析に失敗しました')),
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
      final prompt = "画像内の陸上トレーニング（筋トレなど）のメニューを読み取り、テキストとして出力してください。不要な装飾や挨拶は省き、メニュー内容のみをそのまま抽出してください。";

      final result = await GeminiService().generateContentWithImage(prompt, bytes, mimeType);
      
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('画像の解析に失敗しました')),
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
            const SizedBox(height: 24),

            // メニューテキストエリア
            const Text('本日の練習メニュー', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _menuController,
              minLines: 5,
              maxLines: 5,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例: W-up 400\nKick 100x4 (2:00) 1E1H\nPull 100x4 (1:30) 1E1H\nSwim 50x8 (0:45) Hard\n...',
              ),
            ),
            const SizedBox(height: 24),

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
            const SizedBox(height: 12),
            TextField(
              controller: _drylLandController,
              minLines: 4,
              maxLines: 4,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例: ベンチプレス 60kg x 10回 x 3セット\n懸垂 15回 x 3セット',
              ),
            ),
            const SizedBox(height: 24),
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

            // 保存ボタン
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : () async {
                  setState(() => _isSaving = true);
                  try {
                    // 入力内容からTrainingRecordを作成
                    final poolDetails = _menuController.text.isNotEmpty ? [{'type': 'menu_text', 'content': _menuController.text}] : <Map<String, dynamic>>[];
                    if (_timeController.text.isNotEmpty) {
                      poolDetails.add({'type': 'main_set_time', 'content': _timeController.text});
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

                    final drylandDetails = _drylLandController.text.isNotEmpty ? [{'type': 'menu_text', 'content': _drylLandController.text}] : <Map<String, dynamic>>[];
                    if (drylandDetails.isNotEmpty) {
                      final drylandRecord = TrainingRecord(
                        id: '',
                        date: DateTime.now(),
                        type: 'dryland',
                        details: drylandDetails,
                        subjectiveMetrics: {'feeling': _drylLandFeeling},
                      );
                      await _firestoreService.addTrainingRecord(drylandRecord);
                      // 保存後に陸上トレーニングの自己ベスト自動更新を実行
                      _firestoreService.generateInitialDrylandPbs();
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('トレーニング記録を保存しました．続いてAIコーチの分析を確認できます．')),
                      );
                      // Navigator.pop等で戻る実装を追加する場合はここに記述
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
