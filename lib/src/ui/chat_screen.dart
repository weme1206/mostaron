import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/prompt_builder.dart';
import '../services/settings_resolver.dart';
import '../state/app_state.dart';
import 'widgets/avatars.dart';
import 'widgets/message_bubble.dart';
import 'widgets/thinking_toggle.dart';
import '../utils/colors.dart';
import 'memory_screen.dart';
import 'character_editor_screen.dart';
import 'worldbook_screen.dart';
import 'worldbook_picker.dart';
import 'widgets/search_history_screen.dart';
import 'widgets/ai_rewrite_button.dart';

class ChatScreen extends StatefulWidget {
  final String characterId;
  final String? initialSearchTargetId; // 查找聊天记录后定位到某条消息
  const ChatScreen({super.key, required this.characterId, this.initialSearchTargetId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Character? _character;
  ChatSession? _session;
  List<ChatMessage> _messages = [];
  List<WorldbookEntry> _worldbook = [];
  List<MemoryItem> _memories = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _streaming = false;
  bool _generating = false;
  String _streamText = '';
  String _streamReasoning = '';
  bool _showReasoning = false;
  bool _loading = true;

  bool? _hideCharAvatar;
  bool? _hideUserAvatar;
  bool _userScrolled = false;
  bool _programmaticJump = false;
  int _searchReturnIndex = -1;
  bool _inputRewriting = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  void _onScroll() {
    if (!_programmaticJump) _userScrolled = true;
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final c = await state.getCharacter(widget.characterId);
    final session = await state.getOrCreateSession(widget.characterId);
    final msgs = await state.messagesFor(session.id);
    final worldbook = (c == null || c.worldbookIds.isEmpty)
        ? <WorldbookEntry>[]
        : (await state.worldbookFor(null))
            .where((e) => c.worldbookIds.contains(e.id))
            .toList();
    final memories = await state.memoriesFor(widget.characterId);

    if (msgs.isEmpty && c != null && c.greeting.trim().isNotEmpty) {
      final greeting = ChatMessage(
        id: 'g_${DateTime.now().microsecondsSinceEpoch}',
        sessionId: session.id,
        role: 'assistant',
        content: c.greeting.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await state.insertMessage(greeting);
      msgs.add(greeting);
    }

    if (!mounted) return;
    setState(() {
      _character = c;
      _session = session;
      _messages = msgs;
      _worldbook = worldbook;
      _memories = memories;
      _loading = false;
    });
    _userScrolled = false;
    if (widget.initialSearchTargetId != null) {
      _jumpToMessage(widget.initialSearchTargetId!);
    }
    for (final ms in const [0, 50, 200]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted && !_userScrolled) _jumpToBottom(animate: false);
      });
    }
  }

  ProviderConfig? _resolveProvider(AppState state) =>
      state.getProviderById(_character?.providerId);

  EffectiveSettings get _eff {
    final state = context.read<AppState>();
    final c = _character;
    return c != null ? resolveCharacter(state.settings, c) : resolveSettings(state.settings);
  }

  String get _modelName {
    final c = _character;
    if (c?.model?.isNotEmpty == true) return c!.model!;
    final state = context.read<AppState>();
    final p = _resolveProvider(state);
    return p?.model ?? '未配置接口';
  }

