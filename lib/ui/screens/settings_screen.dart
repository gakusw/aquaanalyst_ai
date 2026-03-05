import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:aquaanalyst_ai/main.dart' show appThemeMode;
import '../../data/services/firestore_service.dart';
import '../../data/models/app_user.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late final Stream<AppUser?> _userProfileStream;
  double _expertiseLevel = 5.0;
  bool _isDraggingExpertise = false; // ドラッグ中の上書き防止フラグ

  @override
  void initState() {
    super.initState();
    _userProfileStream = _firestoreService.getUserProfileStream();
    
    // アプリ起動時のテーマ同期
    _firestoreService.getUserProfileStream().first.then((user) {
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
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: '新しい $title を入力'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );

    if (newValue != null && newValue != currentValue && mounted) {
      // モデルをコピーして更新
      Map<String, dynamic> updatedProfile = Map.from(currentUser.baseProfile);
      String updatedVision = currentUser.vision;
      String updatedDisplayName = currentUser.displayName;

      if (fieldKey == 'vision') {
        updatedVision = newValue;
      } else if (fieldKey == 'displayName') {
        updatedDisplayName = newValue;
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
    }
  }

  Future<void> _editPersonalData(BuildContext context, AppUser currentUser) async {
    final ageController = TextEditingController(text: currentUser.baseProfile['age']?.toString() ?? '');
    final heightController = TextEditingController(text: currentUser.baseProfile['height']?.toString() ?? '');
    final weightController = TextEditingController(text: currentUser.baseProfile['weight']?.toString() ?? '');
    final notesController = TextEditingController(text: currentUser.baseProfile['personal_notes']?.toString() ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('パーソナルデータの編集'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ageController, decoration: const InputDecoration(labelText: '年齢 (歳)'), keyboardType: TextInputType.number),
              TextField(controller: heightController, decoration: const InputDecoration(labelText: '身長 (cm)'), keyboardType: TextInputType.number),
              TextField(controller: weightController, decoration: const InputDecoration(labelText: '体重 (kg)'), keyboardType: TextInputType.number),
              TextField(controller: notesController, decoration: const InputDecoration(labelText: '備考 (怪我の既往、アレルギー等)'), maxLines: 3),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
        ],
      ),
    );

    if (result == true && mounted) {
      Map<String, dynamic> updatedProfile = Map.from(currentUser.baseProfile);
      updatedProfile['age'] = ageController.text;
      updatedProfile['height'] = heightController.text;
      updatedProfile['weight'] = weightController.text;
      updatedProfile['personal_notes'] = notesController.text;

      final updatedUser = AppUser(
        uid: currentUser.uid,
        displayName: currentUser.displayName,
        vision: currentUser.vision,
        baseProfile: updatedProfile,
        createdAt: currentUser.createdAt,
      );

      await _firestoreService.saveUserProfile(updatedUser);
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('パーソナルデータを更新しました')));
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: lengthController, decoration: const InputDecoration(labelText: '水路 (例: 短水路, 長水路)'), keyboardType: TextInputType.text),
              TextField(controller: depthController, decoration: const InputDecoration(labelText: '水深 (m)'), keyboardType: TextInputType.number),
              TextField(controller: crowdController, decoration: const InputDecoration(labelText: '1コースあたりの人数'), keyboardType: TextInputType.number),
              TextField(controller: notesController, decoration: const InputDecoration(labelText: '備考 (水温、施設の混雑状況等)'), maxLines: 3),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
        ],
      ),
    );

    if (result == true && mounted) {
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
    }
  }

  Future<void> _editAiModel(BuildContext context, AppUser currentUser) async {
    final currentModel = currentUser.baseProfile['aiModel'] as String? ?? 'Gemini 2.5 Flash';
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
                     title: const Text('Gemini 2.5 Flash'),
                     subtitle: const Text('高速でバランスの取れた標準モデル'),
                     value: 'Gemini 2.5 Flash',
                     groupValue: selected,
                     onChanged: (val) => setDialogState(() => selected = val!),
                   ),
                   RadioListTile<String>(
                     title: const Text('Gemini 3.1 Pro'),
                     subtitle: const Text('高度な推論と厳格なアプローチ'),
                     value: 'Gemini 3.1 Pro',
                     groupValue: selected,
                     onChanged: (val) => setDialogState(() => selected = val!),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: StreamBuilder<AppUser?>(
        stream: _userProfileStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data;
          
          // Firestoreの値でローカル状態を同期
          if (user != null && !_isDraggingExpertise) {
            final savedLevel = (user.baseProfile['expertiseLevel'] as num?)?.toDouble();
            if (savedLevel != null && savedLevel != _expertiseLevel) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_isDraggingExpertise) setState(() => _expertiseLevel = savedLevel);
              });
            }
          }
          
          // 表示用の仮データまたはFirestoreのデータ
          final visionText = user?.vision?.isNotEmpty == true ? user!.vision : '未設定（タップして編集）';
          final age = user?.baseProfile['age'] ?? '未設定';
          final height = user?.baseProfile['height'] ?? '未設定';
          final weight = user?.baseProfile['weight'] ?? '未設定';
          final personalDataText = '年齢: $age歳 / 身長: ${height}cm / 体重: ${weight}kg';
          
          final envLength = user?.baseProfile['env_pool_length'] ?? '-';
          final envDepth = user?.baseProfile['env_depth'] ?? '-';
          final envCrowd = user?.baseProfile['env_crowd'] ?? '-';
          final envDataText = '水路: $envLength / 水深: $envDepth m / 人数: $envCrowd 人';

          final aiModelText = user?.baseProfile['aiModel'] ?? 'Gemini 2.5 Flash';

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
                onTap: () {
                  if (user != null) _editProfileField(context, user, 'ビジョン', 'vision', user.vision);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('パーソナルデータ (年齢/身長/体重)'),
                subtitle: Text(personalDataText),
                trailing: const Icon(Icons.edit, size: 16),
                onTap: () {
                  if (user != null) {
                    _editPersonalData(context, user);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.pool),
                title: const Text('主な練習環境'),
                subtitle: Text(envDataText),
                trailing: const Icon(Icons.edit, size: 16),
                onTap: () {
                  if (user != null) {
                    _editEnvironment(context, user);
                  }
                },
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
                onTap: () {
                  if (user != null) {
                    _editAiModel(context, user);
                  }
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
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Row(
                  children: [
                    const Icon(Icons.palette_outlined),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('テーマ', style: TextStyle(fontSize: 16)),
                          Text('アプリの表示テーマを切り替えます', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('ダーク')),
                        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('自動')),
                        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('ライト')),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) async {
                        final newMode = s.first;
                        appThemeMode.value = newMode;
                        if (user != null) {
                          Map<String, dynamic> updatedProfile = Map.from(user.baseProfile);
                          updatedProfile['themeMode'] = newMode == ThemeMode.dark ? 'dark' 
                                                      : newMode == ThemeMode.light ? 'light' 
                                                      : 'system';
                          final updatedUser = AppUser(
                            uid: user.uid,
                            displayName: user.displayName,
                            vision: user.vision,
                            baseProfile: updatedProfile,
                            createdAt: user.createdAt,
                          );
                          await _firestoreService.saveUserProfile(updatedUser);
                        }
                      },
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.psychology, color: Colors.grey),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('専門性要求レベル', style: TextStyle(fontSize: 16)),
                      Text(
                        _expertiseLevel <= 3 ? '1: 初心者向き（平易な解説）'
                            : _expertiseLevel <= 6 ? '中級者向き（実践的なアドバイス）'
                            : _expertiseLevel <= 8 ? '上級者向き（科学的な視点を含む）'
                            : '10: トップスイマー向き（最新研究ベース）',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Text(_expertiseLevel.round().toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          Slider(
            value: _expertiseLevel,
            min: 1, max: 10, divisions: 9,
            onChanged: (val) {
              setState(() {
                _expertiseLevel = val;
                _isDraggingExpertise = true;
              });
            },
            onChangeEnd: (val) async {
              setState(() => _isDraggingExpertise = false);
              if (user != null) {
                Map<String, dynamic> updatedProfile = Map.from(user.baseProfile);
                updatedProfile['expertiseLevel'] = val;
                final updatedUser = AppUser(
                  uid: user.uid,
                  displayName: user.displayName,
                  vision: user.vision,
                  baseProfile: updatedProfile,
                  createdAt: user.createdAt,
                );
                await _firestoreService.saveUserProfile(updatedUser);
              }
            },
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
            title: const Text('バージョン 1.0.0 (Prototype)'),
            onTap: () {},
          ),
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
                backgroundColor: Colors.red.withOpacity(0.1),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
        );
      }),
    );
  }
}
