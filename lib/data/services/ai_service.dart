import 'dart:typed_data';
import '../models/nutrition_result.dart';
import '../models/my_product.dart';
import '../models/app_user.dart';

/// AIサービスの共通インターフェース
abstract class AIService {
  /// テキストからの生成
  Future<String?> generateContent(
    String prompt, {
    String? modelId,
    String? responseMimeType,
    String? userId,
    String? systemInstruction,
  });

  /// 画像を含むテキストからの生成
  Future<String?> generateContentWithImage(
    String prompt,
    Uint8List imageBytes,
    String mimeType, {
    String? modelId,
    String? responseMimeType,
    String? userId,
    String? systemInstruction,
  });

  /// 食事内容のテキストから栄養素(PFC)を抽出する
  Future<NutritionResult?> analyzeNutrition(
    String text, {
    String? modelId, 
    List<MyProduct>? myProducts, 
    String? userId
  });

  /// 食事画像からテキスト(料理内容)と栄養素(PFC)を同時に抽出する
  Future<NutritionResult?> analyzeNutritionFromImage(
    Uint8List imageBytes, 
    String mimeType, {
    String? modelId, 
    List<MyProduct>? myProducts, 
    String? userId
  });

  /// タイムペーパー/スコアボードの画像からラップデータを抽出する
  Future<Map<String, dynamic>?> analyzeSwimmingAnalysisSheet(
    Uint8List imageBytes, 
    String mimeType
  );

  // --- インストラクション取得用 (Persona / System Instruction) ---

  Future<String> getCoachSystemInstruction(AppUser user, {String? supplementaryContext});
  Future<String> get nutritionistSystemInstruction;
  Future<String> get insightGuidelineInstruction;
  Future<String> get insightPredictionInstruction;
  Future<String> get weeklyPlanInstruction;

  /// チャットセッションの開始 (Cloudの場合)
  dynamic startChat({
    List<dynamic>? history, 
    String? systemInstruction, 
    String? modelId
  });
}
