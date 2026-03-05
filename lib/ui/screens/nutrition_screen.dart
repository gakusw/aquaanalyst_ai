import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/training_record.dart';

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _memoController = TextEditingController();
  bool _isOcrLoading = false;
  bool _isBcaOcrLoading = false;
  bool _isSaving = false;
  double _subjectiveProtein = 3;
  double _subjectiveCarbs = 3;
  String _selectedMealLabel = '朝食';

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _runOcr(String type) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isOcrLoading = true);
    try {
      final bytes = await pickedFile.readAsBytes();
      final mimeType = pickedFile.mimeType ?? 'image/jpeg';
      final prompt = """
画像内の食事内容や料理の写真を解析し、何を食べたか（料理名や食材）のみを箇条書きで抽出してください。
実際の料理の写真だけでなく、レシートや記録アプリのスクリーンショットなど、どのような形式の画像からでも対応してください。

出力ルール：
1. 1行に1品目ずつ記載する。
2. 栄養バランスに対する評価やアドバイス、AIの挨拶などの不要な記述は一切含めず、抽出結果のみを出力する。
""";

      final result = await GeminiService().generateContentWithImage(prompt, bytes, mimeType);
      
      if (!mounted) return;
      if (result != null && result.isNotEmpty && !result.startsWith('AIの処理中')) {
        setState(() {
          final current = _memoController.text;
          _memoController.text = current.isEmpty ? "【自動解析: $type】\n$result" : "$current\n\n【自動解析: $type】\n$result";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$typeの画像解析が完了しました')),
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
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  Future<void> _runBcaOcr() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isBcaOcrLoading = true);
    try {
      final bytes = await pickedFile.readAsBytes();
      final mimeType = pickedFile.mimeType ?? 'image/jpeg';
      final prompt = """
画像内の体組成計の測定結果を読み取り、体重、骨格筋量、体脂肪率などの数値を抽出して箇条書きで出力してください。
紙のレシート出力結果や、体組成計アプリのスクリーンショットなど、どのような形式の画像からでも対応してください。

出力ルール：
1. 「項目名: 数値 単位」の形式で1行ずつ箇条書きにする。
2. AIの挨拶や不要な装飾、解説などは一切省いてください。
""";

      final result = await GeminiService().generateContentWithImage(prompt, bytes, mimeType);
      
      if (!mounted) return;
      if (result != null && result.isNotEmpty && !result.startsWith('AIの処理中')) {
        setState(() {
          final current = _memoController.text;
          _memoController.text = current.isEmpty ? "【自動解析: 体組成】\n$result" : "$current\n\n【自動解析: 体組成】\n$result";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('体組成計画像の解析が完了しました')),
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
      if (mounted) setState(() => _isBcaOcrLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日の栄養・体組成記録'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
        // A. クイック自己評価
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('A. クイック主観評価 (1: 不足 〜 5: 十分)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                const Text('タンパク質の摂取感'),
                Slider(
                  value: _subjectiveProtein,
                  min: 1, max: 5, divisions: 4,
                  label: _subjectiveProtein.round().toString(),
                  onChanged: (val) => setState(() => _subjectiveProtein = val),
                  activeColor: Colors.blueAccent,
                ),
                const Text('炭水化物の摂取感'),
                Slider(
                  value: _subjectiveCarbs,
                  min: 1, max: 5, divisions: 4,
                  label: _subjectiveCarbs.round().toString(),
                  onChanged: (val) => setState(() => _subjectiveCarbs = val),
                  activeColor: Colors.orangeAccent,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // B-1. 食事写真引き込み
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('B-1. 食事写真から取り込み', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        '食事の写真からPFCをAIが自動推定します',
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
                            onPressed: () => _runOcr('食事'),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('写真から取り込む'),
                          ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // B-2. 体組成計写真から取り込み
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('B-2. 体組成計から取り込み', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        '体組成計画面の写真から体重・骨格筋量・体脂肪率を自動入力',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                        ),
                      ),
                    ],
                  ),
                ),
                _isBcaOcrLoading
                    ? const CircularProgressIndicator()
                        : ElevatedButton.icon(
                            onPressed: _runBcaOcr,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('写真から取り込む'),
                          ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // C. テキストメモ
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('C. 食事ラベルと内容', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedMealLabel,
                  decoration: const InputDecoration(
                    labelText: '食事ラベル',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  items: ['朝食', '昼食', '夕食', '間食', '未分類'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedMealLabel = val);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _memoController,
                  minLines: 4,
                  maxLines: 4,
                  textAlignVertical: TextAlignVertical.top,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '例: 練習直後にプロテイン30g，夕食は鶏むね肉と玄米...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : () async {
                      setState(() => _isSaving = true);
                      try {
                        final record = TrainingRecord(
                          id: '', // Firestoreで自動生成
                          date: DateTime.now(),
                          type: 'nutrition',
                          details: [
                            if (_memoController.text.isNotEmpty)
                              {'type': 'memo', 'content': _memoController.text}
                          ],
                          subjectiveMetrics: {
                            'protein': _subjectiveProtein,
                            'carbs': _subjectiveCarbs,
                            'meal_label': _selectedMealLabel,
                          },
                        );
                        
                        await _firestoreService.addTrainingRecord(record);
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('今日の栄養データを保存しました'))
                          );
                        }
                      } catch (e) {
                         if (mounted) {
                           ScaffoldMessenger.of(context).showSnackBar(
                             SnackBar(content: Text('保存に失敗しました: $e'))
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
                    label: Text(_isSaving ? '保存中...' : '記録を保存'),
                  ),
                )
              ],
            ),
          ),
        ),
        // 余白
        const SizedBox(height: 80),
      ],
    ),
  );
}
}
