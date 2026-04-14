import 'package:flutter/foundation.dart';

/// アプリ全体の共通設定およびバージョン管理を行う
class AppConfig {
  static const String version = '3.0.0';
  static const int buildNumber = 23;

  /// ローカルAI (Gemma 4) のデフォルト設定
  static const bool defaultLocalAiEnabled = false;
  static const String defaultLocalModelSize = '2B'; // 2B or 4B

  /// AIのリトライ回数
  static const int maxAiRetries = 3;

  /// WebGPUが利用可能かどうかを確認（ブラウザ環境のみ）
  static bool get isWebGPUSupported {
    if (!kIsWeb) return false;
    // 注: 実際には JavaScript Bridge を通じて判定する
    return true; 
  }
}
