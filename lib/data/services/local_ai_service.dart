import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'ai_service.dart';
import '../models/app_user.dart';
import '../models/nutrition_result.dart';
import '../models/my_product.dart';

@JS('window.gemmaBridge')
external JSObject get _gemmaBridge;

@JS('window.gemmaBridge.initModel')
external JSPromise<JSBoolean> _initModel(JSString modelPath);

@JS('window.gemmaBridge.generateText')
external JSPromise<JSString> _generateText(JSString prompt);

/// ローカルAI (Gemma 4) をJS Bridge経由で操作するサービス
class LocalAiService implements AIService {
  static const String modelUrl = 'https://storage.googleapis.com/aquaanalyst-ai-models/gemma4-2b-it-gpu.bin';

  Future<bool> initialize() async {
    try {
      final result = await _initModel(modelUrl.toJS).toDart;
      return result.toDart;
    } catch (e) {
      debugPrint('Local AI Init Error: $e');
      return false;
    }
  }

  @override
  Future<String?> generateContent(String prompt, {String? modelId, String? responseMimeType, String? userId, String? systemInstruction}) async {
    try {
      final jsResponse = await _generateText(prompt.toJS).toDart;
      return jsResponse.toDart;
    } catch (e) {
      debugPrint('Local AI Inference Error: $e');
      rethrow;
    }
  }

  @override
  Future<String?> generateContentWithImage(String prompt, Uint8List imageBytes, String mimeType, {String? modelId, String? responseMimeType, String? userId, String? systemInstruction}) async {
    // 2026年時点では、軽量版GemmaのVision推論はブラウザ上で非常に重いため、
    // 画像解析は現在未サポートとしてエラーを返します（将来的に対応予定、現在はクラウドへフォールバックされる）
    throw UnsupportedError('Local Vision analysis is not yet supported in browser environment. Please use Cloud mode.');
  }

  @override
  Future<NutritionResult?> analyzeNutrition(String text, {String? modelId, List<MyProduct>? myProducts, String? userId}) async {
    throw UnsupportedError('Local Nutrition estimation is not yet supported. Please use Cloud mode.');
  }

  @override
  Future<NutritionResult?> analyzeNutritionFromImage(Uint8List imageBytes, String mimeType, {String? modelId, List<MyProduct>? myProducts, String? userId}) async {
    throw UnsupportedError('Local Nutrition vision analysis is not yet supported. Please use Cloud mode.');
  }

  @override
  Future<Map<String, dynamic>?> analyzeSwimmingAnalysisSheet(Uint8List imageBytes, String mimeType) async {
    throw UnsupportedError('Local Swimming sheet analysis is not yet supported. Please use Cloud mode.');
  }

  // --- インストラクション取得用 (Persona / System Instruction) ---
  
  @override
  Future<String> getCoachSystemInstruction(AppUser user, {String? supplementaryContext}) async => "";
  
  @override
  Future<String> get nutritionistSystemInstruction async => "";
  
  @override
  Future<String> get insightGuidelineInstruction async => "";
  
  @override
  Future<String> get insightPredictionInstruction async => "";
  
  @override
  Future<String> get weeklyPlanInstruction async => "";

  @override
  dynamic startChat({List<dynamic>? history, String? systemInstruction, String? modelId}) {
    throw UnsupportedError('Local Chat sessions are not yet supported. Please use Cloud mode.');
  }
}
