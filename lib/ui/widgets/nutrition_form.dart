import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/training_record.dart';
import '../widgets/stable_text_field.dart';
import '../../data/providers/providers.dart';
import '../../utils/app_colors.dart';
import '../../utils/date_utils.dart';
import '../../data/models/my_product.dart';

class NutritionForm extends ConsumerStatefulWidget {
  final bool isDialog;
  final VoidCallback? onSaveSuccess;
  final TrainingRecord? initialRecord;
  const NutritionForm({
    super.key, 
    this.onSaveSuccess, 
    this.isDialog = false,
    this.initialRecord,
  });

  @override
  ConsumerState<NutritionForm> createState() => _NutritionFormState();
}

class _NutritionFormState extends ConsumerState<NutritionForm> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _pController = TextEditingController();
  final TextEditingController _fController = TextEditingController();
  final TextEditingController _cController = TextEditingController();
  bool _isOcrLoading = false;
  bool _isSaving = false;
  bool _hasAnalyzed = false;
  String _selectedMealLabel = '朝食';

  @override
  void initState() {
    super.initState();
    if (widget.initialRecord != null) {
      final r = widget.initialRecord!;
      _memoController.text = r.details.isNotEmpty ? (r.details.first['content'] ?? '') : '';
      _pController.text = (r.subjectiveMetrics['protein']?.toDouble() ?? 0.0).round().toString();
      _fController.text = (r.subjectiveMetrics['fat']?.toDouble() ?? 0.0).round().toString();
      _cController.text = (r.subjectiveMetrics['carbs']?.toDouble() ?? 0.0).round().toString();
      _selectedMealLabel = r.subjectiveMetrics['meal_label'] ?? '朝食';
      _hasAnalyzed = true; 
    }
    // カロリー表示・解析状態更新用リスナー
    _pController.addListener(_onPfcChanged);
    _fController.addListener(_onPfcChanged);
    _cController.addListener(_onPfcChanged);
    _memoController.addListener(_onMemoChanged);
  }

  void _onMemoChanged() {
    if (_hasAnalyzed) {
      setState(() => _hasAnalyzed = false);
    }
  }

  void _onPfcChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _memoController.dispose();
    _pController.dispose();
    _fController.dispose();
    _cController.dispose();
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
      final prompt = await GeminiService().nutritionOcrInstruction;

      final user = ref.read(userProfileProvider).value;
      final modelId = user?.baseProfile['aiModel'] as String? ?? GeminiService.modelFlash;

      final result = await GeminiService().generateContentWithImage(prompt, bytes, mimeType, modelId: modelId);
      
      if (!mounted) return;
      if (result != null && result.isNotEmpty && !result.startsWith('AIの処理中')) {
        setState(() {
          final current = _memoController.text;
          _memoController.text = current.isEmpty ? "【自動解析: $type】\n$result" : "$current\n\n【自動解析: $type】\n$result";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$typeの画像解析が完了しました')),
        );
        _runAiAnalysis();
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

  void _showMyProductSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MyProductsSheet(
        onSelect: (product) {
          setState(() {
            final current = _memoController.text;
            final insertText = '【My食品: ${product.name} (基準量: ${product.baseAmount}${product.unit}) P:${product.protein}g F:${product.fat}g C:${product.carbs}g ${product.calories}kcal】';
            _memoController.text = current.isEmpty ? insertText : "$current\n$insertText";
          });
        },
      ),
    );
  }

  bool _isAiAnalyzing = false;
  Future<void> _runAiAnalysis() async {
    if (_memoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('食事内容を入力してください')),
      );
      return;
    }

    setState(() => _isAiAnalyzing = true);
    try {
      final user = ref.read(userProfileProvider).value;
      final modelId = user?.baseProfile['aiModel'] as String?;
      final myProducts = ref.read(myProductsProvider).value;
      
      final result = await GeminiService().analyzeNutrition(
        _memoController.text, 
        modelId: modelId,
        myProducts: myProducts,
      );
      if (result != null) {
        if (result.protein > 250 || result.fat > 150 || result.carbs > 400) {
          if (!mounted) return;
          final bool? proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 48),
              title: const Text('異常な推定値を検出'),
              content: Text(
                'AIの推定結果に異常な数値が含まれています：\n\n'
                '・タンパク質: ${result.protein.round()}g (上限250)\n'
                '・脂質: ${result.fat.round()}g (上限150)\n'
                '・炭水化物: ${result.carbs.round()}g (上限400)\n\n'
                'このまま上限値に丸めて反映しますか？'
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('反映')),
              ],
            ),
          );
          if (proceed != true) return;
        }

        setState(() {
          _pController.text = result.protein.clamp(0.0, 250.0).round().toString();
          _fController.text = result.fat.clamp(0.0, 150.0).round().toString();
          _cController.text = result.carbs.clamp(0.0, 400.0).round().toString();
          _hasAnalyzed = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('AI解析完了: ${result.reason}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        GeminiService.showErrorDialog(context, e, title: 'AI解析エラー');
      }
    } finally {
      if (mounted) setState(() => _isAiAnalyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 解析時に利用するため、プロバイダーを watch してデータをロードしておく
    ref.watch(myProductsProvider);

    final pV = double.tryParse(_pController.text) ?? 0.0;
    final fV = double.tryParse(_fController.text) ?? 0.0;
    final cV = double.tryParse(_cController.text) ?? 0.0;
    final totalKcal = (pV * 4 + fV * 9 + cV * 4).round();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A. 栄養量入力
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('栄養量 (g)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              Text('$totalKcal kcal', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
            ],
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              _buildNutritionInput('タンパク質', _pController, color: Colors.blueAccent),
              const SizedBox(width: 12),
              _buildNutritionInput('脂質', _fController, color: Colors.redAccent),
              const SizedBox(width: 12),
              _buildNutritionInput('炭水化物', _cController, color: Colors.orangeAccent),
            ],
          ),
          const SizedBox(height: 24),

          // B. 写真解析・メモ
          Row(
            children: [
              const Icon(Icons.fitness_center, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text('食事内容・メモ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_isOcrLoading)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else ...[
                TextButton.icon(
                  onPressed: _showMyProductSheet,
                  icon: const Icon(Icons.bookmark, size: 16, color: Colors.orange),
                  label: const Text('My食品', style: TextStyle(fontSize: 12, color: Colors.orange)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                TextButton.icon(
                  onPressed: () => _runOcr('食事'),
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('写真解析', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              const Text('ラベル: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedMealLabel,
                  isExpanded: true,
                  underline: const SizedBox(),
                  style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                  items: ['朝食', '昼食', '夕食', '間食', '未分類'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                  onChanged: (val) { if (val != null) setState(() => _selectedMealLabel = val); },
                ),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),

          StableTextField(
            controller: _memoController,
            lines: 6,
            hintText: '例: カップヌードル 1個、サラダチキン 110g...',
          ),
          const SizedBox(height: 12),
          
          Align(
            alignment: Alignment.centerRight,
            child: _isAiAnalyzing 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton.icon(
                  onPressed: _runAiAnalysis,
                  icon: Icon(_hasAnalyzed ? Icons.check_circle : Icons.auto_awesome, size: 18),
                  label: const Text('PFCをAI推定', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(
                    foregroundColor: _hasAnalyzed ? Colors.greenAccent : AppColors.skyBlue,
                  ),
                ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildNutritionInput(String label, TextEditingController controller, {required Color color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            decoration: const InputDecoration(
              suffixText: 'g',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> saveRecord() async {
    if (_isSaving) return;
    if (_memoController.text.isNotEmpty && !_hasAnalyzed) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('PFC自動推定が未実行です'),
            content: const Text('このまま保存しますか？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('戻る')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
            ],
          ),
        );
        if (proceed != true) return;
    }
    setState(() => _isSaving = true);
    try {
      final user = ref.read(userProfileProvider).value;
      
      // 当日の目標値を取得（永続化のため）
      int targetP = user?.baseProfile['targetProtein'] ?? 150;
      int targetF = user?.baseProfile['targetFat'] ?? 70;
      int targetC = user?.baseProfile['targetCarbs'] ?? 400;
      int targetCal = user?.baseProfile['targetCalories'] ?? 2500;

      final latestPlan = ref.read(latestWeeklyPlanProvider).value;
      if (latestPlan != null) {
        final logicalToday = AppDateUtils.logicalToday();
        final weekdayStr = ['月曜','火曜','水曜','木曜','金曜','土曜','日曜'][logicalToday.weekday - 1];
        final todaysPlan = latestPlan.dailyPlans.where((p) => p.dateStr.contains(weekdayStr)).firstOrNull;
        if (todaysPlan != null) {
             targetP = todaysPlan.targetProtein > 0 ? todaysPlan.targetProtein : targetP;
             targetF = todaysPlan.targetFat > 0 ? todaysPlan.targetFat : targetF;
             targetC = todaysPlan.targetCarbs > 0 ? todaysPlan.targetCarbs : targetC;
             targetCal = todaysPlan.targetCalories > 0 ? todaysPlan.targetCalories : targetCal;
        }
      }

      final Map<String, int> dailyTargets = {
        'protein': targetP,
        'fat': targetF,
        'carbs': targetC,
        'calories': targetCal,
      };

      final recordData = {
        'type': 'nutrition',
        'details': [if (_memoController.text.isNotEmpty) {'type': 'memo', 'content': _memoController.text}],
        'subjectiveMetrics': {
          'protein': double.tryParse(_pController.text) ?? 0.0, 
          'fat': double.tryParse(_fController.text) ?? 0.0, 
          'carbs': double.tryParse(_cController.text) ?? 0.0, 
          'meal_label': _selectedMealLabel
        },
        'dailyTargets': dailyTargets, // 永続化
      };

      if (widget.initialRecord != null) {
        await _firestoreService.updateTrainingRecord(widget.initialRecord!.id, recordData);
      } else {
        final record = TrainingRecord(
          id: '', 
          date: DateTime.now(), 
          type: 'nutrition',
          details: List<Map<String, dynamic>>.from(recordData['details'] as List),
          subjectiveMetrics: recordData['subjectiveMetrics'] as Map<String, dynamic>,
          dailyTargets: dailyTargets,
        );
        await _firestoreService.addTrainingRecord(record);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存しました')));
        if (widget.onSaveSuccess != null) {
          widget.onSaveSuccess!();
        } else {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        GeminiService.showErrorDialog(context, e, title: '保存エラー');
      }
    } finally { if (mounted) setState(() => _isSaving = false); }
  }
}

class _MyProductsSheet extends StatefulWidget {
  final Function(MyProduct) onSelect;
  const _MyProductsSheet({required this.onSelect});

  @override
  State<_MyProductsSheet> createState() => _MyProductsSheetState();
}

class _MyProductsSheetState extends State<_MyProductsSheet> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            AppBar(
              title: const Text('My食品リスト', style: TextStyle(fontSize: 16)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Expanded(
              child: StreamBuilder<List<MyProduct>>(
                stream: _firestoreService.getMyProductsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  final products = snapshot.data ?? [];
                  if (products.isEmpty) {
                    return const Center(child: Text('登録されたMy食品はありません'));
                  }
                  return ListView.builder(
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final p = products[index];
                      return ListTile(
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('基準量: ${p.baseAmount}${p.unit} - P:${p.protein}g F:${p.fat}g C:${p.carbs}g / ${p.calories}kcal', style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, size: 14, color: Colors.grey),
                          onPressed: () => _firestoreService.deleteMyProduct(p.id),
                        ),
                        onTap: () {
                          widget.onSelect(p);
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add),
                label: const Text('新しく登録する'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController(text: '100');
    final unitCtrl = TextEditingController(text: 'g');
    final pCtrl = TextEditingController();
    final fCtrl = TextEditingController();
    final cCtrl = TextEditingController();
    final kcalCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('My食品の登録'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '食品名 (例: 鶏むね肉)')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(flex: 2, child: TextField(controller: amountCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '基準量 (例: 100)'))),
                  const SizedBox(width: 8),
                  Expanded(flex: 1, child: TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: '単位 (例: g)'))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: pCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'タンパク質'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: fCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '脂質'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: cCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '炭水化物'))),
                ],
              ),
              const SizedBox(height: 8),
              TextField(controller: kcalCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'カロリー (kcal)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final amount = double.tryParse(amountCtrl.text) ?? 100.0;
              final unit = unitCtrl.text.trim();
              final p = double.tryParse(pCtrl.text) ?? 0;
              final f = double.tryParse(fCtrl.text) ?? 0;
              final c = double.tryParse(cCtrl.text) ?? 0;
              final kcal = double.tryParse(kcalCtrl.text) ?? 0;
              
              await _firestoreService.saveMyProduct(MyProduct(
                id: '', name: name, baseAmount: amount, unit: unit, protein: p, fat: f, carbs: c, calories: kcal
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            }, 
            child: const Text('登録')
          ),
        ],
      ),
    );
  }
}
