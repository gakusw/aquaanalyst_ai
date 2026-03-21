import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../data/services/gemini_service.dart';
import '../../data/services/firestore_service.dart';
import '../../data/models/chat_session.dart';
import '../../data/providers/providers.dart';
import '../widgets/premium_card.dart';
import '../../utils/app_colors.dart';

class AgentFeedbackScreen extends ConsumerStatefulWidget {
  const AgentFeedbackScreen({super.key});

  @override
  ConsumerState<AgentFeedbackScreen> createState() => _AgentFeedbackScreenState();
}

// 状態を維持するためのグローバル変数を削除し、State内で管理するように変更（またはセッションIDで切り替え）
// ※利便性のため、現在のセッションIDのみStaticで保持する
String? _activeSessionId;

class _AgentFeedbackScreenState extends ConsumerState<AgentFeedbackScreen> {
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
  bool _isTyping = false;
  String? _streamingResponse;
  String? _currentSessionId = _activeSessionId;
  String? _activeModelId;

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    if (_currentSessionId != null) {
      await _loadSession(_currentSessionId!);
    } else {
      await _firestoreService.ensureHomeChatExists();
      await _loadSession('home_chat');
    }
  }

  Future<void> _loadSession(String sessionId) async {
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _isTyping = true;
      _currentSessionId = sessionId;
      _activeSessionId = sessionId;
    });

    try {
      // 履歴を読み込む (これだけはセッション固有なので非同期)
      // 非同期購読を確実に行うため .first ではなく Stream として扱うことも検討できるが、
      // ここでは初期ロードの確実性を優先
      final history = await _firestoreService.getChatMessagesStream(sessionId).first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => [],
      );
      
      // Provider から最新情報を即座に取得 (通信待ちなし)
      final sysInstContext = ref.read(coachSystemContextProvider);
      final user = ref.read(userProfileProvider).value;
      if (user == null) throw Exception('ユーザー情報が見つかりません');
      
      final modelId = user.baseProfile['aiModel'] as String? ?? GeminiService.modelFlash;
      _activeModelId = modelId;
      final medicalHistory = user.baseProfile['medicalHistory'] as String? ?? 'なし';

      // 共通メソッドを使用してシステム指示を生成
      final fullSysInst = await GeminiService().getCoachSystemInstruction(
        user,
        supplementaryContext: """
$sysInstContext
■ 既往歴: $medicalHistory
""",
      );

      // トークン節約のため、Geminiに送る履歴を直近20件に制限
      final List<Content> geminiHistory = history.reversed.take(20).toList().reversed.map<Content>((m) => 
        m.isAi ? Content.model([TextPart(m.text)]) : Content.text(m.text)
      ).toList();

      _chatSession = GeminiService().startChat(
        systemInstruction: fullSysInst,
        history: geminiHistory,
        modelId: _activeModelId,
      );

      if (mounted) {
        setState(() {
          if (history.isEmpty) {
            _messages.add(CoachMessage(
              text: 'こんにちは！専属コーチです。トレーニングの振り返りや、栄養、睡眠、今後の計画など、何でも相談してくださいね。',
              isAi: true,
              type: MessageType.normal,
            ));
          } else {
            _messages.addAll(history.map((m) => CoachMessage(
              text: m.text,
              isAi: m.isAi,
              type: MessageType.normal,
            )));
          }
          _isTyping = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error loading session: $e');
      setState(() => _isTyping = false);
    }
  }

  Future<void> _createNewChat() async {
    setState(() {
      _messages.clear();
      _isTyping = true;
    });

    try {
      final user = ref.read(userProfileProvider).value;
      if (user == null) throw Exception('ユーザー情報が見つかりません');
      final modelId = user.baseProfile['aiModel'] as String? ?? GeminiService.modelFlash;
      _activeModelId = modelId;

      final sysInstContext = ref.read(coachSystemContextProvider);
      final medicalHistory = user.baseProfile['medicalHistory'] as String? ?? 'なし';
      
      final sysInst = await GeminiService().getCoachSystemInstruction(
        user,
        supplementaryContext: """
$sysInstContext
■ 既往歴: $medicalHistory
""",
      );

      _chatSession = GeminiService().startChat(
        systemInstruction: sysInst,
        history: [],
        modelId: _activeModelId,
      );

      final sessionId = 'chat_${DateTime.now().millisecondsSinceEpoch}';
      await _firestoreService.saveChatSession(ChatSessionModel(
        id: sessionId,
        title: '新規チャット',
        lastMessageAt: DateTime.now(),
        systemInstruction: sysInst,
      ));

      setState(() {
        _currentSessionId = sessionId;
        _activeSessionId = sessionId;
        _messages.add(CoachMessage(
          text: 'こんにちは！コーチです。今日はどのようなことを相談したいですか？',
          isAi: true,
          type: MessageType.normal,
        ));
        _isTyping = false;
      });
    } catch (e) {
      debugPrint('Error creating chat: $e');
      setState(() => _isTyping = false);
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
      _isTyping = true;
      _streamingResponse = null;
    });
    
    _scrollToBottom();

    try {
      // ユーザーメッセージをDB保存（awaitを外してストリーム開始のラグを解消）
      _firestoreService.addChatMessage(sessionId, ChatMessage(text: text, isAi: false, timestamp: DateTime.now()));

      // ストリーミング応答の開始
      final stream = _chatSession!.sendMessageStream(Content.text(text));
      
      String fullResponse = "";

      await for (final chunk in stream) {
        final chunkText = chunk.text;
        if (chunkText != null) {
          fullResponse += chunkText;
          if (mounted) {
            setState(() {
              _isTyping = false;
              _streamingResponse = fullResponse;
            });
            _scrollToBottom();
          }
        }
      }

      // AIメッセージをDB保存（待機せずに即時反映）
      _firestoreService.addChatMessage(sessionId, ChatMessage(text: fullResponse, isAi: true, timestamp: DateTime.now()));

      if (mounted) {
        // DBからStreamBuilderに反映されるまでのフリッカーを防ぐため、少し遅延させてプレビューを消す
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _streamingResponse = null;
            });
          }
        });
      }

      if (!mounted) return;
      
      // 送信成功時に利用回数をインクリメント
      _firestoreService.incrementDailyUsage();

    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _streamingResponse = null;
          final msg = GeminiService().translateError(e, modelId: _activeModelId);
          _messages.add(CoachMessage(text: msg, isAi: true, type: MessageType.warning));
        });
      }
    } finally {
      if (mounted) {
        // 万が一漏れた場合のためにリセット
        setState(() {
          _isTyping = false;
          _streamingResponse = null;
        });
      }
    }
    _scrollToBottom();
  }

  Future<void> _renameSession(String sessionId, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('履歴の名前変更'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '新しいタイトルを入力'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != currentTitle) {
      await _firestoreService.updateChatSessionTitle(sessionId, newTitle);
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('履歴の削除'),
        content: const Text('このチャット履歴を削除してもよろしいですか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestoreService.deleteChatSession(sessionId);
      if (_currentSessionId == sessionId) {
        _loadSession('home_chat');
      }
    }
  }

  void _scrollToBottom() {
    // reverse: true の場合は、スクロール位置の調整は基本不要
  }

  @override
  Widget build(BuildContext context) {
    if (_currentSessionId == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'AquaAnalyst AI',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: AppColors.skyBlue,
            ),
          ),
          centerTitle: false,
        ),
        drawer: _buildDrawer(),
        body: _buildEmptyState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AquaAnalyst AI',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: AppColors.skyBlue,
          ),
        ),
        centerTitle: false,
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
            child: StreamBuilder<List<ChatMessage>>(
              stream: _firestoreService.getChatMessagesStream(_currentSessionId!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final dbMessages = snapshot.data ?? [];
                
                // 初回読み込みでデータが空の場合の初期メッセージ
                if (dbMessages.isEmpty && !_isTyping) {
                   // 初回時のAIの挨拶。DBには保存しない。
                   return ListView(
                     padding: const EdgeInsets.all(16.0),
                     children: [
                       _buildMessageBubble(CoachMessage(
                        text: 'こんにちは！専属コーチです。トレーニングの振り返りや、栄養、睡眠、今後の計画など、何でも相談してくださいね。',
                        isAi: true,
                       )),
                     ],
                   );
                }

                // reverse: true を使用して最新メッセージを下にする
                final displayMessages = dbMessages.reversed.toList();

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16.0),
                  itemCount: displayMessages.length + (_isTyping || _streamingResponse != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    if ((_isTyping || _streamingResponse != null) && index == 0) {
                      if (_isTyping) {
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
                      } else {
                        return _buildMessageBubble(CoachMessage(
                          text: _streamingResponse!,
                          isAi: true,
                          type: MessageType.normal,
                        ));
                      }
                    }
                    
                    final mIndex = (_isTyping || _streamingResponse != null) ? index - 1 : index;
                    final m = displayMessages[mIndex];
                    return _buildMessageBubble(CoachMessage(
                      text: m.text,
                      isAi: m.isAi,
                      type: MessageType.normal,
                    ));
                  },
                );
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
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: PremiumCard(
          icon: Icons.psychology,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.psychology, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 24),
              const Text(
                'コーチに相談しましょう',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'トレーニングの悩みや栄養について、いつでも相談に乗ります。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _createNewChat,
                icon: const Icon(Icons.add),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                label: const Text('新しい相談を開始'),
              ),
            ],
          ),
        ),
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
                    final isHomeChat = session.id == 'home_chat';
                    return ListTile(
                      selected: session.id == _currentSessionId,
                      leading: Icon(isHomeChat ? Icons.home : Icons.chat_bubble_outline),
                      title: Text(session.title),
                      subtitle: Text('${session.lastMessageAt.month}/${session.lastMessageAt.day}'),
                      trailing: isHomeChat ? null : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _renameSession(session.id, session.title),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20),
                            onPressed: () => _deleteSession(session.id),
                          ),
                        ],
                      ),
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
                    gradient: _getBubbleGradient(context, message),
                    border: _getBubbleBorder(context, message),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(message.isAi ? 4 : 20),
                      bottomRight: Radius.circular(message.isAi ? 20 : 4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      height: 1.5,
                      fontSize: 15,
                      color: message.isAi
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.white,
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
        return Colors.orange.withValues(alpha: 0.15);
      case MessageType.bcaSequence:
        return baseColor.withValues(alpha: 0.08);
      default:
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.5);
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

  Gradient? _getBubbleGradient(BuildContext context, CoachMessage message) {
    if (message.isAi) return null;
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
    );
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                    minLines: 1,
                    maxLines: 5, // 5行まで自動で伸びるように変更。1だと使いにくい可能性があるため
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
