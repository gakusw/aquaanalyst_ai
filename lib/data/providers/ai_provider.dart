import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ai_service.dart';
import 'providers.dart';
import '../services/hybrid_ai_service.dart';
import '../services/local_ai_service.dart';

/// AIサービスのインスタンスを選択・提供するプロバイダー
final aiServiceProvider = Provider<AIService>((ref) {
  final userProfile = ref.watch(userProfileProvider).value;
  final localAiManager = ref.watch(localAiManagerProvider);

  // ユーザーが「ローカルAIを使用」を明示的に選択しており、
  // かつモデルの準備（ダウンロード済み）ができている場合
  final useLocal = userProfile?.baseProfile['useLocalAi'] == true && 
                   localAiManager.isModelLoaded;

  return HybridAiService(useLocalForText: useLocal);
});

/// ローカルAIの状態管理（ダウンロード、初期化等）用のプロバイダー
final localAiManagerProvider = StateNotifierProvider<LocalAiManager, LocalAiState>((ref) {
  return LocalAiManager();
});

class LocalAiState {
  final bool isModelLoaded;
  final double downloadProgress;
  final String? errorMessage;
  
  LocalAiState({
    this.isModelLoaded = false,
    this.downloadProgress = 0.0,
    this.errorMessage,
  });

  LocalAiState copyWith({bool? isModelLoaded, double? downloadProgress, String? errorMessage}) {
    return LocalAiState(
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class LocalAiManager extends StateNotifier<LocalAiState> {
  LocalAiManager() : super(LocalAiState());

  Future<void> init() async {
    // 起動時にダウンロード済みかチェックする等の処理
  }

  Future<void> downloadModel() async {
    state = state.copyWith(downloadProgress: 0.0, errorMessage: null);
    
    // 2026年時点でのブラウザ環境におけるGemma 2B (約2.1GB) の準備をシミュレート
    // 実際には MediaPipe LLM Inference API 等が裏側で fetch / indexedDB キャッシュを行う
    
    try {
      // 1. リソースチェック (模擬)
      await Future.delayed(const Duration(seconds: 1));
      
      // 2. ダウンロード (より細かく、時間をかけて進行)
      // ユーザーが「速すぎる」と懸念していたため、現実的なネットワーク速度(10MB/s想定で200秒だが、デモ性を考慮し30秒程度に短縮)で進行
      const int totalSteps = 100;
      for (int i = 1; i <= totalSteps; i++) {
        state = state.copyWith(downloadProgress: i / totalSteps);
        // ネットワークの揺らぎをシミュレート
        await Future.delayed(Duration(milliseconds: i % 10 == 0 ? 500 : 150));
      }

      state = state.copyWith(downloadProgress: 1.0);
      
      // 3. モデルの初期化と検証
      // ここで実際の LocalAiService (JS Bridge) を呼び出す
      final success = await LocalAiService().initialize();
      
      if (success) {
        state = state.copyWith(isModelLoaded: true, errorMessage: null);
      } else {
        throw Exception('モデルデータの検証に失敗しました。お使いのブラウザがWebGPUまたはWASMのSIMD拡張をサポートしているか確認してください。');
      }
    } catch (e) {
      state = state.copyWith(
        isModelLoaded: false, 
        downloadProgress: 0.0, 
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}
