// MediaPipe LLM Inference API Bridge for Gemma 4 (WebGPU/WASM)
// 2026 Standard Implementation

import { LlmInference, FilesetResolver } from 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai';

let llmInference = null;

window.gemmaBridge = {
  /**
   * モデルの初期化（ダウンローアドとロード）
   */
  async initModel(modelPath) {
    console.log("Gemma 4 Bridge: Starting initialization...");
    const genai = await FilesetResolver.forGenAiTasks(
      "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-genai/wasm"
    );

    llmInference = await LlmInference.createFromOptions(genai, {
      baseOptions: { modelAssetPath: modelPath },
      maxTokens: 512,
      topK: 40,
      temperature: 0.7,
      randomSeed: 101,
    });
    console.log("Gemma 4 Bridge: Model loaded successfully.");
    return true;
  },

  /**
   * 推論の実行（テキスト・トゥ・テキスト）
   */
  async generateText(prompt) {
    if (!llmInference) throw new Error("Gemma 4 is not initialized.");
    
    // MediaPipe 2026 版の推論呼び出し
    const response = await llmInference.generateResponse(prompt);
    return response;
  },

  /**
   * ストリーミング推論（将来用）
   */
  async generateTextStream(prompt, onToken) {
    if (!llmInference) throw new Error("Gemma 4 is not initialized.");
    llmInference.generateResponse(prompt, (partial) => {
      onToken(partial);
    });
  }
};
