import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'ai_service.dart';
import '../models/app_user.dart';
import '../models/nutrition_result.dart';
import '../models/my_product.dart';
import 'firestore_service.dart';
import 'prompt_defaults.dart';

class GeminiService implements AIService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  String? _apiKey;
  Map<String, dynamic>? _cachedSettings;
  
  static const String model15Pro = 'gemini-1.5-pro';
  static const String model25Pro = 'gemini-2.5-pro';
  static const String model15Flash = 'gemini-1.5-flash';
  static const String model25Flash = 'gemini-2.5-flash';
  static const String model25FlashLite = 'gemini-2.5-flash-lite';
  static const String model31FlashLite = 'gemini-3.1-flash-lite-preview';
  static const String model30Flash = 'gemini-3.0-flash';
  static const String modelFlashLite = 'gemini-1.5-flash-8b';
  static const String model21Flash = 'gemini-2.1-flash';

  static const String modelFlash = model31FlashLite; 
  static const String modelPro = model25Pro;
  
  static const List<String> modelHierarchy = [
    model31FlashLite,
    model25Flash,
    model25FlashLite,
  ];

  static const List<String> availableModels = modelHierarchy;

  static String getModelDisplayName(String id) {
    switch (id) {
      case model31FlashLite: return 'Gemini 3.1 Flash Lite (高速・推奨)';
      case model25Flash: return 'Gemini 2.5 Flash';
      case model25FlashLite: return 'Gemini 2.5 Flash Lite';
      case model15Flash: return 'Gemini 1.5 Flash';
      case model15Pro: return 'Gemini 1.5 Pro';
      default: return id;
    }
  }

  static String getModelDescription(String id) {
    switch (id) {
      case model31FlashLite: return '最新の高速軽量モデル（プレビュー版）。動作が安定しており、第一選択として推奨されます。';
      case model25Flash: return '高いバランス性能を持つ次世代モデル。';
      case model25FlashLite: return 'コストパフォーマンスに優れた次世代軽量モデル。';
      default: return '標準的なGeminiモデル';
    }
  }

  static String get modelForVision => model15Flash;

  Future<void> init([String? key]) async {
    _apiKey = key ?? dotenv.env['GEMINI_API_KEY'];
  }

  bool isRetryableError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('503') || s.contains('504') || s.contains('deadline') || s.contains('timeout') || s.contains('429') || s.contains('quota') || s.contains('unavailable');
  }

  Future<T> _executeWithResilience<T>({
    required Future<T> Function(String) action,
    String? initialModelId,
    String? userId,
    void Function(String)? onModelSwitched,
  }) async {
    int retryCount = 0;
    const int maxRetries = 3;
    String currentModelId = initialModelId ?? modelFlash;

    while (true) {
      try {
        return await action(currentModelId);
      } catch (e) {
        final isRetryable = isRetryableError(e);
        final nextModel = getNextModelInHierarchy(currentModelId);

        if (isRetryable && retryCount < maxRetries) {
          retryCount++;
          final waitSeconds = retryCount * 2; // 2s, 4s, 6s
          debugPrint('Retryable error: $e. Retrying in ${waitSeconds}s (Attempt $retryCount/$maxRetries)...');
          await Future.delayed(Duration(seconds: waitSeconds));
          continue;
        }

        // リトライ上限に達した、またはリトライ不可なエラーの場合にモデル切り替えを試行
        if (nextModel != null && (isRetryable || e.toString().contains('404') || e.toString().toLowerCase().contains('unavailable'))) {
          debugPrint('Switching model from $currentModelId to $nextModel due to error: $e');
          currentModelId = nextModel;
          retryCount = 0; // 新しいモデルでリトライ回数をリセット

          if (userId != null) {
            FirestoreService().updateUserAiModel(userId, nextModel).catchError((_) {});
            onModelSwitched?.call(nextModel);
          }
          continue;
        }

        // これ以上切り替えられない場合は再送
        rethrow;
      }
    }
  }

  @override
  Future<String?> generateContent(String prompt, {String? modelId, String? responseMimeType, String? userId, String? systemInstruction}) async {
    if (_apiKey == null) throw Exception('APIキーが設定されていません');

    return _executeWithResilience(
      initialModelId: modelId,
      userId: userId,
      action: (targetModelId) async {
        final model = GenerativeModel(
          model: targetModelId,
          apiKey: _apiKey!,
          safetySettings: _defaultSafetySettings,
          systemInstruction: systemInstruction != null ? Content.system(systemInstruction) : null,
          generationConfig: responseMimeType != null ? GenerationConfig(responseMimeType: responseMimeType) : null,
        );

        final response = await model.generateContent([Content.text(prompt)]);
        
        final inputT = response.usageMetadata?.promptTokenCount ?? 0;
        final outputT = response.usageMetadata?.candidatesTokenCount ?? 0;
        FirestoreService().incrementGlobalUsage(targetModelId, inputTokens: inputT, outputTokens: outputT);
        
        if (response.text == null || response.text!.trim().isEmpty) {
          throw Exception('生成結果が空でした');
        }
        return response.text;
      },
    );
  }

  @override
  Future<String?> generateContentWithImage(String prompt, Uint8List imageBytes, String mimeType, {String? modelId, String? responseMimeType, String? userId, String? systemInstruction}) async {
    if (_apiKey == null) throw Exception('APIキーが設定されていません');

    return _executeWithResilience(
      initialModelId: modelId,
      userId: userId,
      action: (targetModelId) async {
        final model = GenerativeModel(
          model: targetModelId,
          apiKey: _apiKey!,
          safetySettings: _defaultSafetySettings,
          systemInstruction: systemInstruction != null ? Content.system(systemInstruction) : null,
          generationConfig: responseMimeType != null ? GenerationConfig(responseMimeType: responseMimeType) : null,
        );
        
        final content = [
          Content.multi([
            TextPart(prompt),
            DataPart(mimeType, imageBytes),
          ])
        ];
        
        final response = await model.generateContent(content);
        
        final inputT = response.usageMetadata?.promptTokenCount ?? 0;
        final outputT = response.usageMetadata?.candidatesTokenCount ?? 0;
        FirestoreService().incrementGlobalUsage(targetModelId, inputTokens: inputT, outputTokens: outputT);

        if (response.text == null || response.text!.trim().isEmpty) {
          throw Exception('生成結果が空でした');
        }

        return response.text;
      },
    );
  }

  /// チャットセッションの開始
  @override
  ChatSession startChat({List<dynamic>? history, String? systemInstruction, String? modelId}) {
    if (_apiKey == null) throw Exception('APIキーが設定されていません');
    
    // 型変換 (dynamic -> Content)
    final typedHistory = history?.map((e) => e as Content).toList();

    final model = GenerativeModel(
      model: modelId ?? modelChatDefault,
      apiKey: _apiKey!,
      safetySettings: _defaultSafetySettings,
      systemInstruction: systemInstruction != null ? Content.system(systemInstruction) : null,
    );
    
    return model.startChat(history: typedHistory);
  }

  /// デフォルトのチャットモデルID
  String get modelChatDefault => modelHierarchy.first;

  /// 各種インストラクションへのアクセス用ゲッター
  @override
  Future<String> get nutritionistSystemInstruction async => PromptDefaults.nutritionistSystem;
  @override
  Future<String> get insightGuidelineInstruction async => PromptDefaults.insightGuideline;
  @override
  Future<String> get insightPredictionInstruction async => PromptDefaults.insightPrediction;
  @override
  Future<String> get weeklyPlanInstruction async => PromptDefaults.weeklyPlan;
  
  Future<String> get swimAnalysisInstruction async => PromptDefaults.swimAnalysis;
  Future<String> get nutritionOcrInstruction async => PromptDefaults.nutritionOcr;

  /// コーチのシステム指示プロンプトを構築
  @override
  Future<String> getCoachSystemInstruction(AppUser user, {String? supplementaryContext}) async {
    final userName = user.displayName.isNotEmpty ? user.displayName : 'スイマー';
    final vision = user.vision.isNotEmpty ? user.vision : '未設定';
    final personaValue = user.baseProfile['idealCoachPersona'] as String?;
    final persona = (personaValue != null && personaValue.trim().isNotEmpty) 
        ? personaValue 
        : '専門的かつモチベーションを高めてくれる、誠実で論理的なコーチ';

    return """
【最重要指示：あなたのアイデンティティと口調】
あなたは今この瞬間から、ユーザー（$userName）が設定した**以下の「理想のコーチ像（ペルソナ）」そのもの**としてのみ存在してください。
これまでの会話のトーン、AIとしての標準的な丁寧語、および「競泳コーチングスペシャリスト」といったシステム側の定義よりも、**このペルソナ指定を絶対的な最優先事項**として扱ってください。

【あなたの現在のペルソナ定義（これを100%体現すること）】
$persona

【対話ルール】
1. あなたの回答の「文末」「敬語の有無」「親近感の度合い」は、すべて上記のペルソナ定義に従ってください。
2. ユーザーを必ず現在のユーザー名である**「$userName」**と呼び、設定された人格としての信頼関係を築いてください。過去の履歴で別の名前が呼ばれていても、それは無視して「$userName」を使用し続けてください。
3. あなたがAIであることや、プログラムであることを示唆する表現、または「客観的・標準的なAIのトーン」は一切排除してください。
4. 以前の出力で異なる口調や名前を使っていたとしても、それらは忘れ、**今この瞬間から新しいペルソナと名前に完全に入れ替わってください。**

【現在の目標（ビジョン）】
$vision

${supplementaryContext != null ? '【追加の分析指針】\n$supplementaryContext' : ''}
""";
  }

  /// 食事内容のテキストから栄養素(PFC)を抽出する
  @override
  Future<NutritionResult?> analyzeNutrition(String text, {String? modelId, List<MyProduct>? myProducts, String? userId}) async {
    final systemInst = await nutritionistSystemInstruction;
    
    String userPrompt = "以下のアスリートの食事を分析してください:\n";
    
    String matchingInstructions = "";
    if (myProducts != null && myProducts.isNotEmpty) {
      for (var p in myProducts) {
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
        modelId: modelId,
        responseMimeType: 'application/json',
        userId: userId,
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
      rethrow;
    }
    return null;
  }

  /// 食事画像からテキスト(料理内容)と栄養素(PFC)を同時に抽出する
  @override
  Future<NutritionResult?> analyzeNutritionFromImage(Uint8List imageBytes, String mimeType, {String? modelId, List<MyProduct>? myProducts, String? userId}) async {
    final systemInst = PromptDefaults.nutritionImageAnalyze;
    
    String userPrompt = "以下の食事画像を分析してください:\n";
    
    String dbContext = "";
    if (myProducts != null && myProducts.isNotEmpty) {
      dbContext += "\n【USER_FOOD_DB（My食品リスト）：画像内に該当するものがあればこの数値を適用すること】\n";
      for (var p in myProducts) {
        dbContext += "- '${p.name}' (基準量:${p.baseAmount}${p.unit}) -> P:${p.protein}g, F:${p.fat}g, C:${p.carbs}g\n";
      }
    }
    
    if (dbContext.isNotEmpty) {
      userPrompt += "$dbContext\n";
    }

    try {
      // システムインストラクションは `generateContentWithImage` でサポートされていない場合があるのでプロンプト本体に結合する
      final combinedPrompt = systemInst + "\n\n" + userPrompt;

      final response = await generateContentWithImage(
        combinedPrompt,
        imageBytes,
        mimeType,
        modelId: modelId,
        responseMimeType: 'application/json',
        userId: userId,
      );

      if (response != null) {
        final sanitizedOutput = _sanitizeJson(response);
        final data = json.decode(sanitizedOutput);
        return NutritionResult(
          protein: (data['protein'] as num).toDouble(),
          fat: (data['fat'] as num).toDouble(),
          carbs: (data['carbs'] as num).toDouble(),
          reason: data['reason'] as String,
          description: data['description'] as String?,
        );
      }
    } catch (e) {
      debugPrint('Nutrition Image Analysis Error: $e');
      rethrow;
    }
    return null;
  }

  /// タイムペーパー/スコアボードの画像からラップデータを抽出する
  @override
  Future<Map<String, dynamic>?> analyzeSwimmingAnalysisSheet(Uint8List imageBytes, String mimeType) async {
    final prompt = await swimAnalysisInstruction;
    try {
      final response = await generateContentWithImage(
        prompt,
        imageBytes,
        mimeType,
        modelId: modelForVision,
        responseMimeType: 'application/json',
      );
      if (response != null) {
        final sanitizedOutput = _sanitizeJson(response);
        return json.decode(sanitizedOutput);
      }
    } catch (e) {
      debugPrint('Swimming Analysis Error: $e');
      rethrow;
    }
    return null;
  }

  String _sanitizeJson(String input) {
    String s = input.trim();
    if (s.startsWith('```')) {
      s = s.replaceAll(RegExp(r'^```(json)?\n?'), '');
      s = s.replaceAll(RegExp(r'\n?```$'), '');
    }
    return s.trim();
  }

  /// エラーメッセージの翻訳・整形
  String translateError(dynamic e, {String? modelId}) {
    final errStr = e.toString().toLowerCase();
    
    if (errStr.contains('not found') || errStr.contains('not supported')) {
      return '指定されたAIモデルが利用できません。設定画面からモデルを変更してください。（ERR_MODEL_UNAVAILABLE）';
    }
    if (errStr.contains('quota') || errStr.contains('429') || errStr.contains('rate limit')) {
      return 'AIの利用制限に達しました。しばらく待ってから再度お試しいただくか、設定でモデルを切り替えてください。（ERR_QUOTA）';
    }
    if (errStr.contains('overloaded') || errStr.contains('503') || errStr.contains('500')) {
      return 'AIサーバーが混雑しています。少し時間を置いてからやり直してください。（ERR_SERVER）';
    }
    if (errStr.contains('token') || errStr.contains('too long')) {
      return 'データの量が制限を超えました。（ERR_TOKEN_LIMIT）';
    }
    if (errStr.contains('api_key') || errStr.contains('authentication')) {
      return 'APIキーが無効または未設定です。（ERR_AUTH）';
    }
    if (errStr.contains('safety') || errStr.contains('blocked')) {
      return '安全上の理由でコンテンツがブロックされました。（ERR_SAFETY）';
    }
    if (errStr.contains('timeout') || errStr.contains('network') || errStr.contains('connection')) {
      return 'ネットワークエラーが発生しました。接続を確認してください。（ERR_NETWORK）';
    }

    final cleanMsg = e.toString().replaceAll('Exception: ', '').trim();
    final hasEnglish = RegExp(r'[a-zA-Z]{5,}').hasMatch(cleanMsg);
    if (hasEnglish) {
      debugPrint('未翻訳エラー: $e');
      return '処理中にエラーが発生しました。しばらく待ってから再度お試しください。（ERR_UNKNOWN）';
    }
    return 'エラーが発生しました：$cleanMsg';
  }

  String? getNextModelInHierarchy(String currentId) {
    final index = modelHierarchy.indexOf(currentId);
    if (index != -1 && index < modelHierarchy.length - 1) {
      return modelHierarchy[index + 1];
    }
    return null;
  }

  /// 設定の更新
  void updateCachedSettings(Map<String, dynamic> settings) {
    _cachedSettings = settings;
  }

  /// エラーダイアログの表示
  static void showErrorDialog(BuildContext context, dynamic error, {String title = 'エラー'}) {
    final msg = GeminiService().translateError(error);
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(child: Text(msg)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(), child: const Text('閉じる')),
        ],
      ),
    );
  }

  final List<SafetySetting> _defaultSafetySettings = [
    SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
    SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
    SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
    SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
  ];
}