  // ---------------- send ----------------
  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _streaming) return;
    final state = context.read<AppState>();
    final session = _session;
    if (session == null) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await state.insertMessage(ChatMessage(
      id: id,
      sessionId: session.id,
      role: 'user',
      content: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    setState(() {
      _messages.add(ChatMessage(
        id: id,
        sessionId: session.id,
        role: 'user',
        content: text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _input.clear();
    });
    _jumpToBottom();
    await _streamReply(state);
  }

  Future<void> _streamReply(AppState state) async {
    if (_streaming) return;
    final character = _character;
    final provider = _resolveProvider(state);
    if (character == null) return;
    if (provider == null) {
      _toast('请先在设置中添加并配置接口');
      return;
    }
    setState(() {
      _streaming = true;
      _streamText = '';
      _streamReasoning = '';
    });
    _jumpToBottom();

    final history = _messages.where((m) => m.role != 'system').toList();
    final payload = PromptBuilder.buildMessages(
      character: character,
      eff: resolveCharacter(state.settings, character),
      worldbook: _worldbook,
      memories: _memories,
      history: history,
    );
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    try {
      await for (final delta in ApiClient().streamChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: (character.model?.isNotEmpty ?? false) ? character.model! : provider.model,
        messages: payload,
        temperature: 0.9,
      )) {
        if (!mounted) return;
        setState(() {
          if (delta.content.isNotEmpty) _streamText += delta.content;
          if (delta.reasoning.isNotEmpty) _streamReasoning += delta.reasoning;
        });
        _jumpToBottom();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _streamText += '\n[错误] ${e.message}');
    }

    final finalText = _streamText.trim();
    final asst = ChatMessage(
      id: id,
      sessionId: _session!.id,
      role: 'assistant',
      content: finalText,
      reasoning: _streamReasoning.trim(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await state.insertMessage(asst);
    if (mounted) {
      setState(() {
        _messages.add(asst);
        _streaming = false;
        _streamText = '';
      });
      _showReasoning = false;
    }
    await _autoMemory(state);
  }

  /// 自动生成长记忆（按设置间隔触发）
  Future<void> _autoMemory(AppState state) async {
    final every = _character != null
        ? resolveCharacter(state.settings, _character!).autoMemoryEvery
        : state.settings.autoMemoryEvery;
    if (!state.settings.memoryEnabled || _messages.length % every != 0) return;
    final provider = _resolveProvider(state);
    if (provider == null || _character == null) return;
    final history = _messages.where((m) => m.role != 'system').toList();
    if (history.isEmpty) return;
    final payload = <Map<String, String>>[
      {'role': 'system', 'content': '总结最近对话里值得长期记住的关键信息（关系/偏好/约定），用一句话陈述；若无则输出"无"。'},
      for (final m in (history.length > 8 ? history.sublist(history.length - 8) : history))
        {'role': m.role == 'user' ? 'user' : 'assistant', 'content': m.content},
    ];
    try {
      final t = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: (_character!.model?.isNotEmpty ?? false) ? _character!.model! : provider.model,
        messages: payload,
      )).trim();
      if (t.isNotEmpty && t != '无' && t != '"无"') {
        await state.addMemory(MemoryItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          characterId: _character!.id,
          content: t,
        ));
        final ms = await state.memoriesFor(_character!.id);
        if (mounted) setState(() => _memories = ms);
      }
    } catch (_) {
      // 忽略自动记忆失败
    }
  }

  // ---------------- actions ----------------
  Future<void> _deleteMessage(ChatMessage m) async {
    final state = context.read<AppState>();
    await state.deleteMessage(m.id);
    setState(() => _messages.removeWhere((x) => x.id == m.id));
  }

  /// 删除该消息及其之后的所有消息，并同步删除该角色产生的长记忆。
  Future<void> _deleteFromHere(ChatMessage m) async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('删除从这里开始的消息'),
        content: const Text('将删除这条消息及其之后的所有消息，并清除这些消息产生的长期记忆。确定？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted || _session == null) return;
    final idx = _messages.indexWhere((x) => x.id == m.id);
    if (idx < 0) return;
    await state.deleteMessagesFrom(_session!.id, null, m.createdAt,
        memoryOwners: [widget.characterId]);
    setState(() => _messages = _messages.sublist(0, idx));
    _jumpToBottom(animate: false);
  }

  Future<void> _editMessage(ChatMessage m, {bool isUser = false}) async {
    final ctrl = TextEditingController(text: m.content);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(controller: ctrl, maxLines: 6, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      final state = context.read<AppState>();
      final newContent = ctrl.text.trim();
      await state.updateMessageContent(m.id, newContent);
      setState(() {
        final idx = _messages.indexWhere((x) => x.id == m.id);
        if (idx >= 0) _messages[idx] = _messages[idx].copyWith(content: newContent);
      });
      // 用户编辑后自动重新生成回复
      if (isUser) {
        await _streamReply(state);
      }
    }
  }

  /// 让角色继续接着上一条回复自然续写（不插入用户消息，角色自己生成新消息）。
  Future<void> _continueReply() async {
    if (_streaming) return;
    final state = context.read<AppState>();
    final character = _character;
    final provider = _resolveProvider(state);
    if (character == null || provider == null) {
      _toast('请先配置接口');
      return;
    }
    final session = _session;
    if (session == null) return;
    // 构造续写 payload：历史 + 一条要求继续的 system 提示（不持久化用户消息）
    final history = _messages.where((m) => m.role != 'system').toList();
    final payload = PromptBuilder.buildMessages(
      character: character,
      eff: resolveCharacter(state.settings, character),
      worldbook: _worldbook,
      memories: _memories,
      history: history,
    );
    payload.add({
      'role': 'user',
      'content': '请接着你上一句话继续说下去，自然续写，不要重复。',
    });
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _streaming = true;
      _streamText = '';
      _streamReasoning = '';
    });
    _jumpToBottom();
    try {
      await for (final delta in ApiClient().streamChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: (character.model?.isNotEmpty ?? false) ? character.model! : provider.model,
        messages: payload,
        temperature: 0.9,
      )) {
        if (!mounted) return;
        setState(() {
          if (delta.content.isNotEmpty) _streamText += delta.content;
          if (delta.reasoning.isNotEmpty) _streamReasoning += delta.reasoning;
        });
        _jumpToBottom();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _streamText += '\n[错误] ${e.message}');
    }
    final asst = ChatMessage(
      id: id,
      sessionId: session.id,
      role: 'assistant',
      content: _streamText.trim(),
      reasoning: _streamReasoning.trim(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await state.insertMessage(asst);
    if (mounted) {
      setState(() {
        _messages.add(asst);
        _streaming = false;
        _streamText = '';
      });
      _showReasoning = false;
    }
    await _autoMemory(state);
  }

  Future<void> _regenerate() async {
    final state = context.read<AppState>();
    final provider = _resolveProvider(state);
    if (provider == null) {
      _toast('请先配置接口');
      return;
    }
    int lastAssistant = -1;
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == 'assistant' && !_messages[i].id.startsWith('g_')) {
        lastAssistant = i;
        break;
      }
    }
    if (lastAssistant == -1) {
      _toast('没有可重新生成的消息');
      return;
    }
    final removed = _messages[lastAssistant];
    await state.deleteMessage(removed.id);
    setState(() => _messages.removeAt(lastAssistant));
    await _streamReply(state);
  }

  /// AI 生成用户下一句回复，填入输入框（不发送）
  Future<void> _generateUserMessage() async {
    final state = context.read<AppState>();
    final provider = _resolveProvider(state);
    if (provider == null) {
      _toast('请先配置接口');
      return;
    }
    final eff = _eff;
    final history = _messages.where((m) => m.role != 'system').toList();
    final payload = <Map<String, String>>[
      {
        'role': 'system',
        'content':
            '你是玩家「${eff.userName}」（${eff.userGender}，与角色的关系：${eff.userRelation.isEmpty ? '朋友' : eff.userRelation}）。'
            '你是正在和角色对话的那个人。\\n${eff.userBackground.isEmpty ? '' : '你的身份背景：${eff.userBackground}'}'
      },
    ];
    for (final m in history) {
      payload.add({'role': m.role, 'content': m.content});
    }
    payload.add({
      'role': 'user',
      'content': '请以玩家「${eff.userName}」的身份，说出下一句自然的话，直接输出内容，不要解释或引号。',
    });
    try {
      setState(() {
        _input.clear();
        _generating = true;
      });
      final text = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: (_character!.model?.isNotEmpty ?? false) ? _character!.model! : provider.model,
        messages: payload,
        temperature: 0.9,
      )).trim();
      if (mounted) {
        setState(() {
          _input.text = text;
          _generating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generating = false);
        _toast('生成失败: $e');
      }
    }
  }

  /// 润色一句话，用于输入框的 AI 改写按钮。
  Future<String> _rewriteText(String text) async {
    final state = context.read<AppState>();
    final provider = _resolveProvider(state);
    if (provider == null) {
      _toast('请先配置接口');
      return text;
    }
    final result = await ApiClient().completeChat(
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      model: (_character!.model?.isNotEmpty ?? false) ? _character!.model! : provider.model,
      messages: [
        {'role': 'system', 'content': '把下面这句话润色成更自然的角色扮演输入，保留原意，直接输出。'},
        {'role': 'user', 'content': text},
      ],
    );
    return result.trim();
  }

  Future<void> _rewriteUserMessage(ChatMessage m) async {
    final state = context.read<AppState>();
    final provider = _resolveProvider(state);
    if (provider == null) {
      _toast('请先配置接口');
      return;
    }
    try {
      setState(() {
        _input.clear();
        _generating = true;
      });
      final text = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: (_character!.model?.isNotEmpty ?? false) ? _character!.model! : provider.model,
        messages: [
          {'role': 'system', 'content': '把下面这句话润色成更自然的角色扮演输入，保留原意，直接输出。'},
          {'role': 'user', 'content': m.content},
        ],
      )).trim();
      if (mounted) {
        setState(() {
          _generating = false;
        });
        // 改写后替换原消息并触发角色自动回复
        await _replaceUserAndReply(state, m, text);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generating = false);
        _toast('改写失败: $e');
      }
    }
  }

  /// 把某条用户消息替换为新内容，并让角色自动回复。
  Future<void> _replaceUserAndReply(AppState state, ChatMessage m, String text) async {
    await state.updateMessageContent(m.id, text);
    setState(() {
      final idx = _messages.indexWhere((x) => x.id == m.id);
      if (idx >= 0) _messages[idx] = _messages[idx].copyWith(content: text);
    });
    await _streamReply(state);
  }

  Future<void> _copy(ChatMessage m) async {
    await Clipboard.setData(ClipboardData(text: m.content));
    if (mounted) _toast('已复制');
  }

  Future<void> _showModelSwitch() async {
    final state = context.read<AppState>();
    final character = _character;
    if (character == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ModelSwitchSheet(
        character: character,
        providers: state.providers,
        onPick: (providerId, model) async {
          final updated = _character!.copyWith(providerId: providerId, model: model);
          await state.updateCharacter(updated);
          if (mounted) setState(() => _character = updated);
        },
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _jumpToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      _programmaticJump = true;
      if (animate) {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(target);
      }
      _programmaticJump = false;
    });
  }

  /// 查找聊天记录后跳转到某条消息，并高亮它；顶部显示"返回查找结果"条。
  void _jumpToMessage(String id) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx < 0 || !mounted) return;
    setState(() => _searchReturnIndex = idx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _programmaticJump = true;
      final target = _messages.length == 0
          ? 0.0
          : (_scroll.position.maxScrollExtent * (idx / _messages.length))
              .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      _programmaticJump = false;
    });
  }

  Future<void> _openChatMenu(AppState state) async {
    final character = _character;
    if (character == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit), title: const Text('角色设置'), onTap: () => Navigator.pop(ctx, 'char')),
            ListTile(leading: const Icon(Icons.tune), title: const Text('聊天窗口设置'), onTap: () => Navigator.pop(ctx, 'settings')),
            ListTile(leading: const Icon(Icons.psychology), title: const Text('长期记忆'), onTap: () => Navigator.pop(ctx, 'memory')),
            ListTile(leading: const Icon(Icons.search), title: const Text('查找聊天记录'), onTap: () => Navigator.pop(ctx, 'search')),
            ListTile(leading: const Icon(Icons.history), title: const Text('删除当前对话'), onTap: () => Navigator.pop(ctx, 'clear')),
            ListTile(leading: const Icon(Icons.menu_book), title: const Text('选择世界书'), onTap: () => Navigator.pop(ctx, 'worldbook')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'char':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => CharacterEditorScreen(character: character)));
        await _load();
        break;
      case 'settings':
        _showContextSettings(state);
        break;
      case 'memory':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => MemoryScreen(characterId: character.id)));
        final ms = await state.memoriesFor(character.id);
        if (mounted) setState(() => _memories = ms);
        break;
      case 'search':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SearchHistoryScreen(characterId: character.id)),
        );
        break;
      case 'worldbook':
        {
          final r = await showWorldbookPicker(context, initial: character.worldbookIds);
          if (r == null || !mounted) break;
          if (r.manage) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const WorldbookScreen()));
            break;
          }
          await state.updateCharacter(character.copyWith(worldbookIds: r.ids));
          await _load();
        }
        break;
      case 'clear':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('删除对话'),
            content: const Text('删除当前会话的所有聊天记录？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除')),
            ],
          ),
        );
        if (ok == true && mounted && _session != null) {
          await state.deleteSession(_session!.id);
          if (mounted) Navigator.pop(context);
        }
        break;
    }
  }

  void _showContextSettings(AppState state) {
    final parentSetState = setState;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sheetSetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('聊天窗口设置', style: TextStyle(fontWeight: FontWeight.bold)),
                SwitchListTile(
                  dense: true,
                  title: const Text('显示角色头像'),
                  value: _hideCharAvatar != true,
                  onChanged: (v) {
                    setState(() => _hideCharAvatar = !v);
                    sheetSetState(() {});
                    parentSetState(() {});
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('显示我的头像'),
                  value: _hideUserAvatar != true,
                  onChanged: (v) {
                    setState(() => _hideUserAvatar = !v);
                    sheetSetState(() {});
                    parentSetState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final c = _character!;
    final state = context.watch<AppState>();
    final showCharAvatar = _hideCharAvatar == null ? true : !_hideCharAvatar!;
    final showUserAvatar = _hideUserAvatar == null ? true : !_hideUserAvatar!;
    final effBg = _effectiveBackground(state, c);
    final hasBg = effBg.isNotEmpty && File(effBg).existsSync();
    final topInset = 0.0;

    return Scaffold(
      extendBodyBehindAppBar: hasBg,
      appBar: AppBar(
        backgroundColor: hasBg ? Colors.transparent : null,
        elevation: hasBg ? 0 : null,
        title: Column(
          children: [
            Text(c.name, style: const TextStyle(fontSize: 16)),
            Text(_modelName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _openChatMenu(state))],
      ),
      body: _buildBody(state, c, showCharAvatar, showUserAvatar, effBg, hasBg),
    );
  }

  double get _topInset => MediaQuery.of(context).viewPadding.top + kToolbarHeight;

  Widget _buildBody(AppState state, Character c, bool sc, bool su, String effBg, bool hasBg) {
    final topInset = hasBg ? _topInset : 0.0;
    if (!hasBg) {
      return Column(
        children: [
          Expanded(child: _messageList(state, c, sc, su, 0)),
          _inputBar(state, c),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: Image.file(File(effBg), fit: BoxFit.cover)),
        Positioned.fill(
          child: Column(
            children: [
              Expanded(child: _messageList(state, c, sc, su, topInset)),
              _inputBar(state, c),
            ],
          ),
        ),
      ],
    );
  }

  String _effectiveBackground(AppState state, Character c) {
    return c.chatBackground;
  }

  Widget _messageList(AppState state, Character c, bool showCharAvatar, bool showUserAvatar, double topInset) {
    final showBanner = _searchReturnIndex >= 0;
    final bannerOffset = showBanner ? 1 : 0;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.only(top: topInset + 8, bottom: 12),
      itemCount: bannerOffset + _messages.length + (_streaming ? 1 : 0),
      itemBuilder: (context, i) {
        if (showBanner && i == 0) {
          return _searchReturnBanner();
        }
        final msgIdx = i - bannerOffset;
        if (msgIdx < _messages.length) {
          final m = _messages[msgIdx];
          final isLast = msgIdx == _messages.length - 1;
          final reasoning = (m.role == 'assistant' && m.reasoning.isNotEmpty) ? m.reasoning : '';
          return MessageBubble(
            message: m,
            isUser: m.role == 'user',
            avatar: m.role == 'user'
                ? buildUserAvatar(context, state.settings, 34)
                : buildCharacterAvatar(context, c, 34),
            senderName: m.role == 'user' ? state.settings.personaName : c.name,
            showAvatar: m.role == 'user' ? showUserAvatar : showCharAvatar,
            footer: isLast && !_streaming ? _actionFooter(state, m) : null,
            topContent: reasoning.isNotEmpty ? ThinkingToggle(reasoning: reasoning) : null,
            bubbleColor: m.role == 'user'
                ? parseHexColor(state.settings.bubbleSelfColor)
                : parseHexColor(state.settings.bubbleCharColor),
            bubbleOpacity: state.settings.bubbleOpacity,
            fontScale: state.settings.fontSize,
            highlight: _searchReturnIndex >= 0 && msgIdx == _searchReturnIndex,
            onCopy: () => _copy(m),
            onDelete: () => _deleteMessage(m),
            onDeleteFromHere: () => _deleteFromHere(m),
          );
        }
        final streamingMsg = ChatMessage(
          id: 'st', sessionId: _session!.id, role: 'assistant', content: _streamText, createdAt: 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_streaming && _streamText.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text('$c.name 正在思考…', style: const TextStyle(color: Colors.blueGrey)),
                  ],
                ),
              ),
            if (_streamReasoning.isNotEmpty && state.settings.outputThinking) _reasoningBox(state, c),
            MessageBubble(
              message: streamingMsg,
              isUser: false,
              avatar: buildCharacterAvatar(context, c, 34),
              senderName: c.name,
              showAvatar: showCharAvatar,
              isCurrent: true,
              fontScale: state.settings.fontSize,
            ),
          ],
        );
      },
    );
  }

  Widget _searchReturnBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18),
          const SizedBox(width: 8),
          const Expanded(child: Text('已定位到查找的消息', style: TextStyle(fontSize: 13))),
          TextButton(
            onPressed: () => setState(() => _searchReturnIndex = -1),
            child: const Text('结束查找'),
          ),
        ],
      ),
    );
  }

  Widget _reasoningBox(AppState state, Character c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: () => setState(() => _showReasoning = !_showReasoning),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology, size: 16),
                    const SizedBox(width: 6),
                    Text(_showReasoning ? '收起思考' : '思考过程'),
                    const Spacer(),
                    Icon(_showReasoning ? Icons.expand_less : Icons.expand_more, size: 18),
                  ],
                ),
                if (_showReasoning)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_streamReasoning, style: const TextStyle(fontSize: 12, height: 1.4)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 最新一轮消息下方的操作条（透明圆角，纯图标）
  Widget _actionFooter(AppState state, ChatMessage m) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: _generating || _streaming,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: m.role == 'user'
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              _btn(scheme, Icons.delete_outline, () => _deleteMessage(m)),
              _btn(scheme, Icons.edit, () => _editMessage(m, isUser: true)),
              _btn(scheme, _continueIcon, () => _continueReply()),
              _btn(scheme, Icons.auto_awesome, () => _rewriteUserMessage(m)),
            ])
          : Row(mainAxisSize: MainAxisSize.min, children: [
              _btn(scheme, Icons.refresh, () => _regenerate()),
              _btn(scheme, Icons.delete_outline, () => _deleteMessage(m)),
              _btn(scheme, Icons.edit, () => _editMessage(m)),
              _btn(scheme, _continueIcon, () => _continueReply()),
              _btn(scheme, Icons.chat_bubble_outline, () => _generateUserMessage()),
            ]),
      ),
    );
  }

  static const IconData _continueIcon = Icons.arrow_forward_ios;

  Widget _btn(ColorScheme scheme, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 19, color: scheme.primary),
      ),
    );
  }

  Widget _inputBar(AppState state, Character c) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            InkWell(
              onTap: _streaming ? null : _showModelSwitch,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.model_training, size: 22),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AiRewriteButton(
                    controller: _input,
                    rewrite: _rewriteText,
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 10,
                    onRewriting: (v) => setState(() => _inputRewriting = v),
                  ),
                  const SizedBox(height: 2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 56),
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 3,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: _inputRewriting ? '正在改写…' : (_generating ? '正在生成…' : '发一条消息…'),
                        filled: true,
                        isDense: true,
                        fillColor: Theme.of(context).brightness == Brightness.dark
                            ? Colors.black.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.send, size: 24),
              onPressed: (_streaming || _generating || _inputRewriting) ? null : _send,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasoningCard extends StatefulWidget {
  final String reasoning;
  const _ReasoningCard({required this.reasoning});
  @override
  State<_ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<_ReasoningCard> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    if (widget.reasoning.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 60, 0),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology, size: 16),
                    const SizedBox(width: 6),
                    Text(_open ? '收起思考' : '思考过程'),
                    const Spacer(),
                    Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
                  ],
                ),
                if (_open)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(widget.reasoning, style: const TextStyle(fontSize: 12, height: 1.4)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelSwitchSheet extends StatefulWidget {
  final Character character;
  final List<ProviderConfig> providers;
  final Future<void> Function(String providerId, String model) onPick;
  const _ModelSwitchSheet({required this.character, required this.providers, required this.onPick});

  @override
  State<_ModelSwitchSheet> createState() => _ModelSwitchSheetState();
}

class _ModelSwitchSheetState extends State<_ModelSwitchSheet> {
  String? _selectedProviderId;
  List<String> _models = [];
  bool _fetching = false;
  final TextEditingController _modelCtrl = TextEditingController();
  ProviderConfig? _selectedProvider;

  @override
  void initState() {
    super.initState();
    final cur = widget.character.providerId;
    _selectedProviderId = cur;
    if (cur != null) {
      for (final p in widget.providers) {
        if (p.id == cur) {
          _selectedProvider = p;
          _modelCtrl.text = widget.character.model ?? p.model;
          _models = p.models;
          break;
        }
      }
    } else {
      _modelCtrl.text = widget.character.model ?? '';
    }
  }

  Future<void> _fetchModels() async {
    final p = _selectedProvider;
    if (p == null || p.apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先填写该接口的 Key')));
      return;
    }
    setState(() => _fetching = true);
    try {
      final models = await ApiClient().getModels(baseUrl: p.baseUrl, apiKey: p.apiKey);
      setState(() => _models = models);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取失败: $e')));
    } finally {
      setState(() => _fetching = false);
    }
  }

  Future<void> _choose() async {
    await widget.onPick(_selectedProviderId ?? '', _modelCtrl.text.trim());
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('切换模型', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          for (final p in widget.providers)
            RadioListTile<String>(
              dense: true,
              title: Text(p.name),
              subtitle: Text('${p.baseUrl} · ${p.model}', maxLines: 1, overflow: TextOverflow.ellipsis),
              value: p.id,
              groupValue: _selectedProviderId,
              onChanged: (v) => setState(() {
                _selectedProviderId = v;
                _selectedProvider = p;
                _models = p.models;
                _modelCtrl.text = widget.character.model?.isNotEmpty == true
                    ? widget.character.model!
                    : p.model;
              }),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(labelText: '模型名', hintText: 'gpt-4o / deepseek-chat'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: _fetching
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.list),
                label: const Text('获取模型'),
                onPressed: _fetching ? null : _fetchModels,
              ),
            ],
          ),
          if (_models.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _models
                  .take(30)
                  .map((m) => ActionChip(
                        label: Text(m, style: const TextStyle(fontSize: 12)),
                        onPressed: () => setState(() => _modelCtrl.text = m),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _choose, child: const Text('确定')),
          ),
        ],
      ),
    );
  }
}
