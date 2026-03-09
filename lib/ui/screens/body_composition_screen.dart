import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/training_record.dart';
import '../widgets/stable_text_field.dart';

class BodyCompositionScreen extends StatefulWidget {
  const BodyCompositionScreen({super.key});

  @override
  State<BodyCompositionScreen> createState() => _BodyCompositionScreenState();
}

class _BodyCompositionScreenState extends State<BodyCompositionScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _muscleController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  bool _isOcrLoading = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _weightController.dispose();
    _muscleController.dispose();
    _fatController.dispose();
    _memoController.dispose();
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
      final prompt = """
画像内の体組成計の測定結果を読み取り、体重、骨格筋量、体脂肪率などの数値を抽出してください。
紙のレシート出力結果や、体組成計アプリのスクリーンショットなど、どのような形式の画像からでも対応してください。

出力ルール：
1. 「項目名: 数値 単位」の形式で1行ずつ箇条書きにする。
2. AIの挨拶や不要な装飾、解説などは一切省いてください。
""";

      final result = await GeminiService().generateContentWithImage(prompt, bytes, mimeType);
      
      if (!mounted) return;
      if (result != null && result.isNotEmpty && !result.startsWith('AIの処理中')) {
        setState(() {
          _memoController.text = result;
          
          // 数値を自動抽出して各フィールドに埋める（簡易パース）
          final weightMatch = RegExp(r'体重[:\s]*(\d+\.?\d*)').firstMatch(result);
          final muscleMatch = RegExp(r'骨格筋量[:\s]*(\d+\.?\d*)').firstMatch(result);
          final fatMatch = RegExp(r'体脂肪率[:\s]*(\d+\.?\d*)').firstMatch(result);

          if (weightMatch != null) _weightController.text = weightMatch.group(1)!;
          if (muscleMatch != null) _muscleController.text = muscleMatch.group(1)!;
          if (fatMatch != null) {
            _fatController.text = fatMatch.group(1)!;
          } else {
            // 体脂肪率がない場合、体脂肪量から逆算を試みる
            final fatMassMatch = RegExp(r'体脂肪量[:\s]*(\d+\.?\d*)').firstMatch(result);
            if (fatMassMatch != null && weightMatch != null) {
              final fatMass = double.tryParse(fatMassMatch.group(1)!);
              final weight = double.tryParse(weightMatch.group(1)!);
              if (fatMass != null && weight != null && weight > 0) {
                final calculatedFatPct = (fatMass / weight) * 100;
                _fatController.text = calculatedFatPct.toStringAsFixed(1);
              }
            }
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('体組成計画像の解析が完了しました')),
        );
      } else {
        throw Exception(result ?? '解析失敗');
      }
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errMsg)),
      );
    } finally {
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  Future<void> _saveRecord() async {
    if (_weightController.text.isEmpty && _memoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('体重またはメモを入力してください')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      // 数値を含んだ詳細テキストを作成
      final weightText = _weightController.text.isNotEmpty ? "体重: ${_weightController.text} kg" : "";
      final muscleText = _muscleController.text.isNotEmpty ? "骨格筋量: ${_muscleController.text} kg" : "";
      final fatText = _fatController.text.isNotEmpty ? "体脂肪率: ${_fatController.text} %" : "";
      
      final fullText = [weightText, muscleText, fatText, _memoController.text]
          .where((s) => s.isNotEmpty)
          .join("\n");

      final record = TrainingRecord(
        id: '',
        date: DateTime.now(),
        type: 'nutrition', // 体組成も分析のため 'nutrition' カテゴリとして扱う（既存との互換性）
        details: [{'type': 'menu_text', 'content': fullText}],
        subjectiveMetrics: {
          'is_body_composition': true, // 明示的なフラグ
          'weight': double.tryParse(_weightController.text) ?? 0.0,
          'muscle_mass': double.tryParse(_muscleController.text) ?? 0.0,
          'body_fat': double.tryParse(_fatController.text) ?? 0.0,
        },
      );

      await _firestoreService.addTrainingRecord(record);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('体組成を記録しました')),
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('体組成記録')),
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
                          Text('写真から読み取る', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('体組成計の画面やレシートを解析します'),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isOcrLoading ? null : _runOcr,
                      icon: _isOcrLoading 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.camera_alt),
                      label: const Text('解析'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // マニュアル入力
            const Text('数値を入力', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '体重',
                      suffixText: 'kg',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _muscleController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '骨格筋量',
                      suffixText: 'kg',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fatController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '体脂肪率',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            const Text('メモ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            StableTextField(
              controller: _memoController,
              lines: 4,
              hintText: 'その他の詳細など',
              labelText: 'メモ',
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _saveRecord,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(_isSaving ? '保存中...' : '体組成を保存'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
