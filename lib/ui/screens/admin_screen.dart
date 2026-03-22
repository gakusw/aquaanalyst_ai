import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/firestore_service.dart';
import '../../data/services/gemini_service.dart';
import '../../data/services/prompt_defaults.dart';
import '../../utils/app_colors.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  late TabController _tabController;
  int _currentIndex = 0;
  
  final Map<String, TextEditingController> _controllers = {
    'coach_base': TextEditingController(),
    'nutrition_ocr': TextEditingController(),
    'nutrition_analysis': TextEditingController(),
    'swim_analysis': TextEditingController(),
    'insight_guideline': TextEditingController(),
    'insight_prediction': TextEditingController(),
  };

  final TextEditingController _hourController = TextEditingController();
  String _selectedModel = GeminiService.modelFlash;
  bool _isLoading = true;
  bool _isSaving = false;
  int _totalUsers = 0;
  int _newUsers = 0;
  bool _isMaintenanceMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _currentIndex = _tabController.index);
    });
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _hourController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _firestoreService.getSystemSettings();
      final total = await _firestoreService.getTotalUserCount();
      final newU = await _firestoreService.getNewUserCountThisWeek();
      setState(() {
        _totalUsers = total;
        _newUsers = newU;
        _isMaintenanceMode = settings['maintenance_mode'] ?? false;

        _setControllerText('coach_base', settings['coach_base'], PromptDefaults.coachBase);
        _setControllerText('nutrition_ocr', settings['nutrition_ocr'], PromptDefaults.nutritionOcr);
        _setControllerText('nutrition_analysis', settings['nutrition_analysis'], PromptDefaults.nutritionistSystem);
        _setControllerText('swim_analysis', settings['swim_analysis'], PromptDefaults.swimAnalysis);
        _setControllerText('insight_guideline', settings['insight_guideline'], PromptDefaults.insightGuideline);
        _setControllerText('insight_prediction', settings['insight_prediction'], PromptDefaults.insightPrediction);

        _hourController.text = (settings['logical_day_start_hour'] ?? 4).toString();
        _selectedModel = settings['default_ai_model'] ?? GeminiService.modelFlash;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading settings: $e');
      setState(() => _isLoading = false);
    }
  }

  void _setControllerText(String key, dynamic savedValue, String defaultValue) {
    if (savedValue == null || (savedValue as String).isEmpty) {
      _controllers[key]!.text = defaultValue;
    } else {
      _controllers[key]!.text = savedValue;
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final hour = int.tryParse(_hourController.text) ?? 4;
      final Map<String, dynamic> dataToSave = {
        'logical_day_start_hour': hour,
        'default_ai_model': _selectedModel,
        'maintenance_mode': _isMaintenanceMode,
        'last_updated': DateTime.now().toIso8601String(),
      };

      _controllers.forEach((key, controller) {
        dataToSave[key] = controller.text;
      });

      await _firestoreService.saveSystemSettings(dataToSave);
      
      // キャッシュも更新
      GeminiService().updateCachedSettings(dataToSave);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('システム設定を保存しました')));
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理者メニュー'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/settings'),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'ダッシュボード'),
            Tab(text: '全般'),
            Tab(text: 'コーチ'),
            Tab(text: '食事OCR'),
            Tab(text: '栄養解析'),
            Tab(text: '水泳解析'),
            Tab(text: '予測指針'),
            Tab(text: '予測詳細'),
          ],
        ),
      ),
      body: _buildCurrentTab(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _saveSettings,
        icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
        label: const Text('設定を保存'),
      ),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0: return _buildDashboardTab();
      case 1: return _buildGeneralTab();
      case 2: return _buildPromptTab('coach_base', 'コーチ基本人格', 'エージェントの基本的な性格、専門知識レベル、行動指針。');
      case 3: return _buildPromptTab('nutrition_ocr', '食事OCR', '画像から料理名と分量を抽出する際の指示。');
      case 4: return _buildPromptTab('nutrition_analysis', '栄養解析', '料理名からPFCバランスを推定する思考プロセス。');
      case 5: return _buildPromptTab('swim_analysis', '分析シート解析', 'タイムペーパーからラップタイムを抽出する指示。');
      case 6: return _buildPromptTab('insight_guideline', 'タイム予測指針', '予測における科学的な制約事項。');
      case 7: return _buildPromptTab('insight_prediction', '予測プロンプト', '予測実行時のメインテンプレート。{swimPbs} 等が置換されます。');
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildDashboardTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('ユーザー統計'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('総ユーザー数', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text('$_totalUsers', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue)),
                  ],
                ),
                Column(
                  children: [
                    const Text('新規登録 (直近7日)', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text('$_newUsers', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.orange)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('緊急設定'),
        Card(
          color: _isMaintenanceMode ? Colors.red.shade50 : null,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('メンテナンスモード', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('オンにすると一般ユーザーはアプリを利用できなくなります。'),
                value: _isMaintenanceMode,
                activeColor: Colors.red,
                onChanged: (val) {
                  setState(() => _isMaintenanceMode = val);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('システムパラメータ'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('日付変更時間 (0-23)'),
                subtitle: const Text('アプリ内の日付が切り替わる基準時間'),
                trailing: SizedBox(
                  width: 60,
                  child: TextField(
                    controller: _hourController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.zero),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('デフォルトAIモデル'),
                subtitle: const Text('標準的な推論に使用するモデル'),
                trailing: DropdownButton<String>(
                  value: _selectedModel,
                  items: [
                    GeminiService.model25Flash,
                    GeminiService.model31FlashLite,
                    GeminiService.model30Flash,
                  ].map((m) => DropdownMenuItem(value: m, child: Text(m.replaceFirst('gemini-', '')))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedModel = val);
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('個人機能のデバッグ'),
                subtitle: const Text('本日のAI推論クォータ管理を強制リセットします。'),
                trailing: ElevatedButton.icon(
                  onPressed: () async {
                    await _firestoreService.clearDailyUsage();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('利用回数をリセットしました')));
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('利用回数リセット'),
                  style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromptTab(String key, String title, String description) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title),
          Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _controllers[key],
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                fillColor: Colors.black12,
                filled: true,
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.skyBlue)),
    );
  }
}
