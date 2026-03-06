import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../data/services/gemini_service.dart';
import '../../data/services/firestore_service.dart';
import '../../data/models/personal_best.dart';
import '../../data/models/chat_session.dart';

class AgentFeedbackScreen extends StatefulWidget {
  const AgentFeedbackScreen({super.key});

  @override
  State<AgentFeedbackScreen> createState() => _AgentFeedbackScreenState();
}

// 状態を維持するためのグローバル変数を削除し、State内で管理するように変更（またはセッションIDで切り替え）
// ※利便性のため、現在のセッションIDのみStaticで保持する
String? _activeSessionId;

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

  final List<CoachMessage> _messages = [];
  ChatSession? _chatSession;
  bool _isInit = false;
  bool _isTyping = false;
  String? _currentSessionId = _activeSessionId;
  String _aiModelName = 'Gemini 1.5 Flash';

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    if (_currentSessionId != null) {
      await _loadSession(_currentSessionId!);
    } else {
      // セッションがない場合は初期化（必要に応じて自動作成も検討）
    }
  }

  Future<void> _loadSession(String sessionId) async {
    setState(() {
      _messages.clear();
      _isTyping = true;
      _currentSessionId = sessionId;
      _activeSessionId = sessionId;
    });

    try {
      // 履歴を読み込む
      final history = await _firestoreService.getChatMessagesStream(sessionId).first;
      
      // システムプロンプトを取得するためのセッション情報を取得
      final sessions = await _firestoreService.getChatSessionsStream().first;
      final currentSession = sessions.firstWhere((s) => s.id == sessionId);

      // Geminiの型に変換
      final List<Content> geminiHistory = history.map((m) => 
        m.isAi ? Content.model([TextPart(m.text)]) : Content.user([TextPart(m.text)])
      ).toList();

      _chatSession = GeminiService().startChat(
        systemInstruction: currentSession.systemInstruction,
        history: geminiHistory,
      );

      setState(() {
        _messages.addAll(history.map((m) => CoachMessage(
          text: m.text,
          isAi: m.isAi,
          type: MessageType.normal,
        )));
        _isTyping = false;
        _isInit = true;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error loading session: $e');
      setState(() => _isTyping = false);
    }
  }

  Future<void> _createNewChat() async {
    setState(() {
      _messages.clear();
      _isTyping = true;
      _isInit = false;
    });

    try {
      final user = await _firestoreService.getUserProfileStream().first;
      final expertiseLevel = (user?.baseProfile['expertiseLevel'] as num?)?.toDouble() ?? 5.0;
      final vision = user?.vision ?? '未設定';
      final idealCoach = user?.baseProfile['idealCoachPersona'] as String? ?? 'ロジカルで、選手のモチベーションを高めてくれる専門家';

      // 節約のため直近5件に制限
      final records = await _firestoreService.getTrainingRecordsStream(limit: 5).first;
      final latestPlan = await _firestoreService.getLatestWeeklyPlanStream().first;
      final allPbs = await _firestoreService.getPersonalBestsStream().first;

      String recordsText = records.isEmpty ? "なし" : records.map((r) => "- ${r.date.toIso8601String().substring(0,10)}: ${r.type}").join('\n');
      String pbText = allPbs.isEmpty ? "なし" : allPbs.take(5).map((pb) => "- ${pb.event}: ${pb.value}").join('\n');

      final sysInst = '''
あなたは競泳コーチです。
理想のコーチ像: $idealCoach
目標: $vision
レベル: $expertiseLevel/10
最新の記録:
$recordsText
自己ベスト(一部):
$pbText
''';

      final sessionId = await _firestoreService.createChatSession(
        title: '${DateTime.now().month}/${DateTime.now().day} の相談',
        systemInstruction: sysInst,
      );

      _currentSessionId = sessionId;
      _activeSessionId = sessionId;
      _chatSession = GeminiService().startChat(systemInstruction: sysInst);

      // 初回挨拶
      final response = await _chatSession!.sendMessage(Content.text("システムを起動してください。挨拶と、分析に必要な情報があれば聞いてください。"));
      final aiMsg = response.text ?? 'こんにちは。何かお手伝いしましょうか？';
      
      await _firestoreService.addChatMessage(sessionId, ChatMessage(text: aiMsg, isAi: true, timestamp: DateTime.now()));

      setState(() {
        _messages.add(CoachMessage(text: aiMsg, isAi: true));
        _isTyping = false;
        _isInit = true;
      });
    } catch (e) {
      setState(() {
        _isTyping = false;
        _messages.add(CoachMessage(text: 'エラーが発生しました: $e', isAi: true, type: MessageType.warning));
      });
    }
  }

  void _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;
    final sessionId = _currentSessionId;
    
    if (sessionId == null || _chatSession == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('チャットが初期化されていません。「新しい相談」を始めてください。')));
      return;
    }

    _textController.clear();
    setState(() {
      _messages.add(CoachMessage(text: text, isAi: false));
      _isTyping = true;
    });
    
    _scrollToBottom();

    try {
      // ユーザーメッセージをDB保存
      await _firestoreService.addChatMessage(sessionId, ChatMessage(text: text, isAi: false, timestamp: DateTime.now()));

      final response = await _chatSession!.sendMessage(Content.text(text));
      final aiMsg = response.text ?? '応答がありませんでした。';

      // AIメッセージをDB保存
      await _firestoreService.addChatMessage(sessionId, ChatMessage(text: aiMsg, isAi: true, timestamp: DateTime.now()));

      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(CoachMessage(text: aiMsg, isAi: true));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(CoachMessage(text: _getFriendlyErrorMessage(e), isAi: true, type: MessageType.warning));
      });
    }
    _scrollToBottom();
  }

  String _getFriendlyErrorMessage(dynamic e) {
    final errorStr = e.toString();
    
    if (errorStr.contains('Quota exceeded') || errorStr.contains('429')) {
      return '【AIコーチより】\nただいまリクエストが集中しており、少し休憩が必要です。1分ほど待ってからもう一度話しかけてみてください。';
    }
    
    if (errorStr.contains('Service Unavailable') || errorStr.contains('503')) {
      return '【AIコーチより】\nAIサーバーが一時的にメンテナンス中か、不安定なようです。少し時間を置いてからお試しください。';
    }
    
    if (errorStr.contains('API key not valid')) {
      return '【システムエラー】\nAPIキーが正しく設定されていないようです。管理者設定を確認してください。';
    }
    
    if (errorStr.contains('Connection failed') || errorStr.contains('Network')) {
      return '【通信エラー】\nインターネット接続を確認してください。オフラインの可能性があります。';
    }

    return '【AIコーチより】\n申し訳ありません、一時的な通信エラーが発生したようです。通信環境を確認し、少し時間を置いてから再度お試しください。';
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
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          Expanded(
            child: _currentSessionId == null && !_isTyping
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isTyping) {
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
                              label: Text('考え中...'),
                            ),
                          ),
                        );
                      }
                      final message = _messages[index];
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.psychology, size: 64, color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 16),
          const Text('相談を始めましょう'),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createNewChat,
            icon: const Icon(Icons.add),
            label: const Text('新しい相談を開始'),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
            child: const Center(child: Text('相談履歴', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新しく相談する'),
            onTap: () {
              Navigator.pop(context);
              _createNewChat();
            },
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<ChatSessionModel>>(
              stream: _firestoreService.getChatSessionsStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final sessions = snapshot.data!;
                if (sessions.isEmpty) return const Center(child: Text('履歴がありません'));
                
                return ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    return ListTile(
                      selected: session.id == _currentSessionId,
                      title: Text(session.title),
                      subtitle: Text('${session.lastMessageAt.month}/${session.lastMessageAt.day}'),
                      onTap: () {
                        Navigator.pop(context);
                        _loadSession(session.id);
                      },
                    );
                  },
                );
              },
            ),
          ),
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
