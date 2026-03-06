import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';

class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  String? _apiKey;

  /// 初期化処理
  void init() {
    _apiKey = dotenv.env['GEMINI_API_KEY'];
    if (_apiKey == null || _apiKey!.isEmpty || _apiKey == 'YOUR_KEY_HERE') {
      debugPrint('Warning: GEMINI_API_KEY is not set or invalid.');
    }
  }

  GenerativeModel? _createModel({String? systemInstruction, String? responseMimeType}) {
    if (_apiKey == null || _apiKey!.isEmpty || _apiKey == 'YOUR_KEY_HERE') return null;
    return GenerativeModel(
      model: 'gemini-3.0-pro',
      apiKey: _apiKey!,
      systemInstruction: systemInstruction != null ? Content.system(systemInstruction) : null,
      generationConfig: responseMimeType != null ? GenerationConfig(responseMimeType: responseMimeType) : null,
    );
  }

  /// AIへの単発プロンプト送信
  Future<String?> generateContent(String prompt, {String? systemInstruction, String? responseMimeType}) async {
    final model = _createModel(systemInstruction: systemInstruction, responseMimeType: responseMimeType);
    if (model == null) return 'AIモデルが初期化されていません。APIキーの設定を確認してください。';

    try {
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      return response.text;
    } catch (e) {
      debugPrint('Gemini API Error: $e');
      final errorStr = e.toString();
      if (errorStr.contains('Quota exceeded') || errorStr.contains('429')) {
        throw Exception('AIの利用制限（無料枠の上限）に達しました。約1分ほど待ってから再度お試しください。');
      }
      throw Exception('AIの処理中にエラーが発生しました: $e');
    }
  }

  /// 画像付きでAIへプロンプト送信
  Future<String?> generateContentWithImage(
    String prompt,
    Uint8List imageBytes,
    String mimeType, {
    String? systemInstruction,
    String? responseMimeType,
  }) async {
    final model = _createModel(systemInstruction: systemInstruction, responseMimeType: responseMimeType);
    if (model == null) return 'AIモデルが初期化されていません。APIキーの設定を確認してください。';

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
      debugPrint('Gemini Vision API Error: $e');
      final errorStr = e.toString();
      if (errorStr.contains('Quota exceeded') || errorStr.contains('429')) {
        throw Exception('AIの利用制限（無料枠の一時的な上限）に達しました。約1分待ってから再度お試しください。');
      }
      throw Exception('AIの処理中にエラーが発生しました: $e');
    }
  }

  /// チャットセッション（履歴保持）を開始する
  /// [history] を指定することで、過去のメッセージから再開可能
  ChatSession startChat({String? systemInstruction, List<Content>? history}) {
    final model = _createModel(systemInstruction: systemInstruction);
    if (model == null) {
      throw Exception('AI model is not initialized or API key is missing.');
    }
    return model.startChat(history: history);
  }
}
