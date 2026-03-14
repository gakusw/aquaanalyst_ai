import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import 'firestore_service.dart';
import 'prompt_defaults.dart';

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
  static const String model15Flash = 'gemini-1.5-flash';
  static const String model25Flash = 'gemini-2.5-flash';
  static const String model31FlashLite = 'gemini-3.1-flash-lite-preview';

  static const String modelFlash = model25Flash; 
  static const String modelPro = model15Pro;
  static const String modelForChat = model31FlashLite;
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
    final vision = user.baseProfile['vision'] ?? '未設定';
    final expertise = user.baseProfile['expertiseLevel'] ?? '一般';
    final persona = user.baseProfile['idealCoachPersona'] ?? '誠実で論理的';

    return """
$base

【現在のコーチング対象（ユーザー情報）】
- 目指す姿/目標: $vision
- 競技レベル/専門性: $expertise
- ユーザーが求めるコーチの雰囲気: $persona

${supplementaryContext != null ? '【追加の分析指針】\n$supplementaryContext' : ''}
""";
  }

  /// 食事内容のテキストから栄養素(PFC)を抽出する
  Future<NutritionResult?> analyzeNutrition(String text, {String? modelId}) async {
    final systemInst = await nutritionAnalysisInstruction;
    const userPrompt = "以下のアスリートの食事を分析し、控えめに見積もってください:\n";

    try {
      final response = await generateContent(
        "$userPrompt$text",
        systemInstruction: systemInst,
        modelId: modelId ?? modelForNutrition,
        responseMimeType: 'application/json',
      );

      if (response != null) {
        final data = json.decode(response);
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
      if (response != null) return json.decode(response);
    } catch (e) {
      debugPrint('Swimming Analysis Error: $e');
    }
    return null;
  }

  /// エラーメッセージの翻訳・整形
  String translateError(dynamic e, {String? modelId}) {
    final errStr = e.toString();
    if (errStr.contains('quota')) {
      return 'AIの利用制限に達しました。しばらく待ってから再度お試しいただくか、管理者メニューでモデルを切り替えてください。';
    }
    if (errStr.contains('api_key')) {
      return 'APIキーが正しく設定されていません。';
    }
    return 'エラーが発生しました: $errStr';
  }
}
