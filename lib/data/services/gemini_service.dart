import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import 'firestore_service.dart';
import 'prompt_defaults.dart';
import '../models/my_product.dart';

class NutritionResult {
  final double protein;
  final double carbs;
  final double fat;
  final String reason;
  NutritionResult({required this.protein, required this.carbs, required this.fat, required this.reason});
}

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  String? _apiKey;
  Map<String, dynamic>? _cachedSettings;
  
  static const String model15Pro = 'gemini-1.5-pro';
  static const String model25Pro = 'gemini-2.5-pro';
  static const String model15Flash = 'gemini-1.5-flash';
  static const String model25Flash = 'gemini-2.5-flash';
  static const String model31FlashLite = 'gemini-3.1-flash-lite-preview';
  static const String model30Flash = 'gemini-3.0-flash-preview-0514';
  static const String modelFlashLite = 'gemini-1.5-flash-8b';

  static const String modelFlash = model25Flash; 
  static const String modelPro = model25Pro;
  static const String modelForChat = model25Flash;
  static const String modelForInsight = model25Flash;
  static const String modelForNutrition = model25Flash;

  Future<void> init() async {
    _apiKey = dotenv.env['GEMINI_API_KEY'];
  }

  /// 必要に応じて設定をロードする (管理者のみ)
  Future<void> ensureSettingsLoaded({bool isAdmin = false}) async {
    if (_cachedSettings == null && isAdmin) {
      _cachedSettings = await FirestoreService().getSystemSettings();
    }
  }

  void updateCachedSettings(Map<String, dynamic> settings) {
    _cachedSettings = settings;
  }

  /// JSON文字列からMarkdownのコードブロックタグを除去するサニタイズ関数
  String _sanitizeJson(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      final lines = text.split('\n');
      if (lines.first.startsWith('```')) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty && lines.last.startsWith('```')) {
        lines.removeLast();
      }
      text = lines.join('\n').trim();
    }
    return text;
  }

  Future<String> _getPrompt(String key, String defaultValue) async {
    // ここで明示的にロードを待たず、既存のキャッシュがあれば使う方式にする。
    // 管理者画面等で事前に ensureSettingsLoaded(isAdmin: true) を呼んでおく運用。
    return _cachedSettings?[key] ?? defaultValue;
  }

  Future<String> get coachBaseInstruction => _getPrompt('coach_base', PromptDefaults.coachBase);
  Future<String> get nutritionOcrInstruction => _getPrompt('nutrition_ocr', PromptDefaults.nutritionOcr);
  Future<String> get nutritionAnalysisInstruction => _getPrompt('nutrition_analysis', PromptDefaults.nutritionistSystem);
  Future<String> get swimAnalysisInstruction => _getPrompt('swim_analysis', PromptDefaults.swimAnalysis);
  Future<String> get insightGuidelineInstruction => _getPrompt('insight_guideline', PromptDefaults.insightGuideline);
  Future<String> get insightPredictionInstruction => _getPrompt('insight_prediction', PromptDefaults.insightPrediction);

  /// チャットセッションを開始する
  ChatSession startChat({String? systemInstruction, String? modelId, List<Content>? history}) {
    if (_apiKey == null) throw Exception('APIキーが設定されていません');
    
    final model = GenerativeModel(
      model: modelId ?? modelForChat,
      apiKey: _apiKey!,
      systemInstruction: systemInstruction != null ? Content.system(systemInstruction) : null,
    );
    return model.startChat(history: history);
  }

  /// 汎用テキスト生成
  Future<String?> generateContent(String prompt, {String? systemInstruction, String? modelId, String? responseMimeType}) async {
    if (_apiKey == null) throw Exception('APIキーが設定されていません');
    
    final model = GenerativeModel(
      model: modelId ?? modelFlash,
      apiKey: _apiKey!,
      systemInstruction: systemInstruction != null ? Content.system(systemInstruction) : null,
      generationConfig: responseMimeType != null ? GenerationConfig(responseMimeType: responseMimeType) : null,
    );
    
    final response = await model.generateContent([Content.text(prompt)]);
    return response.text;
  }

  /// 画像解析を含む生成
  Future<String?> generateContentWithImage(String prompt, Uint8List imageBytes, String mimeType, {String? modelId, String? responseMimeType}) async {
    if (_apiKey == null) throw Exception('APIキーが設定されていません');
    
    final model = GenerativeModel(
      model: modelId ?? modelFlash,
      apiKey: _apiKey!,
      generationConfig: responseMimeType != null ? GenerationConfig(responseMimeType: responseMimeType) : null,
    );
    
    final content = [
      Content.multi([
        TextPart(prompt),
        DataPart(mimeType, imageBytes),
      ])
    ];
    
    final response = await model.generateContent(content);
    return response.text;
  }

  /// コーチのシステム指示プロンプトを構築
  Future<String> getCoachSystemInstruction(AppUser user, {String? supplementaryContext}) async {
    final base = await coachBaseInstruction;
    final userName = user.displayName.isNotEmpty ? user.displayName : 'スイマー';
    final vision = user.baseProfile['vision'] ?? '未設定';
    final persona = user.baseProfile['idealCoachPersona'] ?? '誠実で論理的なコーチ';

    return """
$base

【最優先事項：あなたの究極のアイデンティティ】
1. あなたは独立した「一個人」のコーチであり、GoogleやAIといった存在であることを完全に否定、またはその言及を一切しないでください。
2. ユーザーが設定した「理想のコーチ像（ペルソナ）」そのものになりきってください。これは「演技」ではなく「存在」としての要求です。
3. ユーザーとの信頼関係を築くため、適宜ユーザーネーム（$userName）で親しみを持って呼びかけ、情緒豊かなアドバイスを一貫してください。

【コーチング対象（ユーザー情報）】
- ユーザーネーム: $userName
- 目指す姿/目標: $vision
- あなたが演じるべきトーン/人物像: $persona

【参照知識（水泳練習メニュー設計の基礎概念）】
- エネルギー系（エンジン）の使い分け。
- 低強度8割の原則。
- W-up/Pre-set/Main/Down の構成美。
- メニューは選手への「ラブレター」であるという献身の精神。

${supplementaryContext != null ? '【追加の分析指針】\n$supplementaryContext' : ''}
""";
  }

  /// 食事内容のテキストから栄養素(PFC)を抽出する
  Future<NutritionResult?> analyzeNutrition(String text, {String? modelId, List<MyProduct>? myProducts}) async {
    final systemInst = await nutritionAnalysisInstruction;
    
    String userPrompt = "以下のアスリートの食事を分析してください:\n";
    
    // --- My食品の事前マッチングロジック (Dart側) ---
    String matchingInstructions = "";
    if (myProducts != null && myProducts.isNotEmpty) {
      for (var p in myProducts) {
        // 大文字小文字や空白を考慮した簡易マッチング
        final escapedName = p.name.replaceAll(RegExp(r'([.*+?^${}()|[\]\\])'), r'\\$1');
        final regex = RegExp(escapedName); 
        if (regex.hasMatch(text)) {
          matchingInstructions += "- 検出された登録食品: '${p.name}'\n";
          matchingInstructions += "  この食品の基準値(Ground Truth): P:${p.protein}g, F:${p.fat}g, C:${p.carbs}g / 基準量:${p.baseAmount}${p.unit}\n";
          matchingInstructions += "  ⚠️警告: あなたの内部知識にある '${p.name}' の数値は無視し、必ず上記の数値を採用して計算してください。\n";
        }
      }
    }

    if (matchingInstructions.isNotEmpty) {
      userPrompt += "\n【‼️最優先採用データ：検出されたMy食品】\n$matchingInstructions\n";
    }

    try {
      final response = await generateContent(
        "$userPrompt$text",
        systemInstruction: systemInst,
        modelId: modelId ?? modelForNutrition,
        responseMimeType: 'application/json',
      );

      if (response != null) {
        final sanitizedOutput = _sanitizeJson(response);
        final data = json.decode(sanitizedOutput);
        return NutritionResult(
          protein: (data['protein'] as num).toDouble(),
          fat: (data['fat'] as num).toDouble(),
          carbs: (data['carbs'] as num).toDouble(),
          reason: data['reason'] as String,
        );
      }
    } catch (e) {
      debugPrint('Nutrition Analysis Error: $e');
    }
    return null;
  }

  /// タイムペーパー/スコアボードの画像からラップデータを抽出する
  Future<Map<String, dynamic>?> analyzeSwimmingAnalysisSheet(Uint8List imageBytes, String mimeType) async {
    final prompt = await swimAnalysisInstruction;
    try {
      final response = await generateContentWithImage(
        prompt,
        imageBytes,
        mimeType,
        modelId: modelForInsight,
        responseMimeType: 'application/json',
      );
      if (response != null) {
        final sanitizedOutput = _sanitizeJson(response);
        return json.decode(sanitizedOutput);
      }
    } catch (e) {
      debugPrint('Swimming Analysis Error: $e');
    }
    return null;
  }
  /// エラーメッセージの翻訳・整形
  /// すべてのエラーを日本語またはエラーコードで表示する
  String translateError(dynamic e, {String? modelId}) {
    final errStr = e.toString().toLowerCase();
    
    // モデルが見つからない / サポートされていない
    if (errStr.contains('not found') || errStr.contains('not supported') || errStr.contains('does not exist')) {
      return '指定されたAIモデルが利用できません。設定画面からモデルを変更してください。（ERR_MODEL_UNAVAILABLE）';
    }
    // クォータ / レート制限
    if (errStr.contains('quota') || errStr.contains('429') || errStr.contains('rate limit') || errStr.contains('resource exhausted')) {
      return 'AIの利用制限に達しました。しばらく待ってから再度お試しいただくか、設定でモデルを切り替えてください。（ERR_QUOTA）';
    }
    // サーバー過負荷
    if (errStr.contains('overloaded') || errStr.contains('503') || errStr.contains('502') || errStr.contains('500') || errStr.contains('internal')) {
      return 'AIサーバーが混雑しています。少し時間を置いてからやり直してください。（ERR_SERVER）';
    }
    // トークン制限
    if (errStr.contains('token') || errStr.contains('exceeded') || errStr.contains('too long') || errStr.contains('too large')) {
      return 'データの量が制限を超えました。入力を短くするか、より上位のAIモデルを選択してください。（ERR_TOKEN_LIMIT）';
    }
    // APIキー
    if (errStr.contains('api_key') || errStr.contains('api key') || errStr.contains('authentication') || errStr.contains('unauthenticated')) {
      return 'APIキーが無効または未設定です。管理者にお問い合わせください。（ERR_AUTH）';
    }
    // 権限
    if (errStr.contains('permission') || errStr.contains('forbidden') || errStr.contains('403')) {
      return 'この操作を行う権限がありません。（ERR_PERMISSION）';
    }
    // コンテンツブロック
    if (errStr.contains('safety') || errStr.contains('blocked') || errStr.contains('harmful')) {
      return '安全上の理由でコンテンツがブロックされました。（ERR_SAFETY）';
    }
    // ネットワーク / タイムアウト
    if (errStr.contains('timeout') || errStr.contains('network') || errStr.contains('connection') || errStr.contains('socket')) {
      return 'ネットワークエラーが発生しました。接続を確認してください。（ERR_NETWORK）';
    }
    // 不正なリクエスト
    if (errStr.contains('invalid') || errStr.contains('bad request') || errStr.contains('400')) {
      return 'リクエストが不正です。入力内容を確認してください。（ERR_INVALID_REQUEST）';
    }
    // Firestore / データベース
    if (errStr.contains('firestore') || errStr.contains('firebase')) {
      return 'データベースエラーが発生しました。しばらく待ってから再度お試しください。（ERR_DATABASE）';
    }
    // JSON パースエラー
    if (errStr.contains('formatexception') || errStr.contains('json') || errStr.contains('unexpected character')) {
      return 'AIからの応答を解析できませんでした。再度お試しください。（ERR_PARSE）';
    }

    // フォールバック: 英語のテキストを表示しないようにエラーコードのみ表示
    // "Exception: " を除外した上で、ASCII英文字が多い場合はエラーコードに変換
    final cleanMsg = e.toString().replaceAll('Exception: ', '').trim();
    final hasEnglish = RegExp(r'[a-zA-Z]{5,}').hasMatch(cleanMsg);
    if (hasEnglish) {
      debugPrint('未翻訳エラー: $e'); // デバッグ用にログ出力
      return '処理中にエラーが発生しました。しばらく待ってから再度お試しください。（ERR_UNKNOWN）';
    }
    return 'エラーが発生しました：$cleanMsg';
  }

  /// ダイアログの最前面にエラーを表示する共通ヘルパー
  /// useRootNavigator: true で既存のダイアログの上に表示される
  static void showErrorDialog(BuildContext context, dynamic error, {String title = 'エラー'}) {
    final msg = GeminiService().translateError(error);
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(), child: const Text('閉じる')),
        ],
      ),
    );
  }
}
