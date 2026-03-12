import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';

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
  static const String model15Pro = 'gemini-1.5-pro';
  static const String model15Flash = 'gemini-1.5-flash';
  static const String model15Flash8b = 'gemini-1.5-flash-8b';
  static const String model20Flash = 'gemini-2.0-flash';
  static const String model31Flash = 'gemini-1.5-flash'; // プレビュー版の不安定回避のため1.5を安定版として使用
  static const String model31FlashLite = 'gemini-1.5-flash-8b';
  static const String model20FlashExp = 'gemini-2.0-flash-exp';

  // 下位互換用エイリアス
  static const String modelPro = model15Pro;
  static const String modelFlash = model20Flash; // 2.0 Flashを標準の高速モデルに

  // ユースケース別推奨モデル (コスパ最適化)
  static const String modelForChat = model31Flash;      // 日々のチャット (最新・高速)
  static const String modelForInsight = model15Pro;    // タイム予測・深い分析 (知能優先)
  static const String modelForNutrition = model15Flash8b; // 栄養解析 (格安・データ抽出)

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
    String effectiveModelId = modelId ?? modelFlash;

    // 最新のPreview/Experimentalモデルが503エラー（混雑）を起こす場合、安定版へフォールバック
    if (effectiveModelId.contains('3.1-flash-lite-preview') || effectiveModelId.contains('gemini-3.1-flash-lite')) {
      effectiveModelId = model15Flash8b;
    } else if (effectiveModelId.contains('3.1-flash-preview') || effectiveModelId.contains('gemini-3.1-flash')) {
      effectiveModelId = model15Flash;
    }

    // 'models/' プレフィックスを付ける。ユーザーが既に付けている場合は重複させない。
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
    String? modelId = 'models/gemini-1.5-flash',
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
  Future<NutritionResult?> analyzeNutrition(String text, {String? modelId}) async {
    // 栄養士ペルソナのシステム指示（汎用的な推論ベース）
    const nutritionistSystemInstruction = """
あなたは公認スポーツ栄養士です。
アスリートの食事内容（テキスト）から、マクロ栄養素（タンパク質 P、脂質 F、炭水化物 C）の含有量をグラム単位で、慎重かつ正確に見積もってください。

[戦略]
1. 推論ロジック: 不明な料理や商品名がある場合は、一般的な原材料（例: 「カップ焼きそば」 -> 油揚げ麺 100g、ソース、かやく）に分解して推定してください。
2. 分量: 明示されていない場合は、日本の標準的な一人前の分量（例: 白米 150g、主菜 100-150g）を基準にします。
3. リスク管理: タンパク質や炭水化物を過大評価しないでください。やや控えめに見積もる方がアスリートの管理としては安全です。

[基準データ（推論用）]
- 標準的な定食（主食+主菜+副菜）: P:20-25g, F:15-20g, C:70-90g
- 軽い軽食/飲料: P:0-5g, F:0-5g, C:10-30g
- ブラックコーヒー: ほぼゼロ
- 牛乳・ヨーグルト: 200ml/g あたり P:3-6g 程度

[出力形式]
- 以下のJSON形式のみを出力してください（追加のテキストは不要です）
  {"protein": 数値, "fat": 数値, "carbs": 数値, "reason": "品目ごとの内訳や根拠（日本語）"}
""";

    const userPrompt = "以下のアスリートの食事を分析し、控えめに見積もってください:\n";

    try {
      final response = await generateContent(
        "$userPrompt$text",
        systemInstruction: nutritionistSystemInstruction,
        modelId: modelId ?? modelForNutrition,  // 栄養解析用の軽量モデルをデフォルトに
        responseMimeType: 'application/json',
      );

      if (response == null || response.isEmpty) return null;
      final data = Map<String, dynamic>.from(jsonDecode(response));
      return NutritionResult(
        protein: (data['protein'] as num).toDouble(),
        carbs: (data['carbs'] as num).toDouble(),
        fat: (data['fat'] as num).toDouble(),
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
      return 'AIの利用制限（回数上限）に達しました。1〜2分待つか、1.5 Flash などの軽量モデルへ切り替えてください。';
    }
    if (errorStr.contains('503') || errorStr.contains('Service Unavailable')) {
      return '現在、Googleのサーバーが大変混み合っています (503 error)。特にPreview版モデルで発生しやすいため、1.5 Flash などの安定版（Stable）モデルへの切り替えをお勧めします。';
    }
    if (errorStr.contains('not found') || errorStr.contains('404')) {
      return '指定されたAIモデル ($modelName) が見つかりません。最新のモデルIDをアプリで確認してください。';
    }
    if (errorStr.contains('User Location is not supported')) {
      return 'お住いの地域ではこのAIモデル ($modelName) の利用が制限されています。';
    }
    if (errorStr.contains('Safety') || errorStr.contains('HARM_CATEGORY')) {
      return 'AIが不適切な内容と判断したため、回答を生成できませんでした。';
    }
    
    return '通信エラーが発生しました ($modelName)。時間を置いてから再度お試しください。';
  }

  /// アプリ共通のコーチ人格（システム指示）を生成する
  String getCoachSystemInstruction(AppUser user, {String supplementaryContext = ''}) {
    final expertiseLevel = (user.baseProfile['expertiseLevel'] as num?)?.toDouble() ?? 5.0;
    final vision = user.vision;
    final idealCoach = user.baseProfile['idealCoachPersona'] as String? ?? '専門的かつモチベーションを高めてくれるコーチ';

    // 専門レベルに応じた修飾語
    String scientificTone = "";
    if (expertiseLevel >= 8) {
      scientificTone = "流体力学、運動生理学、バイオメカニクスの高度な専門用語を駆使し、論文ベースの科学的なエビデンスに基づいた指導を行ってください。";
    } else if (expertiseLevel >= 5) {
      scientificTone = "トレーニング科学や栄養学の基礎に基づき、具体的かつ論理的な根拠を添えて指導を行ってください。";
    } else {
      scientificTone = "初心者でも理解しやすいよう、専門的な概念を平易な言葉や比喩に変換して、親しみやすく指導してください。";
    }

    return """
あなたは、世界トップレベルの競泳コーチングスペシャリストです。
データ分析、バイオメカニクス、運動生理学に精通しており、ユーザーのポテンシャルを最大限に引き出す論理的かつ科学的な指導を行います。

[あなたの性格・口調（最優先）]
$idealCoach

[科学的アプローチの指針]
$scientificTone

[ターゲット（ユーザー設定）]
- ビジョン(最終目標): $vision
- 専門知識の要求レベル: $expertiseLevel/10

[行動指針]
1. 上記の「口調」を常に維持し、一貫した人格で接してください。
2. ユーザーの「ビジョン」を常に念頭に置き、すべての回答をその達成へ結びつけてください。
3. 専門レベル($expertiseLevel/10)に応じた深さと語彙で解説を行ってください。
4. 根拠のない精神論は避け、常に生理学的・運動学的な論理性を持って回答してください。
$supplementaryContext
""";
  }
}
