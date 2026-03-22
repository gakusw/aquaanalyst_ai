import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/training_record.dart';
import '../widgets/stable_text_field.dart';

class BodyCompositionForm extends StatefulWidget {
  final bool isDialog;
  final VoidCallback? onSaveSuccess;
  const BodyCompositionForm({super.key, this.onSaveSuccess, this.isDialog = false});

  @override
  State<BodyCompositionForm> createState() => _BodyCompositionFormState();
}

class _BodyCompositionFormState extends State<BodyCompositionForm> {
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
      const prompt = """
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
          final weightMatch = RegExp(r'体重[:\s]*(\d+\.?\d*)').firstMatch(result);
          final muscleMatch = RegExp(r'骨格筋量[:\s]*(\d+\.?\d*)').firstMatch(result);
          final fatMatch = RegExp(r'体脂肪率[:\s]*(\d+\.?\d*)').firstMatch(result);

          if (weightMatch != null) _weightController.text = weightMatch.group(1)!;
          if (muscleMatch != null) _muscleController.text = muscleMatch.group(1)!;
          if (fatMatch != null) {
            _fatController.text = fatMatch.group(1)!;
          } else {
            final fatMassMatch = RegExp(r'体脂肪量[:\s]*(\d+\.?\d*)').firstMatch(result);
            if (fatMassMatch != null && weightMatch != null) {
              final fatMass = double.tryParse(fatMassMatch.group(1)!);
              final weight = double.tryParse(weightMatch.group(1)!);
              if (fatMass != null && weight != null && weight > 0) {
                _fatController.text = ((fatMass / weight) * 100).toStringAsFixed(1);
              }
            }
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('体組成計画像の解析が完了しました')));
      } else {
        throw Exception(result ?? '解析失敗');
      }
    } catch (e) {
      if (!mounted) return;
      GeminiService.showErrorDialog(context, e, title: '解析エラー');
    } finally {
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  Future<void> saveRecord() async {
    if (_isSaving) return;
    if (_weightController.text.isEmpty && _memoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('体重またはメモを入力してください')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final weightText = _weightController.text.isNotEmpty ? "体重: ${_weightController.text} kg" : "";
      final muscleText = _muscleController.text.isNotEmpty ? "骨格筋量: ${_muscleController.text} kg" : "";
      final fatText = _fatController.text.isNotEmpty ? "体脂肪率: ${_fatController.text} %" : "";
      final fullText = [weightText, muscleText, fatText, _memoController.text].where((s) => s.isNotEmpty).join("\n");

      final record = TrainingRecord(
        id: '', date: DateTime.now(), type: 'body_composition',
        details: [{'type': 'menu_text', 'content': fullText}],
        subjectiveMetrics: {
          'is_body_composition': true,
          'weight': double.tryParse(_weightController.text) ?? 0.0,
          'muscle_mass': double.tryParse(_muscleController.text) ?? 0.0,
          'body_fat': double.tryParse(_fatController.text) ?? 0.0,
        },
      );

      await _firestoreService.addTrainingRecord(record);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('体組成を記録しました')));
        if (widget.onSaveSuccess != null) widget.onSaveSuccess!(); else Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        GeminiService.showErrorDialog(context, e, title: '保存エラー');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isOcrLoading || true) // Row is preserved but modified
          Row(
            children: [
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
          const SizedBox(height: 16),

          Row(
            children: [
              _buildInput('体重', _weightController, 'kg'),
              const SizedBox(width: 16),
              _buildInput('骨格筋量', _muscleController, 'kg'),
            ],
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              _buildInput('体脂肪率', _fatController, '%'),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 24),

          const Text('詳細メモ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          StableTextField(
            controller: _memoController,
            lines: 6,
            hintText: '解析結果や補足など',
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, String suffix) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              suffixText: suffix,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}
