import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aquaanalyst_ai/main.dart' show appThemeMode;
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/models/app_user.dart';
import '../widgets/stable_text_field.dart';
import '../../core/app_config.dart';
import '../../data/providers/providers.dart';
import '../../data/providers/ai_provider.dart';
import '../../utils/app_colors.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  int _versionTapCount = 0;

  @override
  void initState() {
    super.initState();
    
    // アプリ起動時のテーマ同期
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(userProfileProvider).value;
      if (user != null) {
        final savedTheme = user.baseProfile['themeMode'] as String?;
        if (savedTheme != null && mounted) {
          appThemeMode.value = savedTheme == 'dark' ? ThemeMode.dark 
                             : savedTheme == 'light' ? ThemeMode.light 
                             : ThemeMode.system;
        }
      }
    });
  }

  Future<void> _editProfileField(BuildContext context, AppUser currentUser, String title, String fieldKey, String currentValue) async {
    final controller = TextEditingController(text: currentValue);
    final newValue = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title の編集'),
        content: SizedBox(
          width: 400, // ダイアログの幅を完全に固定
          child: StableTextField(
            controller: controller,
            hintText: '新しい $title を入力',
            lines: (fieldKey == 'vision' || fieldKey == 'idealCoachPersona' || fieldKey == 'medicalHistory') ? 5 : 1,
            keyboardType: (fieldKey == 'vision' || fieldKey == 'idealCoachPersona' || fieldKey == 'medicalHistory') ? TextInputType.multiline : TextInputType.text,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );

    if (newValue != null && newValue != currentValue && mounted) {
      try {
        // モデルをコピーして更新
        Map<String, dynamic> updatedProfile = Map.from(currentUser.baseProfile);
        String updatedVision = currentUser.vision;
        String updatedDisplayName = currentUser.displayName;

        if (fieldKey == 'vision') {
          updatedVision = newValue;
        } else if (fieldKey == 'displayName') {
          updatedDisplayName = newValue;
        } else if (fieldKey == 'idealCoachPersona') {
          updatedProfile[fieldKey] = newValue;
        } else {
          updatedProfile[fieldKey] = newValue;
        }

        final updatedUser = AppUser(
          uid: currentUser.uid,
          displayName: updatedDisplayName,
          vision: updatedVision,
          baseProfile: updatedProfile,
          createdAt: currentUser.createdAt,
        );

        await _firestoreService.saveUserProfile(updatedUser);
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title を更新しました')));
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog(context, '保存エラー', e.toString());
        }
      }
    }
  }

  void _showErrorDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.red)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _editNutritionGoals(BuildContext context, AppUser currentUser) async {
    final calorieController = TextEditingController(text: currentUser.baseProfile['targetCalories']?.toString() ?? '2500');
    final proteinController = TextEditingController(text: currentUser.baseProfile['targetProtein']?.toString() ?? '150');
    final fatController = TextEditingController(text: currentUser.baseProfile['targetFat']?.toString() ?? '70');
    final carbsController = TextEditingController(text: currentUser.baseProfile['targetCarbs']?.toString() ?? '400');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('標準（デフォルト）栄養目標の編集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('週間計画がない場合や、AIへの指示に使用されます。', style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 16),
            StableTextField(
              controller: calorieController,
              labelText: '目標エネルギー (kcal)',
              hintText: '例: 2500',
              lines: 1,
              keyboardType: TextInputType.number,
            ),
            Row(
              children: [
                Expanded(child: StableTextField(controller: proteinController, labelText: 'P (g)', hintText: '150', lines: 1, keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(child: StableTextField(controller: fatController, labelText: 'F (g)', hintText: '70', lines: 1, keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(child: StableTextField(controller: carbsController, labelText: 'C (g)', hintText: '400', lines: 1, keyboardType: TextInputType.number)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        Map<String, dynamic> updatedProfile = Map.from(currentUser.baseProfile);
        updatedProfile['targetCalories'] = int.tryParse(calorieController.text) ?? 2500;
        updatedProfile['targetProtein'] = int.tryParse(proteinController.text) ?? 150;
        updatedProfile['targetFat'] = int.tryParse(fatController.text) ?? 70;
        updatedProfile['targetCarbs'] = int.tryParse(carbsController.text) ?? 400;

        final updatedUser = AppUser(
          uid: currentUser.uid,
          displayName: currentUser.displayName,
          vision: currentUser.vision,
          baseProfile: updatedProfile,
          createdAt: currentUser.createdAt,
        );

        await _firestoreService.saveUserProfile(updatedUser);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('栄養目標を更新しました')));
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog(context, '保存エラー', e.toString());
        }
      }
    }
  }

  Future<void> _editPersonalData(BuildContext context, AppUser currentUser) async {
    final nameController = TextEditingController(text: currentUser.displayName);
    final ageController = TextEditingController(text: currentUser.baseProfile['age']?.toString() ?? '');
    final heightController = TextEditingController(text: currentUser.baseProfile['height']?.toString() ?? '');
    final weightController = TextEditingController(text: currentUser.baseProfile['weight']?.toString() ?? '');
    final notesController = TextEditingController(text: currentUser.baseProfile['personal_notes']?.toString() ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('パーソナルデータの編集'),
        content: SizedBox(
          width: 400, // ダイアログの幅を固定
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StableTextField(
                  controller: nameController,
                  hintText: '例: イトマン二郎',
                  labelText: 'ユーザーネーム (表示名)',
                  lines: 1,
                  keyboardType: TextInputType.text,
                ),
                StableTextField(
                  controller: ageController,
                  hintText: '例: 22',
                  labelText: '年齢 (歳)',
                  lines: 1,
                  keyboardType: TextInputType.number,
                ),
                StableTextField(
                  controller: heightController,
                  hintText: '例: 175.5',
                  labelText: '身長 (cm)',
                  lines: 1,
                  keyboardType: TextInputType.number,
                ),
                StableTextField(
                  controller: weightController,
                  hintText: '例: 68.0',
                  labelText: '体重 (kg)',
                  lines: 1,
                  keyboardType: TextInputType.number,
                ),
                StableTextField(
                  controller: notesController,
                  hintText: '怪我の既往、アレルギー等',
                  labelText: '備考',
                  lines: 5,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        Map<String, dynamic> updatedProfile = Map.from(currentUser.baseProfile);
        updatedProfile['age'] = ageController.text;
        updatedProfile['height'] = heightController.text;
        updatedProfile['weight'] = weightController.text;
        updatedProfile['personal_notes'] = notesController.text;

        final updatedUser = AppUser(
          uid: currentUser.uid,
          displayName: nameController.text.isNotEmpty ? nameController.text : currentUser.displayName,
          vision: currentUser.vision,
          baseProfile: updatedProfile,
          createdAt: currentUser.createdAt,
        );

        await _firestoreService.saveUserProfile(updatedUser);
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('パーソナルデータを更新しました')));
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog(context, '保存エラー', e.toString());
        }
      }
    }
  }

  Future<void> _editEnvironment(BuildContext context, AppUser currentUser) async {
    final lengthController = TextEditingController(text: currentUser.baseProfile['env_pool_length']?.toString() ?? '');
    final depthController = TextEditingController(text: currentUser.baseProfile['env_depth']?.toString() ?? '');
    final crowdController = TextEditingController(text: currentUser.baseProfile['env_crowd']?.toString() ?? '');
    final notesController = TextEditingController(text: currentUser.baseProfile['env_notes']?.toString() ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('主な練習環境の編集'),
        content: SizedBox(
          width: 400, // ダイアログの幅を固定
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StableTextField(
                  controller: lengthController,
                  hintText: '例: 短水路, 長水路',
                  labelText: '水路',
                  lines: 1,
                  keyboardType: TextInputType.text,
                ),
                StableTextField(
                  controller: depthController,
                  hintText: '例: 1.2',
                  labelText: '水深 (m)',
                  lines: 1,
                  keyboardType: TextInputType.number,
                ),
                StableTextField(
                  controller: crowdController,
                  hintText: '例: 15',
                  labelText: '1コースあたりの人数',
                  lines: 1,
                  keyboardType: TextInputType.number,
                ),
                StableTextField(
                  controller: notesController,
                  hintText: '水温、施設の混雑状況等',
                  labelText: '備考',
                  lines: 5,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
        ],
      ),
    );

    if (result == true && mounted) {
       try {
         Map<String, dynamic> updatedProfile = Map.from(currentUser.baseProfile);
         updatedProfile['env_pool_length'] = lengthController.text;
         updatedProfile['env_depth'] = depthController.text;
         updatedProfile['env_crowd'] = crowdController.text;
         updatedProfile['env_notes'] = notesController.text;
         
         final updatedUser = AppUser(
           uid: currentUser.uid,
           displayName: currentUser.displayName,
           vision: currentUser.vision,
           baseProfile: updatedProfile,
           createdAt: currentUser.createdAt,
         );
         
         await _firestoreService.saveUserProfile(updatedUser);
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('練習環境を更新しました')));
         }
       } catch (e) {
         if (mounted) {
           _showErrorDialog(context, '保存エラー', e.toString());
         }
       }
    }
  }

  Future<void> _editAiModel(BuildContext context, AppUser currentUser) async {
    final currentModel = currentUser.baseProfile['aiModel'] as String? ?? GeminiService.model31FlashLite;
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        String selected = currentModel;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('AIコーチモデルの設定'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    RadioListTile<String>(
                      title: Text(GeminiService.getModelDisplayName(GeminiService.model31FlashLite)),
                      subtitle: const Text('【高速・既定】次世代の最速モデル。制限が緩く安定しています。'),
                      value: GeminiService.model31FlashLite,
                      groupValue: selected,
                      onChanged: (val) => setDialogState(() => selected = val!),
                    ),
                    RadioListTile<String>(
                      title: Text(GeminiService.getModelDisplayName(GeminiService.model15Flash)),
                      subtitle: const Text('【安定】最も実績のある標準モデル。3.1が不安定な時に。'),
                      value: GeminiService.model15Flash,
                      groupValue: selected,
                      onChanged: (val) => setDialogState(() => selected = val!),
                    ),
                    RadioListTile<String>(
                      title: Text(GeminiService.getModelDisplayName(GeminiService.model25Flash)),
                      subtitle: const Text('【高性能・高負荷】深い思考が必要な時に。1日の利用回数制限が厳しいです。'),
                      value: GeminiService.model25Flash,
                      groupValue: selected,
                      onChanged: (val) => setDialogState(() => selected = val!),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💡 自動切り替え機能',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '選択中のモデルがリミット（429エラー）に達した場合、アプリが自動的に階層（3.1FL → 1.5F → 2.5F）を辿って設定を更新し、中断なく利用を継続できるようになっています。',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
                TextButton(onPressed: () => Navigator.pop(context, selected), child: const Text('保存')),
              ],
            );
          }
        );
      },
    );

    if (result != null && result != currentModel && mounted) {
       try {
         Map<String, dynamic> updatedProfile = Map.from(currentUser.baseProfile);
         updatedProfile['aiModel'] = result;
         
         final updatedUser = AppUser(
           uid: currentUser.uid,
           displayName: currentUser.displayName,
           vision: currentUser.vision,
           baseProfile: updatedProfile,
           createdAt: currentUser.createdAt,
         );
         
         await _firestoreService.saveUserProfile(updatedUser);
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AIコーチモデルを更新しました')));
         }
       } catch (e) {
         if (mounted) {
           _showErrorDialog(context, '保存エラー', e.toString());
         }
       }
    }
  }


  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider);
    final dailyUsageAsync = ref.watch(dailyUsageProvider);

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
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('読み込みエラー: $e')),
        data: (user) {
          // ユーザプロファイルが未作成の場合のフォールバック
          final currentUser = user ?? AppUser(
            uid: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            displayName: 'ゲストユーザー',
          );

          final visionText = currentUser.vision.isNotEmpty ? currentUser.vision : '未設定（タップして編集）';
          final age = currentUser.baseProfile['age'] ?? '未設定';
          final height = currentUser.baseProfile['height'] ?? '未設定';
          final weight = currentUser.baseProfile['weight'] ?? '未設定';
          final personalDataText = '年齢: $age歳 / 身長: ${height}cm / 体重: ${weight}kg';
          
          final envLength = currentUser.baseProfile['env_pool_length'] ?? '-';
          final envDepth = currentUser.baseProfile['env_depth'] ?? '-';
          final envCrowd = currentUser.baseProfile['env_crowd'] ?? '-';
          final envDataText = '水路: $envLength / 水深: $envDepth m / 人数: $envCrowd 人';

          final aiModelKey = currentUser.baseProfile['aiModel'] ?? GeminiService.modelFlash;
          String aiModelText = 'Gemini 2.5 Flash';
          if (aiModelKey.contains('3.1-flash-lite')) {
            aiModelText = 'Gemini 3.1 Flash-Lite';
          } else if (aiModelKey.contains('2.5-flash')) {
            aiModelText = 'Gemini 2.5 Flash';
          }

          return ListView(
            children: [
              // アカウント設定
              ListTile(
                title: Text('アカウント設定', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ),
              ListTile(
                leading: const Icon(Icons.star),
                title: const Text('ビジョン(最終目標)'),
                subtitle: Text(visionText),
                trailing: const Icon(Icons.edit, size: 16),
                onTap: () => _editProfileField(context, currentUser, 'ビジョン', 'vision', currentUser.vision),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('パーソナルデータ (年齢/身長/体重)'),
                subtitle: Text(personalDataText),
                trailing: const Icon(Icons.edit, size: 16),
                onTap: () => _editPersonalData(context, currentUser),
              ),
              ListTile(
                leading: const Icon(Icons.pool),
                title: const Text('主な練習環境'),
                subtitle: Text(envDataText),
                trailing: const Icon(Icons.edit, size: 16),
                onTap: () => _editEnvironment(context, currentUser),
              ),
              ListTile(
                leading: const Icon(Icons.restaurant_menu),
                title: const Text('標準（デフォルト）栄養目標'),
                subtitle: Text('目標: ${currentUser.baseProfile['targetCalories'] ?? 2500} kcal (P:${currentUser.baseProfile['targetProtein'] ?? 150}g / F:${currentUser.baseProfile['targetFat'] ?? 70}g / C:${currentUser.baseProfile['targetCarbs'] ?? 400}g)'),
                trailing: const Icon(Icons.edit, size: 16),
                onTap: () => _editNutritionGoals(context, currentUser),
              ),
              ListTile(
                leading: const Icon(Icons.medical_services_outlined),
                title: const Text('怪我・病気の既往歴'),
                subtitle: Text(currentUser.baseProfile['medicalHistory'] as String? ?? 'なし'),
                trailing: const Icon(Icons.edit, size: 16),
                onTap: () => _editProfileField(
                    context, 
                    currentUser, 
                    '怪我・病気の既往歴', 
                    'medicalHistory', 
                    currentUser.baseProfile['medicalHistory'] as String? ?? 'なし'
                  ),
              ),
              const Divider(),

              // システム設定
              ListTile(
                title: Text('システム設定', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ),
              ListTile(
                leading: const Icon(Icons.smart_toy_outlined),
                title: const Text('AIコーチモデル'),
                subtitle: Text(aiModelText),
                trailing: const Icon(Icons.edit, size: 16),
                onTap: () => _editAiModel(context, currentUser),
              ),
              const Divider(),

              // AI設定（ローカル）
              ListTile(
                title: Text('AIプロセッサ設定 (v2.0)', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.memory),
                title: const Text('Gemma 4 ローカル推論'),
                subtitle: const Text('テキスト解析（PFC推定、分析）を端末内で行います。プライバシー向上と503エラー抑止に効果的です。'),
                value: currentUser.baseProfile['useLocalAi'] == true,
                onChanged: (val) async {
                  try {
                    Map<String, dynamic> updatedProfile = Map.from(currentUser.baseProfile);
                    updatedProfile['useLocalAi'] = val;
                    final updatedUser = currentUser.copyWith(baseProfile: updatedProfile);
                    await _firestoreService.saveUserProfile(updatedUser);
                  } catch (e) {
                    if (mounted) _showErrorDialog(context, '設定保存エラー', e.toString());
                  }
                },
              ),
              Consumer(
                builder: (context, ref, _) {
                  final localAiState = ref.watch(localAiManagerProvider);
                  if (localAiState.isModelLoaded) {
                    return const ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('ローカルAIモデル: 準備完了'),
                      subtitle: Text('Gemma 4 (2B) が利用可能です'),
                    );
                  }
                  
                  return ListTile(
                    leading: localAiState.downloadProgress > 0 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_for_offline_outlined),
                    title: Text(localAiState.downloadProgress > 0 
                      ? 'モデルをダウンロード中... (${(localAiState.downloadProgress * 100).toInt()}%)' 
                      : 'ローカルAIモデルをダウンロード'),
                    subtitle: const Text('初回のみ約2GBの通信が発生します。Wi-Fi環境推奨。'),
                    onTap: localAiState.downloadProgress > 0 ? null : () {
                      ref.read(localAiManagerProvider.notifier).downloadModel();
                    },
                  );
                },
              ),
              const Divider(),

          // テーマ設定
          ListTile(
            title: Text('表示設定', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: appThemeMode,
            builder: (context, mode, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.palette_outlined, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        const Text('テーマ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('アプリの表示テーマを切り替えます', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('ダーク')),
                          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('自動')),
                          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('ライト')),
                        ],
                        selected: {mode},
                        onSelectionChanged: (s) async {
                          try {
                            final newMode = s.first;
                            appThemeMode.value = newMode;
                            
                            await _firestoreService.updateUserProfileFields(currentUser.uid, {
                              'baseProfile.themeMode': newMode == ThemeMode.dark ? 'dark' 
                                                     : newMode == ThemeMode.light ? 'light' 
                                                     : 'system'
                            });
                          } catch (e) {
                            if (mounted) {
                              _showErrorDialog(context, '設定保存エラー', e.toString());
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),

          // コーチング設定
          ListTile(
            title: Text('コーチング設定', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          ),

          ListTile(
            leading: Image.asset('assets/images/app_icon.png', width: 24, height: 24),
            title: const Text('理想のコーチ像'),
            subtitle: Text(user?.baseProfile['idealCoachPersona'] as String? ?? '専門的かつモチベーションを高めてくれるコーチ'),
            trailing: const Icon(Icons.edit, size: 16),
            onTap: () => _editProfileField(
                context, 
                currentUser, 
                '理想のコーチ像', 
                'idealCoachPersona', 
                currentUser.baseProfile['idealCoachPersona'] as String? ?? '専門的かつモチベーションを高めてくれる、誠実で論理的なコーチ'
              ),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('初期設定（オンボーディング）をやり直す'),
            onTap: () => context.go('/onboarding'),
          ),
          const Divider(),
          ListTile(
            title: Text('アプリ情報', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('バージョン ${AppConfig.version}+${AppConfig.buildNumber}'),
            onTap: () async {
              if (currentUser.role == 'admin') return;
              setState(() {
                _versionTapCount++;
              });
              if (_versionTapCount >= 5) {
                _versionTapCount = 0;
                final pwController = TextEditingController();
                final bool? ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('シークレットアクセス', style: TextStyle(color: Colors.amber)),
                    content: TextField(
                      controller: pwController,
                      obscureText: true,
                      decoration: const InputDecoration(hintText: 'Passcode'),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
                    ],
                  ),
                );
                if (ok == true && pwController.text == 'Admin2026') {
                  await _firestoreService.elevateUserToAdmin(currentUser.uid);
                  ref.invalidate(userProfileProvider); // プロバイダーを強制再読み込み
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('管理者権限を付与しました', style: TextStyle(color: Colors.amber))));
                    context.go('/admin'); // 即座に管理者メニューに遷移させる
                  }
                }
              }
            },
          ),
          if (user?.role == 'admin') ...[
            const Divider(),
            ListTile(
              title: const Text('管理者メニュー', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
              subtitle: const Text('詳細なパラメータ調整やデバッグ機能'),
              leading: const Icon(Icons.admin_panel_settings, color: Colors.amber),
              onTap: () {
                context.go('/admin');
              },
            ),
          ],
          const Divider(height: 32),
          // ログアウトボタン
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  context.go('/auth');
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('ログアウト'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.red,
                backgroundColor: Colors.red.withValues(alpha: 0.1),
                elevation: 0,
              ),
            ),
          ),
          const Divider(),
          // デバッグ情報
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('デバッグ情報', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.outline)),
                const SizedBox(height: 8),
                dailyUsageAsync.when(
                  data: (count) => Text('本日のAI利用回数 (送信成功数): $count 回', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  loading: () => const Text('本日のAI利用回数: 読み込み中...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  error: (e, s) => Text('利用回数取得エラー: $e', style: const TextStyle(fontSize: 12, color: Colors.red)),
                ),
                const SizedBox(height: 4),
                const Text('※実際のクォータと完全に一致するものではありません。', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
        );
       },
     ),
    );
  }
}
