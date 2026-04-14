import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/training_record.dart';
import '../../data/models/my_menu.dart';
import '../../data/providers/providers.dart';
import '../../data/providers/ai_provider.dart';
import '../../utils/event_utils.dart';
import '../widgets/stable_text_field.dart';
import '../../utils/app_colors.dart';

class TrainingForm extends ConsumerStatefulWidget {
  final bool isDialog;
  final VoidCallback? onSaveSuccess;
  final TrainingRecord? initialRecord;
  const TrainingForm({
    super.key, 
    this.onSaveSuccess, 
    this.isDialog = false,
    this.initialRecord,
  });

  @override
  ConsumerState<TrainingForm> createState() => _TrainingFormState();
}

class _TrainingFormState extends ConsumerState<TrainingForm> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _menuController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _drylLandController = TextEditingController();
  final TextEditingController _distanceController = TextEditingController();
  double _subjectiveFeeling = 5.0; // 水中主観感覚 1-10
  double _drylLandFeeling = 5.0; // 陸上主観感覚 1-10
  bool _isOcrLoading = false;
  bool _isDrylLandOcrLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialRecord != null) {
      final r = widget.initialRecord!;
      if (r.type == 'pool') {
        _menuController.text = r.details.where((d) => d['type'] == 'menu_text').firstOrNull?['content'] ?? '';
        _timeController.text = r.details.where((d) => d['type'] == 'main_set_time').firstOrNull?['content'] ?? '';
        _durationController.text = r.durationMinutes > 0 ? r.durationMinutes.toString() : '';
        _distanceController.text = r.subjectiveMetrics['total_distance']?.toString() ?? '';
        _subjectiveFeeling = r.subjectiveMetrics['feeling']?.toDouble() ?? 5.0;
      } else if (r.type == 'dryland') {
        _drylLandController.text = r.details.where((d) => d['type'] == 'menu_text').firstOrNull?['content'] ?? '';
        _drylLandFeeling = r.subjectiveMetrics['feeling']?.toDouble() ?? 5.0;
      }
    }
  }

  @override
  void dispose() {
    _menuController.dispose();
    _durationController.dispose();
    _timeController.dispose();
    _drylLandController.dispose();
    _distanceController.dispose();
    super.dispose();
  }

  Future<void> _runOcr() async {
    final source = await _showImageSourcePicker();
    if (source == null) return;
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
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
""";
      final user = ref.read(userProfileProvider).value;
      final aiModel = user?.baseProfile['aiModel'] as String? ?? GeminiService.modelFlash;
      final aiService = ref.read(aiServiceProvider);
      final result = await aiService.generateContentWithImage(prompt, bytes, mimeType, modelId: aiModel, userId: user?.uid);
      
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
      GeminiService.showErrorDialog(context, e, title: '解析エラー');
    } finally {
      if (mounted) {
        setState(() => _isOcrLoading = false);
      }
    }
  }

  Future<void> _runDrylLandOcr() async {
    final source = await _showImageSourcePicker();
    if (source == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (pickedFile == null) return;

    setState(() => _isDrylLandOcrLoading = true);
    
    try {
      final bytes = await pickedFile.readAsBytes();
      final mimeType = pickedFile.mimeType ?? 'image/jpeg';
      const prompt = '画像内の陸上トレーニング（筋トレなど）の記録をテキストとして抽出してください。\n'
          'ホワイトボードの手書きメニューや、トレーニング記録アプリのスクリーンショットなど、どのような形式の画像でも対応してください。\n\n'
          'システムで自己ベストなどを自動認識するため、以下の点に注意して整形してください。\n'
          '1. 各トレーニングの「種目名」を1行目に書く\n'
          '2. その下に各セットの情報を「1セット目 30.0kg 10回」のように書く\n'
          '3. 種目が変わる場合は、新しい種目名を1行書いてからセット情報を続ける\n'
          '4. AIの挨拶や解説文などは一切含めないこと\n\n'
          '出力例：\n'
          'ベンチプレス\n'
          '1セット目 60.0kg 10回\n'
          '2セット目 60.0kg 8回\n'
          'スクワット\n'
          '1セット目 80.0kg 12回';

      final user = ref.read(userProfileProvider).value;
      final aiModel = user?.baseProfile['aiModel'] as String? ?? GeminiService.modelFlash;
      final aiService = ref.read(aiServiceProvider);
      final result = await aiService.generateContentWithImage(prompt, bytes, mimeType, modelId: aiModel, userId: user?.uid);
      
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
      GeminiService.showErrorDialog(context, e, title: '解析エラー');
    } finally {
      if (mounted) {
        setState(() => _isDrylLandOcrLoading = false);
      }
    }
  }

  Future<ImageSource?> _showImageSourcePicker() async {
    return await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('画像ソースを択', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('ギャラリーから選択'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showMyMenuSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MyMenuSheet(
        currentContent: _menuController.text.trim(),
        onSelect: (content) {
          setState(() {
            if (_menuController.text.isNotEmpty) {
              _menuController.text += '\n\n';
            }
            _menuController.text += content;
          });
        },
      ),
    );
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
              else ...[
                TextButton.icon(
                  onPressed: _runOcr,
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text('写真解析', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
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
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _showMyMenuSheet,
                icon: const Icon(Icons.bookmark, size: 16, color: Colors.teal),
                label: const Text('Myメニュー', style: TextStyle(fontSize: 12, color: Colors.teal)),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
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
          const SizedBox(height: 16),
          const Text('合計距離 (m)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          TextField(
            controller: _distanceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '例: 2500',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
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
              const Icon(Icons.fitness_center, color: Colors.white, size: 20),
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
        final poolDist = int.tryParse(_distanceController.text) ?? 0;
        
        if (poolDetails.isNotEmpty || poolTime > 0 || poolDist > 0) {
          final recordData = {
            'type': 'pool',
            'durationMinutes': poolTime,
            'details': poolDetails,
            'subjectiveMetrics': {
              'feeling': _subjectiveFeeling,
              'total_distance': poolDist,
            },
          };

          if (widget.initialRecord != null && widget.initialRecord!.type == 'pool') {
            await _firestoreService.updateTrainingRecord(widget.initialRecord!.id, recordData);
          } else {
            final poolRecord = TrainingRecord(
              id: '', 
              date: DateTime.now(),
              type: 'pool',
              durationMinutes: poolTime,
              details: poolDetails,
              subjectiveMetrics: {
                'feeling': _subjectiveFeeling,
                'total_distance': poolDist,
              },
            );
            await _firestoreService.addTrainingRecord(poolRecord);
          }
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

        final recordData = {
          'type': 'dryland',
          'details': drylandDetails,
          'subjectiveMetrics': {'feeling': _drylLandFeeling},
        };

        if (widget.initialRecord != null && widget.initialRecord!.type == 'dryland') {
          await _firestoreService.updateTrainingRecord(widget.initialRecord!.id, recordData);
        } else {
          final drylandRecord = TrainingRecord(
            id: '',
            date: DateTime.now(),
            type: 'dryland',
            details: drylandDetails,
            subjectiveMetrics: {'feeling': _drylLandFeeling},
          );
          await _firestoreService.addTrainingRecord(drylandRecord);
        }
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
        GeminiService.showErrorDialog(context, e, title: '保存エラー');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _MyMenuSheet extends ConsumerStatefulWidget {
  final String currentContent;
  final Function(String) onSelect;
  const _MyMenuSheet({required this.currentContent, required this.onSelect});

  @override
  ConsumerState<_MyMenuSheet> createState() => _MyMenuSheetState();
}

class _MyMenuSheetState extends ConsumerState<_MyMenuSheet> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    final myMenusAsync = ref.watch(myMenusProvider);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            AppBar(
              title: const Text('Myメニューリスト', style: TextStyle(fontSize: 16)),
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Expanded(
              child: myMenusAsync.when(
                data: (menus) => menus.isEmpty
                  ? const Center(child: Text('登録されたメニューはありません'))
                  : ListView.builder(
                      itemCount: menus.length,
                      itemBuilder: (context, index) {
                        final m = menus[index];
                        return ListTile(
                          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(m.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18, color: Colors.teal),
                                onPressed: () => _showEditDialog(m),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                                onPressed: () => _showDeleteConfirm(m),
                              ),
                            ],
                          ),
                          onTap: () {
                            widget.onSelect(m.content);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('エラー: $e')),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add),
                label: const Text('現在内容を新しく登録する'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController(text: widget.currentContent);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Myメニューの登録'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('練習メニューをMyメニューとして保存します。', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl, 
                decoration: const InputDecoration(labelText: 'メニュー名 (例: インターバルA)'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contentCtrl, 
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'メニュー内容'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final content = contentCtrl.text.trim();
              if (name.isEmpty || content.isEmpty) return;
              
              await _firestoreService.saveMyMenu(MyMenu(
                id: '', 
                name: name, 
                content: content, 
                createdAt: DateTime.now(),
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            }, 
            child: const Text('登録')
          ),
        ],
      ),
    );
  }

  void _showEditDialog(MyMenu menu) {
    final nameCtrl = TextEditingController(text: menu.name);
    final contentCtrl = TextEditingController(text: menu.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Myメニューの編集'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl, 
                decoration: const InputDecoration(labelText: 'メニュー名'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contentCtrl, 
                maxLines: 5,
                decoration: const InputDecoration(labelText: '内容'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              
              await _firestoreService.saveMyMenu(MyMenu(
                id: menu.id, 
                name: name, 
                content: contentCtrl.text.trim(), 
                createdAt: menu.createdAt,
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            }, 
            child: const Text('更新')
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(MyMenu menu) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除の確認'),
        content: Text('「${menu.name}」を削除してもよろしいですか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              await _firestoreService.deleteMyMenu(menu.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }
}
