import 'dart:typed_data';
import 'ai_service.dart';
import 'gemini_service.dart';
import 'local_ai_service.dart';
import '../models/app_user.dart';
import '../models/nutrition_result.dart';
import '../models/my_product.dart';

/// ローカルとクラウドを賢く使い分けるハイブリッドAIサービス
class HybridAiService implements AIService {
  final GeminiService _cloudService = GeminiService();
  final LocalAiService _localService = LocalAiService();
  final bool useLocalForText;

  HybridAiService({this.useLocalForText = false});

  @override
  Future<String?> generateContent(
    String prompt, {
    String? modelId,
    String? responseMimeType,
    String? userId,
    String? systemInstruction,
  }) async {
    // ユーザー設定でローカルが有効な場合、テキスト生成はローカルを優先
    if (useLocalForText) {
      try {
        return await _localService.generateContent(
          prompt, 
          modelId: modelId, 
          responseMimeType: responseMimeType, 
          userId: userId,
          systemInstruction: systemInstruction,
        );
      } catch (e) {
        // ローカルでの推論に失敗（未初期化、リソース不足等）した場合はクラウドへ自動フォールバック
        return await _cloudService.generateContent(
          prompt, 
          modelId: modelId, 
          responseMimeType: responseMimeType, 
          userId: userId,
          systemInstruction: systemInstruction,
        );
      }
    }

    // デフォルトはクラウド
    return await _cloudService.generateContent(
      prompt, 
      modelId: modelId, 
      responseMimeType: responseMimeType, 
      userId: userId,
      systemInstruction: systemInstruction,
    );
  }

  @override
  Future<String?> generateContentWithImage(
    String prompt,
    Uint8List imageBytes,
    String mimeType, {
    String? modelId,
    String? responseMimeType,
    String? userId,
    String? systemInstruction,
  }) async {
    // 画像解析は常に Cloud (Gemini) を使用する
    return await _cloudService.generateContentWithImage(
      prompt,
      imageBytes,
      mimeType,
      modelId: modelId,
      responseMimeType: responseMimeType,
      userId: userId,
      systemInstruction: systemInstruction,
    );
  }

  @override
  Future<NutritionResult?> analyzeNutrition(
    String text, {
    String? modelId, 
    List<MyProduct>? myProducts, 
    String? userId
  }) async {
    // 栄養素推定（テキスト）は現時点でクラウドでの精度が高いためクラウドへルーティング
    return await _cloudService.analyzeNutrition(
      text, 
      modelId: modelId, 
      myProducts: myProducts, 
      userId: userId
    );
  }

  @override
  Future<NutritionResult?> analyzeNutritionFromImage(
    Uint8List imageBytes, 
    String mimeType, {
    String? modelId, 
    List<MyProduct>? myProducts, 
    String? userId
  }) async {
    // 画像からの栄養素推定は常にクラウド
    return await _cloudService.analyzeNutritionFromImage(
      imageBytes,
      mimeType,
      modelId: modelId,
      myProducts: myProducts,
      userId: userId,
    );
  }

  @override
  Future<Map<String, dynamic>?> analyzeSwimmingAnalysisSheet(
    Uint8List imageBytes, 
    String mimeType
  ) async {
    // 泳法解析（OCR/JSON）は常にクラウド
    return await _cloudService.analyzeSwimmingAnalysisSheet(
      imageBytes,
      mimeType,
    );
  }

  // --- インストラクション取得用 (Persona / System Instruction) ---
  
  @override
  Future<String> getCoachSystemInstruction(AppUser user, {String? supplementaryContext}) async {
    return await _cloudService.getCoachSystemInstruction(user, supplementaryContext: supplementaryContext);
  }

  @override
  Future<String> get nutritionistSystemInstruction async => await _cloudService.nutritionistSystemInstruction;

  @override
  Future<String> get insightGuidelineInstruction async => await _cloudService.insightGuidelineInstruction;

  @override
  Future<String> get insightPredictionInstruction async => await _cloudService.insightPredictionInstruction;

  @override
  Future<String> get weeklyPlanInstruction async => await _cloudService.weeklyPlanInstruction;

  @override
  dynamic startChat({List<dynamic>? history, String? systemInstruction, String? modelId}) {
    // チャットセッションは状態管理が必要なため、現在はクラウド版を返します
    return _cloudService.startChat(
      history: history,
      systemInstruction: systemInstruction,
      modelId: modelId,
    );
  }
}
