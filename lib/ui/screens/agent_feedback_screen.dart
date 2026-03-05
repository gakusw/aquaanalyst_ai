import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../widgets/add_record_fab.dart';
import '../../data/services/gemini_service.dart';
import '../../data/services/firestore_service.dart';

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
    setState(() {
      _globalIsTyping = true;
    });

    try {
      final user = await _firestoreService.getUserProfileStream().first;
      _globalAiModelName = user?.baseProfile['aiModel'] as String? ?? 'Gemini 2.5 Flash';
      final records = await _firestoreService.getTrainingRecordsStream(limit: 5).first;
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

      // 最新自己ベストの抽出
      String pbText = "登録されている自己ベストはありません。";
      if (allPbs.isNotEmpty) {
        final Map<String, PersonalBest> latestPbs = {};
        for (var pb in allPbs.reversed) {
          latestPbs[pb.event] = pb;
        }
        pbText = "現在の自己ベスト:\n" + latestPbs.values.map((pb) => 
          "- ${pb.event}: ${pb.value} ${pb.category == 'swim' ? '秒' : 'kg'} (${pb.date.year}/${pb.date.month}/${pb.date.day})"
        ).join('\n');
      }

      final sysInst = '''
あなたは水泳競技のAIコーチ「AquaAnalyst AI」です。
ユーザーのパートナーとして、データに基づきつつも、親身で励みになるアドバイスを提供してください。
【ユーザー情報】
- ビジョン(最終目標): ${user?.vision ?? '未設定'}
- 基本プロフィール: ${user?.baseProfile.toString() ?? '未設定'}

【最新の週間トレーニング計画】
$planText

【最新のデータ】
$recordsText

【現在の自己ベスト】
$pbText

ユーザーからの質問や発言に対して、上記データ・計画に加えて自己ベストの成長も踏まえた実践的かつ客観的なコーチングを行ってください。
ただし、「感情や希望的観測を一切排除した」といった冷たすぎる表現や、内部プロセス（「Phase C」など）の名称は絶対に出さないでください。専門的でありながら、ユーザーのモチベーションを高める温かいトーンを心がけてください。
''';

      _globalChatSession = GeminiService().startChat(systemInstruction: sysInst);

      if (mounted) {
        setState(() {
          _globalMessages.add(CoachMessage(
            text: 'AIコーチシステムが起動しました。最新のデータと基本プロフィールを読み込み完了しました。現在のコンディションやトレーニングについて報告してください。',
            isAi: true,
            type: MessageType.normal,
          ));
          _globalIsTyping = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _globalMessages.add(CoachMessage(
            text: 'AIの初期化に失敗しました。APIキー等の設定を確認してください。\\nエラー: \$e',
            isAi: true,
            type: MessageType.warning,
          ));
          _globalIsTyping = false;
        });
      }
    }
  }

  void _handleSubmitted(String text) async {
    if (text.trim().isEmpty || _globalChatSession == null) return;

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
        // UIが破棄されていてもグローバル状態は更新する
        _globalIsTyping = false;
        _globalMessages.add(CoachMessage(
          text: response.text ?? '応答がありませんでした。',
          isAi: true,
          type: (response.text?.contains('警告') ?? false) 
              ? MessageType.warning 
              : (response.text?.contains('希望的観測') ?? false) 
                  ? MessageType.bcaSequence 
                  : MessageType.normal,
        ));
        return;
      }
      setState(() {
        _globalIsTyping = false;
        _globalMessages.add(CoachMessage(
          text: response.text ?? '応答がありませんでした。',
          isAi: true,
          type: (response.text?.contains('警告') ?? false) 
              ? MessageType.warning 
              : (response.text?.contains('希望的観測') ?? false) 
                  ? MessageType.bcaSequence 
                  : MessageType.normal,
        ));
      });
    } catch (e) {
      if (!mounted) {
        _globalIsTyping = false;
        _globalMessages.add(CoachMessage(
          text: 'エラーが発生しました: \$e',
          isAi: true,
          type: MessageType.warning,
        ));
        return;
      }
      setState(() {
        _globalIsTyping = false;
        _globalMessages.add(CoachMessage(
          text: 'エラーが発生しました: \$e',
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

