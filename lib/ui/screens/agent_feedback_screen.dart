import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../data/services/gemini_service.dart';
import '../../data/services/firestore_service.dart';
import '../../data/models/personal_best.dart';

class AgentFeedbackScreen extends StatefulWidget {
  const AgentFeedbackScreen({super.key});

  @override
  State<AgentFeedbackScreen> createState() => _AgentFeedbackScreenState();
}

// グローバルにチャット履歴と状態を保持し、タブ切り替え時にも会話を維持する
final List<CoachMessage> _globalMessages = [];
ChatSession? _globalChatSession;
bool _globalIsInit = false;
bool _globalIsTyping = false;
String _globalAiModelName = 'AquaAnalyst AI';

class _AgentFeedbackScreenState extends State<AgentFeedbackScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (!_globalIsInit) {
      _initChat();
    }
  }

  Future<void> _initChat() async {
    _globalIsInit = true;
    
    // UIを即座に更新して起動中であることを示す
    if (mounted) {
      setState(() {
        _globalMessages.add(CoachMessage(
          text: 'AIコーチを起動しています... しばらくお待ちください。',
          isAi: true,
          type: MessageType.normal,
        ));
        _globalIsTyping = true;
      });
    }

    try {
      final user = await _firestoreService.getUserProfileStream().first;
      _globalAiModelName = user?.baseProfile['aiModel'] as String? ?? 'Gemini 2.5 Flash';
      final expertiseLevel = (user?.baseProfile['expertiseLevel'] as num?)?.toDouble() ?? 5.0;
      final vision = user?.vision ?? '未設定';
      final idealCoach = user?.baseProfile['idealCoachPersona'] as String? ?? 'ロジカルで、選手のモチベーションを高めてくれる専門家';

      final records = await _firestoreService.getTrainingRecordsStream(limit: 10).first;
      final latestPlan = await _firestoreService.getLatestWeeklyPlanStream().first;
      final allPbs = await _firestoreService.getPersonalBestsStream().first;

      String recordsText = "直近のトレーニング記録はありません。";
      if (records.isNotEmpty) {
        recordsText = "直近のトレーニング記録:\n" + records.map((r) {
          final dateStr = r.date.toIso8601String().substring(0, 10);
          final typeStr = r.type == 'pool' ? '水中練習' : '陸上/その他';
          return "- $dateStr: $typeStr (時間: ${r.durationMinutes ?? '?'}分, 疲労度: ${r.subjectiveMetrics['fatigue'] ?? '?'}/10)\n  詳細: ${r.details}";
        }).join('\n');
      }
      
      String planText = "現在設定されている週間トレーニング計画はありません。";
      if (latestPlan != null) {
        planText = "現在の週間トレーニング計画 (${latestPlan.startDate.month}/${latestPlan.startDate.day}〜):\n" + 
          latestPlan.dailyPlans.map((d) => "  - ${d.dateStr}: 水中[${d.waterMenu}] 陸上[${d.dryland}] (強度: ${d.intensity})").join('\n');
      }

      String pbText = "自己ベスト:\n" + (allPbs.isEmpty ? "未登録" : allPbs.reversed.map((pb) => 
        "- ${pb.event}: ${pb.value} ${pb.category == 'swim' ? '秒' : 'kg'} (${pb.date.year}/${pb.date.month}/${pb.date.day})"
      ).join('\n'));

      final sysInst = '''
# Role
あなたは「競泳科学分析・トレーニング統合エージェント」です。スポーツ生理学、バイオメカニクス、およびデータサイエンスの深い知見を持ち、初心者からトップアスリートまで対応した分析と指導を行います。

# コーチ像（あなたのパーソナリティ）
ユーザーが望むあなたの理想のコーチ像は以下の通りです：
$idealCoach
※これに従い、提供するアドバイスのトーン（厳しさ、優しさ、論理性の比重など）や言葉遣いを適切に調整してください。

# ビジョン（ユーザーの最終目標）
$vision
※すべてのアドバイスはこの目標の達成に向けられたものである必要があります。

# Expertise Level
現在の専門性要求レベル: $expertiseLevel / 10
(1: 初心者向けに平易な言葉で、10: 専門用語や最新論文の知見を用いた極めて科学的な解説)

# Mission
ユーザーから提供される個別のデータを客観的に分析し、以下の2つのアウトプットを統合して提供してください。
1. **科学的トレーニング案:** 生理学的背景に基づいたメニュー構成と技術的アドバイス。
2. **タイム予測・レース分析:** CSSやRiegelの公式、ストローク効率（DPS/SR）等を用いた分析。

# Analysis Framework
- エネルギー系分析 (ターゲット距離に応じた代謝特性の最適化)
- ストローク効率 (DPSとSRの相関)
- 予測アルゴリズム (複数距離の相関による推定)

【ユーザーコンテキスト】
- プロフィール: ${user?.baseProfile.toString() ?? '未設定'}
- 週間計画: $planText
- 直近の練習: $recordsText
- 自己ベスト: $pbText

# Guidelines
- 客観的かつ論理的なトーンを維持する。
- 初回起動時は「AIコーチシステムが起動しました」と述べ、不足情報の確認から入る。
- 最初の挨拶は簡潔にし、速やかにユーザーへの問いかけを行う。
''';

      _globalChatSession = GeminiService().startChat(systemInstruction: sysInst);

      if (mounted) {
        // ビジョンを考慮した初回挨拶を生成させる
        final response = await _globalChatSession!.sendMessage(Content.text("システムを起動してください。まず、私の最終目標（ビジョン）である「$vision」を認知していることを踏まえて簡潔に挨拶を行い、分析精度を高めるために不足している情報について私に求めてください。"));
        
        setState(() {
          // 「起動中...」のメッセージを削除または更新する。ここでは最新の応答を追加
          _globalMessages.removeWhere((m) => m.text.contains('起動しています'));
          _globalMessages.add(CoachMessage(
            text: response.text ?? 'AIコーチシステムが起動しました。コンディションや詳細データを教えてください。',
            isAi: true,
            type: MessageType.normal,
          ));
          _globalIsTyping = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _globalIsTyping = false;
          _globalMessages.add(CoachMessage(
            text: 'AIの初期化に失敗しました。APIキー等の設定を確認してください。\nエラー: $e',
            isAi: true,
            type: MessageType.warning,
          ));
        });
      }
    }
  }

  void _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;
    
    // 初期化前にメッセージが送られた場合
    if (_globalChatSession == null) {
      setState(() {
        _globalMessages.add(CoachMessage(
          text: text,
          isAi: false,
          type: MessageType.normal,
        ));
        _globalMessages.add(CoachMessage(
          text: 'AIコーチの起動を待っています。しばらくお待ちください...',
          isAi: true,
          type: MessageType.warning,
        ));
      });
      _textController.clear();
      _scrollToBottom();
      return;
    }

    _textController.clear();
    setState(() {
      _globalMessages.add(CoachMessage(
        text: text,
        isAi: false,
        type: MessageType.normal,
      ));
      _globalIsTyping = true;
    });
    
    _scrollToBottom();

    try {
      final response = await _globalChatSession!.sendMessage(Content.text(text));
      if (!mounted) {
        _globalIsTyping = false;
        _globalMessages.add(CoachMessage(
          text: response.text ?? '応答がありませんでした。',
          isAi: true,
          type: MessageType.normal,
        ));
        return;
      }
      setState(() {
        _globalIsTyping = false;
        _globalMessages.add(CoachMessage(
          text: response.text ?? '応答がありませんでした。',
          isAi: true,
          type: MessageType.normal,
        ));
      });
    } catch (e) {
      if (!mounted) {
        _globalIsTyping = false;
        _globalMessages.add(CoachMessage(
          text: 'エラーが発生しました: $e',
          isAi: true,
          type: MessageType.warning,
        ));
        return;
      }
      setState(() {
        _globalIsTyping = false;
        _globalMessages.add(CoachMessage(
          text: 'エラーが発生しました: $e',
          isAi: true,
          type: MessageType.warning,
        ));
      });
    }
    
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('コーチ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('過去のスレッド履歴を表示します（モック）')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              itemCount: _globalMessages.length + (_globalIsTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _globalMessages.length && _globalIsTyping) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 16.0),
                      child: Chip(
                        avatar: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        label: Text('回答を生成中...'),
                        backgroundColor: Colors.black45,
                      ),
                    ),
                  );
                }
                final message = _globalMessages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          const Divider(height: 1),
          _buildTextComposer(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(CoachMessage message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: message.isAi ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (message.isAi)
            Container(
              margin: const EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(Icons.psychology, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: message.isAi ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 5.0),
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: _getBubbleColor(context, message),
                    border: _getBubbleBorder(context, message),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(message.isAi ? 0 : 16),
                      bottomRight: Radius.circular(message.isAi ? 16 : 0),
                    ),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      height: 1.5,
                      color: message.isAi
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!message.isAi)
            Container(
              margin: const EdgeInsets.only(left: 16.0),
              child: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                child: Icon(Icons.person, color: Theme.of(context).colorScheme.onSecondaryContainer),
              ),
            ),
        ],
      ),
    );
  }

  Color _getBubbleColor(BuildContext context, CoachMessage message) {
    if (!message.isAi) return Theme.of(context).colorScheme.primary;
    // ライト/ダーク両方に対応できるよう、表面色にうっすら色を載せる
    final baseColor = Theme.of(context).colorScheme.onSurface;
    switch (message.type) {
      case MessageType.warning:
        return Colors.orange.withOpacity(0.15);
      case MessageType.bcaSequence:
        return baseColor.withOpacity(0.08);
      default:
        return Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3);
    }
  }

  BoxBorder? _getBubbleBorder(BuildContext context, CoachMessage message) {
    if (!message.isAi) return null;
    switch (message.type) {
      case MessageType.warning:
        return Border.all(color: Colors.orange);
      case MessageType.bcaSequence:
        return Border.all(color: Theme.of(context).colorScheme.outlineVariant);
      default:
        return Border.all(color: Theme.of(context).colorScheme.primaryContainer);
    }
  }

  Widget _buildTextComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      color: Theme.of(context).cardColor,
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20.0),
                ),
                  child: Focus(
                  onKeyEvent: (node, event) {
                    // Enterキーが押された際（KeyDownEvent）の処理
                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                      final bool isCtrl = HardwareKeyboard.instance.isControlPressed;
                      final bool isShift = HardwareKeyboard.instance.isShiftPressed;

                      // モバイル等でCtrl/Shiftキーが使えない場合は無視
                      // PCで Ctrl+Enter または Shift+Enter の場合は改行（TextFieldが処理）
                      if (isCtrl || isShift) {
                        return KeyEventResult.ignored;
                      }

                      // 変換中 (Composing) でない場合のみ送信
                      if (!_textController.value.composing.isValid) {
                        final text = _textController.text;
                        if (text.trim().isNotEmpty) {
                          _handleSubmitted(text);
                        }
                        return KeyEventResult.handled; // 送信されたのでこれ以上のイベント伝播を防ぐ
                      } else {
                        // 変換中のEnterは変換確定としてTextFieldに任せる
                        return KeyEventResult.ignored;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _textController,
                    minLines: 3,
                    maxLines: 3,
                    textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline, // モバイルでも改行を優先
                      decoration: const InputDecoration(
                        hintText: 'メッセージを入力',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
                      ),
                    ),
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            Container(
              margin: const EdgeInsets.only(bottom: 2.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.send, color: Theme.of(context).colorScheme.onPrimary),
                onPressed: () => _handleSubmitted(_textController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum MessageType {
  normal,
  warning,
  bcaSequence,
}

class CoachMessage {
  final String text;
  final bool isAi;
  final MessageType type;

  CoachMessage({
    required this.text,
    required this.isAi,
    this.type = MessageType.normal,
  });
}
