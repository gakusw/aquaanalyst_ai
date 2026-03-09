import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';

class NutritionResult {
  final double protein;
  final double carbs;
  final String reason;
  NutritionResult({required this.protein, required this.carbs, required this.reason});
}

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  String? _apiKey;
  static const String modelPro = 'models/gemini-2.5-pro';
  static const String modelFlash = 'models/gemini-2.5-flash';
  static const String modelFlash20 = 'models/gemini-2.0-flash';

  /// 初期化処理
  void init() {
    _apiKey = dotenv.env['GEMINI_API_KEY'];
    if (_apiKey == null || _apiKey!.isEmpty || _apiKey == 'YOUR_KEY_HERE') {
      debugPrint('Warning: GEMINI_API_KEY is not set or invalid.');
    }
  }

  GenerativeModel? _createModel({
    String? modelId,
    String? systemInstruction,
    String? responseMimeType,
  }) {
    if (_apiKey == null || _apiKey!.isEmpty || _apiKey == 'YOUR_KEY_HERE') return null;
    String effectiveModelId = modelId ?? modelPro;
    // 'models/' プレフィックスがない場合は付与する（古い保存データへの互換性）
    if (!effectiveModelId.startsWith('models/')) {
      effectiveModelId = 'models/$effectiveModelId';
    }

    return GenerativeModel(
      model: effectiveModelId,
      apiKey: _apiKey!,
      systemInstruction: systemInstruction != null ? Content.system(systemInstruction) : null,
      generationConfig: responseMimeType != null ? GenerationConfig(responseMimeType: responseMimeType) : null,
    );
  }

  /// AIへの単発プロンプト送信
  Future<String?> generateContent(String prompt, {String? systemInstruction, String? responseMimeType, String? modelId}) async {
    final model = _createModel(modelId: modelId, systemInstruction: systemInstruction, responseMimeType: responseMimeType);
    if (model == null) return 'AIモデルが初期化されていません。';

    try {
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      return response.text;
    } catch (e) {
      throw Exception(translateError(e, modelId: modelId));
    }
  }

  /// 画像付きでAIへプロンプト送信 (コスト節約のためFlashモデルを推奨)
  Future<String?> generateContentWithImage(
    String prompt,
    Uint8List imageBytes,
    String mimeType, {
    String? systemInstruction,
    String? responseMimeType,
    String? modelId = 'models/gemini-2.5-flash',
  }) async {
    final model = _createModel(modelId: modelId, systemInstruction: systemInstruction, responseMimeType: responseMimeType);
    if (model == null) return 'AIモデルが初期化されていません。';

    try {
      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart(mimeType, imageBytes),
        ])
      ];
      final response = await model.generateContent(content);
      return response.text;
    } catch (e) {
      throw Exception(translateError(e, modelId: modelId));
    }
  }

  /// 食事内容のテキストから栄養素(PFC)を抽出する
  Future<NutritionResult?> analyzeNutrition(String text) async {
    const prompt = """
入力された食事内容（商品名、メニュー名、分量など）から、タンパク質と炭水化物の摂取量を5段階で推定し、JSON形式で回答してください。
5段階評価の基準：
1: 極めて少ない / なし
2: 少ない
3: 普通
4: 多い
5: 極めて多い（アスリートの1食分として十分以上）

【回答形式 (JSON)】
{
  "protein": 1〜5の数値,
  "carbs": 1〜5の数値,
  "reason": "その数値にした理由（簡潔に）"
}
""";

    try {
      final response = await generateContent(
        "内容: $text\n\n$prompt",
        modelId: modelFlash,
        responseMimeType: 'application/json',
      );

      if (response == null || response.isEmpty) return null;
      final data = Map<String, dynamic>.from(jsonDecode(response));
      return NutritionResult(
        protein: (data['protein'] as num).toDouble(),
        carbs: (data['carbs'] as num).toDouble(),
        reason: data['reason'] ?? '',
      );
    } catch (e) {
      debugPrint('Nutrition Analysis Error: $e');
      return null;
    }
  }

  /// チャットセッション（履歴保持）を開始する
  ChatSession startChat({String? systemInstruction, List<Content>? history, String? modelId}) {
    final model = _createModel(modelId: modelId, systemInstruction: systemInstruction);
    if (model == null) {
      throw Exception('AIモデルが初期化されていません。');
    }
    return model.startChat(history: history);
  }

  /// エラーメッセージを日本語に翻訳する
  String translateError(dynamic e, {String? modelId}) {
    final errorStr = e.toString();
    final modelName = modelId ?? modelPro;
    debugPrint('Gemini API Error details ($modelName): $errorStr');

    if (errorStr.contains('Quota exceeded') || errorStr.contains('429')) {
      return 'AIの利用制限（1日、または1分間あたりの回数上限）に達しました。モデル: $modelName\n1.5 Pro/3.1 Proなどの高性能モデルは無料枠が非常にタイトです。1〜2分待ってからお試しいただくか、設定画面で「Flash（軽量版）」に切り替えることをお勧めします。';
    }
    if (errorStr.contains('not found') || errorStr.contains('404')) {
      return '指定されたAIモデル ($modelName) が見つかりません。最新のモデルIDを確認してください。';
    }
    if (errorStr.contains('User Location is not supported')) {
      return 'お住いの地域ではこのAIモデル ($modelName) の利用が制限されています。';
    }
    if (errorStr.contains('Safety') || errorStr.contains('HARM_CATEGORY')) {
      return 'AIが不適切な内容と判断したため、回答を生成できませんでした。';
    }
    
    return '通信エラーが発生しました ($modelName)。時間を置いてから再度お試しください。';
  }
}
