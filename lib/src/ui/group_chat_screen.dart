import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/prompt_builder.dart';
import '../services/settings_resolver.dart';
import '../utils/colors.dart';
import '../state/app_state.dart';
import 'widgets/avatars.dart';
import 'widgets/message_bubble.dart';
import 'widgets/thinking_toggle.dart';
import 'group_create_screen.dart';
import 'character_editor_screen.dart';
import 'memory_screen.dart';
import 'worldbook_screen.dart';
import 'worldbook_picker.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  const GroupChatScreen({super.key, required this.groupId});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  ChatGroup? _group;
  List<ChatMessage> _messages = [];
  Map<String, Character> _members = {};
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _streaming = false;
  bool _generating = false;
  String _streamSender = '';
  String _streamText = '';
  String _streamReasoning = '';
  bool _loading = true;
  int _turn = 0; // 用于轮流回复起始位置
  bool _userScrolled = false;
  bool _programmaticJump = false;

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
    final g = await state.getGroup(widget.groupId);
    Map<String, Character> members = {};
    if (g != null) {
      for (final mid in g.memberIds) {
        final c = await state.getCharacter(mid);
        if (c != null) members[mid] = c;
      }
    }
    final msgs = g == null ? <ChatMessage>[] : await state.groupMessages(g.id);
    if (!mounted) return;
    setState(() {
      _group = g;
      _members = members;
      _messages = msgs;
      _loading = false;
    });
    _userScrolled = false;
    for (final ms in const [0, 50, 200]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted && !_userScrolled) _jumpToBottom(animate: false);
      });
    }
  }

  ProviderConfig? _providerFor(Character c, AppState state) {
    final g = _group;
    if (g != null && g.providerId != null && g.providerId!.isNotEmpty) {
      return state.getProviderById(g.providerId);
    }
    return state.getProviderById(c.providerId);
  }

  String _replyModelFor(Character c, ProviderConfig p) {
    final g = _group;
    if (g != null && g.model?.isNotEmpty == true) return g.model!;
    if (c.model?.isNotEmpty == true) return c.model!;
    return p.model;
  }
  EffectiveSettings get _eff => _group == null
      ? resolveSettings(context.read<AppState>().settings)
      : resolveGroup(context.read<AppState>().settings, _group!);

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _streaming) return;
    final state = context.read<AppState>();
    final g = _group;
    if (g == null) return;

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final userMsg = ChatMessage(
      id: id,
      groupId: g.id,
      role: 'user',
      content: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await state.insertMessage(userMsg);
    setState(() {
      _messages.add(userMsg);
      _input.clear();
    });
    _jumpToBottom();

    if (g.replyMode == 'designated') return;

    await _triggerReplies(state, g);
  }

  Future<void> _autoAll(AppState state, ChatGroup g) async {
    final members = _members.values.toList();
    if (members.isEmpty) return;
    final last = _messages.isNotEmpty ? _messages.last.content : '';
    final mentioned = members.where((m) => last.contains(m.name)).toList();
    final rest = members.where((m) => !mentioned.contains(m)).toList();
    final order = [...mentioned, ...rest];
    for (final m in order) {
      if (!mounted) return;
      await _streamReply(state, g, m, m.id);
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<void> _autoNatural(AppState state, ChatGroup g) async {
    final members = _members.values.toList();
    if (members.isEmpty) return;
    // 轮流：从上次起始位置之后开始
    int start = _turn % members.length;
    final order = [...members.sublist(start), ...members.sublist(0, start)];
    var replied = 0;
    for (final m in order) {
      if (!mounted) return;
      if (await _shouldReply(state, g, m)) {
        await _streamReply(state, g, m, m.id);
        replied++;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    _turn++;
    if (replied == 0 && order.isNotEmpty) {
      // 至少一人回复
      await _streamReply(state, g, order.first, order.first.id);
    }
  }

  Future<bool> _shouldReply(AppState state, ChatGroup g, Character character) async {
    final provider = _providerFor(character, state);
    if (provider == null) return false;
    final last = _messages.isNotEmpty ? _messages.last.content : '';
    try {
      final r = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: (character.model?.isNotEmpty ?? false) ? character.model! : provider.model,
        messages: [
          {
            'role': 'system',
            'content': '你是「${character.name}」。有人刚在群里说话，根据你的性格判断你是否要开口回应。只回复：是 或 否。'
          },
          {'role': 'user', 'content': last},
        ],
      )).trim();
      return r.contains('是');
    } catch (_) {
      return false;
    }
  }

  Future<void> _designatedReply(Character c) async {
    if (_streaming) return;
    final state = context.read<AppState>();
    final g = _group;
    if (g == null) return;
    await _streamReply(state, g, c, c.id);
  }

  // ---------------- latest-round actions ----------------
  Future<void> _deleteMessage(ChatMessage m) async {
    final state = context.read<AppState>();
    await state.deleteMessage(m.id);
    setState(() => _messages.removeWhere((x) => x.id == m.id));
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
      final nc = ctrl.text.trim();
      await state.updateMessageContent(m.id, nc);
      setState(() {
        final idx = _messages.indexWhere((x) => x.id == m.id);
        if (idx >= 0) _messages[idx] = _messages[idx].copyWith(content: nc);
      });
      if (isUser) await _triggerReplies(state, _group!);
    }
  }

  Future<void> _triggerReplies(AppState state, ChatGroup g) async {
    if (g.replyMode == 'designated') return;
    if (g.replyMode == 'natural') {
      await _autoNatural(state, g);
    } else {
      await _autoAll(state, g);
    }
  }

  Future<void> _regenerateMessage(ChatMessage m) async {
    if (_streaming) return;
    final state = context.read<AppState>();
    final g = _group;
    if (g == null || m.senderCharacterId == null) return;
    final character = _members[m.senderCharacterId];
    if (character == null) return;
    await state.deleteMessage(m.id);
    setState(() => _messages.removeWhere((x) => x.id == m.id));
    await _streamReply(state, g, character, character.id);
  }

  Future<void> _generateMyReply() async {
    final state = context.read<AppState>();
    final g = _group;
    if (g == null) return;
    final provider = state.getProviderById(null);
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先配置接口')));
      return;
    }
    final eff = _eff;
    final payload = <Map<String, String>>[
      {
        'role': 'system',
        'content': '你是玩家「${eff.userName}」，正在群里和 ${_members.values.map((m) => m.name).join('、')} 聊天。'
            '请以玩家的身份说下一句，直接输出内容，不要解释或引号。'
      },
    ];
    for (final m in _messages) {
      payload.add({'role': m.role == 'user' ? 'user' : 'assistant', 'content': m.content});
    }
    try {
      setState(() {
        _input.clear();
        _generating = true;
      });
      final text = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: provider.model,
        messages: payload,
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
      }
    }
  }

  Future<void> _rewriteUser(ChatMessage m) async {
    final state = context.read<AppState>();
    final provider = state.getProviderById(null);
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先配置接口')));
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
        model: provider.model,
        messages: [
          {'role': 'system', 'content': '把下面这句话润色成更自然的角色扮演输入，保留原意，直接输出。'},
          {'role': 'user', 'content': m.content},
        ],
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('改写失败: $e')));
      }
    }
  }

  Widget _actionFooter(AppState state, ChatMessage m) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: m.role == 'user'
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              _btn(scheme, Icons.delete_outline, '删除', () => _deleteMessage(m)),
              _btn(scheme, Icons.edit, '编辑', () => _editMessage(m, isUser: true)),
              _btn(scheme, Icons.auto_awesome, 'AI改写', () => _rewriteUser(m)),
            ])
          : Row(mainAxisSize: MainAxisSize.min, children: [
              _btn(scheme, Icons.refresh, '重生成', () => _regenerateMessage(m)),
              _btn(scheme, Icons.delete_outline, '删除', () => _deleteMessage(m)),
              _btn(scheme, Icons.edit, '编辑', () => _editMessage(m)),
              _btn(scheme, Icons.chat_bubble_outline, '生成我的回复', () => _generateMyReply()),
            ]),
    );
  }

  Widget _btn(ColorScheme scheme, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.primary),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(fontSize: 11, color: scheme.primary)),
          ],
        ),
      ),
    );
  }

  Future<void> _streamReply(AppState state, ChatGroup g, Character character, String senderCharId) async {
    if (_streaming) return;
    final provider = _providerFor(character, state);
    if (provider == null) {
      await state.insertMessage(ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        groupId: g.id,
        role: 'assistant',
        senderCharacterId: senderCharId,
        content: '（$character.name 未配置接口）',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      return;
    }
    final histories = _messages.where((m) => m.role != 'system').toList();
    final gwb = g.worldbookIds.isEmpty
        ? <WorldbookEntry>[]
        : (await state.worldbookFor(null)).where((e) => g.worldbookIds.contains(e.id)).toList();
    final payload = PromptBuilder.buildGroupMessages(
      character: character,
      eff: _eff,
      worldbook: gwb,
      memories: await state.memoriesFor(character.id),
      groupMemories: await state.memoriesFor('group_${g.id}'),
      history: histories,
      groupNames: _members.values.map((m) => m.name).toList(),
      replyStyle: g.replyStyle,
    );

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _streaming = true;
      _streamSender = character.name;
      _streamText = '';
      _streamReasoning = '';
    });
    _jumpToBottom();

    try {
      await for (final delta in ApiClient().streamChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: _replyModelFor(character, provider),
        messages: payload,
        temperature: 0.9,
      )) {
        if (!mounted) return;
        if (delta.content.isNotEmpty) setState(() => _streamText += delta.content);
        if (delta.reasoning.isNotEmpty) setState(() => _streamReasoning += delta.reasoning);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _streamText += '\n[错误] ${e.message}');
    }

    final finalText = _streamText.trim();
    final asst = ChatMessage(
      id: id,
      groupId: g.id,
      role: 'assistant',
      senderCharacterId: senderCharId,
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
        _streamReasoning = '';
      });
    }
    _jumpToBottom();
    if (g.autoMemoryEvery > 0 && g.autoMemoryEvery <= _messages.length &&
        _messages.length % g.autoMemoryEvery == 0 && state.settings.memoryEnabled) {
      _autoMemory(state, g);
    }
  }

  Future<void> _autoMemory(AppState state, ChatGroup g) async {
    final provider = state.getProviderById(null);
    if (provider == null) return;
    final history = _messages.where((m) => m.role != 'system').toList();
    if (history.isEmpty) return;
    final tail = history.length > 8 ? history.sublist(history.length - 8) : history;
    try {
      final t = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: provider.model,
        messages: [
          {'role': 'system', 'content': '总结最近群聊里值得长期记住的关键信息，用一句话陈述；若无则输出"无"。'},
          for (final m in tail)
            {'role': m.role == 'user' ? 'user' : 'assistant', 'content': '${m.senderCharacterId ?? '我'}：${m.content}'},
        ],
      )).trim();
      if (t.isNotEmpty && t != '无' && t != '"无"') {
        await state.addMemory(MemoryItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          characterId: 'group_${g.id}',
          content: t,
        ));
      }
    } catch (_) {}
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

  Future<void> _openMembers(AppState state) async {
    final g = _group;
    if (g == null) return;
    final total = _members.length + 1; // + 自己
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('群成员（$total）', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // 自己置顶
                  ListTile(
                    leading: buildUserAvatar(context, state.settings, 40),
                    title: Text('${state.settings.personaName}（我）'),
                    subtitle: const Text('群主'),
                  ),
                  for (final c in _members.values)
                    ListTile(
                      leading: buildCharacterAvatar(context, c, 40),
                      title: Text(c.name),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => CharacterEditorScreen(character: c)));
                        await _load();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final g = _group!;
    final state = context.watch<AppState>();
    final effBg = g.background;
    final hasBg = effBg.isNotEmpty && File(effBg).existsSync();

    return Scaffold(
      extendBodyBehindAppBar: hasBg,
      appBar: AppBar(
        backgroundColor: hasBg ? Colors.transparent : null,
        elevation: hasBg ? 0 : null,
        title: Column(
          children: [
            Text(g.name, style: const TextStyle(fontSize: 16)),
            Text('${_members.length + 1} 人', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.group), onPressed: () => _openMembers(state)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'settings') {
                _showGroupChatSettings(state, g);
              } else if (v == 'memory') {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => MemoryScreen(characterId: 'group_${g.id}')));
                if (mounted) setState(() {});
              } else if (v == 'worldbook') {
                final r = await showWorldbookPicker(context, initial: g.worldbookIds);
                if (r == null || !mounted) return;
                if (r.manage) {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const WorldbookScreen()));
                  return;
                }
                await state.updateGroup(g.copyWith(worldbookIds: r.ids));
                await _load();
              } else if (v == 'edit') {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => GroupCreateScreen(group: g)));
                await _load();
              } else if (v == 'delete') {
                await context.read<AppState>().deleteGroup(g.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('聊天窗口设置')),
              PopupMenuItem(value: 'memory', child: Text('长期记忆')),
              PopupMenuItem(value: 'worldbook', child: Text('世界书')),
              PopupMenuItem(value: 'edit', child: Text('编辑群聊')),
              PopupMenuItem(value: 'delete', child: Text('删除群聊')),
            ],
          ),
        ],
      ),
      body: hasBg
          ? Stack(
              children: [
                Positioned.fill(child: Image.file(File(effBg), fit: BoxFit.cover)),
                Positioned.fill(child: _column(state, g)),
              ],
            )
          : _column(state, g),
    );
  }

  double get _topInset => MediaQuery.of(context).viewPadding.top + kToolbarHeight;

  Widget _column(AppState state, ChatGroup g) {
    final effBg = g.background;
    final hasBg = effBg.isNotEmpty && File(effBg).existsSync();
    final topInset = hasBg ? _topInset : 0.0;
    return Column(
      children: [
        Expanded(child: _messageList(state, g, topInset)),
        if (g.replyMode == 'designated') _designatedRow(state, g),
        _inputBar(state, g),
      ],
    );
  }

  Widget _messageList(AppState state, ChatGroup g, double topInset) {
    final showCharAvatar = _hideCharAvatar == null ? true : !_hideCharAvatar;
    final showUserAvatar = _hideUserAvatar == null ? true : !_hideUserAvatar;
    final last = _messages.isNotEmpty ? _messages.length - 1 : -1;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.only(top: topInset + 8, bottom: 12),
      itemCount: _messages.length + (_streaming ? 1 : 0),
      itemBuilder: (context, i) {
        if (i < _messages.length) {
          final m = _messages[i];
          final foot = (i == last && !_streaming) ? _actionFooter(state, m) : null;
          if (m.role == 'user') {
            return MessageBubble(
              message: m,
              isUser: true,
              avatar: buildUserAvatar(context, state.settings, 34),
              senderName: state.settings.personaName,
              showAvatar: showUserAvatar,
              footer: foot,
              bubbleColor: parseHexColor(state.settings.bubbleSelfColor),
              bubbleOpacity: state.settings.bubbleOpacity,
            );
          }
          final sender = m.senderCharacterId != null ? _members[m.senderCharacterId] : null;
          return MessageBubble(
            message: m,
            isUser: false,
            avatar: sender != null ? buildCharacterAvatar(context, sender, 34) : null,
            senderName: sender?.name ?? '?',
            showAvatar: showCharAvatar,
            footer: foot,
            topContent: m.reasoning.trim().isNotEmpty ? ThinkingToggle(reasoning: m.reasoning) : null,
            bubbleColor: parseHexColor(state.settings.bubbleCharColor),
            bubbleOpacity: state.settings.bubbleOpacity,
          );
        }
        Character? sender;
        for (final c in _members.values) {
          if (c.name == _streamSender) {
            sender = c;
            break;
          }
        }
        final st = ChatMessage(
          id: 'st', role: 'assistant', content: _streamText, createdAt: 0,
          groupId: g.id, senderCharacterId: sender?.id,
        );
        return MessageBubble(
          message: st,
          isUser: false,
          avatar: sender != null ? buildCharacterAvatar(context, sender, 34) : null,
          senderName: _streamSender,
          showAvatar: showCharAvatar,
          isCurrent: true,
        );
      },
    );
  }

  Widget _designatedRow(AppState state, ChatGroup g) {
    return Container(
      height: 54,
      color: Colors.transparent,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _members.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final c = _members.values.elementAt(i);
          return InkWell(
            onTap: () => _designatedReply(c),
            onLongPress: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => CharacterEditorScreen(character: c)));
              await _load();
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 26, height: 26, child: buildCharacterAvatar(context, c, 24)),
                  const SizedBox(width: 5),
                  Text(c.name, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showGroupModelSwitch(AppState state, ChatGroup g) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _GroupModelSheet(
        group: g,
        providers: state.providers,
        onPick: (providerId, model) async {
          _group = _group!.copyWith(
            providerId: providerId.isEmpty ? null : providerId,
            model: model.isEmpty ? null : model,
          );
          await state.updateGroup(_group!);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _showGroupChatSettings(AppState state, ChatGroup g) {
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
                const Text('群聊窗口设置', style: TextStyle(fontWeight: FontWeight.bold)),
                SwitchListTile(
                  dense: true,
                  title: const Text('显示角色头像'),
                  value: !_hideCharAvatar,
                  onChanged: (v) {
                    setState(() => _hideCharAvatar = !v);
                    sheetSetState(() {});
                    parentSetState(() {});
                    if (!v) _warnHideAvatar();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('显示我的头像'),
                  value: !_hideUserAvatar,
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

  bool _hideCharAvatar = false;
  bool _hideUserAvatar = false;

  Future<void> _warnHideAvatar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('隐藏角色头像'),
        content: const Text('群聊中隐藏角色头像将无法区分是谁在说话，确定要隐藏吗？'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(backgroundColor: Colors.grey.shade300),
            onPressed: () => Navigator.pop(d, false),
            child: const Text('取消'),
          ),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok == false && mounted) {
      setState(() => _hideCharAvatar = false);
    }
  }

  Widget _inputBar(AppState state, ChatGroup g) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            InkWell(
              onTap: _streaming ? null : () => _showGroupModelSwitch(state, g),
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
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 56),
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: _generating ? '正在生成…' : '发一条消息…',
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
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.send, size: 24),
              onPressed: _streaming ? null : _send,
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

class _GroupModelSheet extends StatefulWidget {
  final ChatGroup group;
  final List<ProviderConfig> providers;
  final Future<void> Function(String providerId, String model) onPick;
  const _GroupModelSheet({required this.group, required this.providers, required this.onPick});
  @override
  State<_GroupModelSheet> createState() => _GroupModelSheetState();
}

class _GroupModelSheetState extends State<_GroupModelSheet> {
  String? _pid;
  List<String> _models = [];
  bool _fetching = false;
  final TextEditingController _model = TextEditingController();
  ProviderConfig? _selected;

  @override
  void initState() {
    super.initState();
    _pid = widget.group.providerId;
    _model.text = widget.group.model ?? '';
    for (final p in widget.providers) {
      if (p.id == _pid) {
        _selected = p;
        _models = p.models;
        break;
      }
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    final p = _selected;
    if (p == null || p.apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先填写该接口的 Key')));
      return;
    }
    setState(() => _fetching = true);
    try {
      final ms = await ApiClient().getModels(baseUrl: p.baseUrl, apiKey: p.apiKey);
      setState(() => _models = ms);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取失败: $e')));
    } finally {
      setState(() => _fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('群聊模型（对该群所有角色生效）', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          for (final p in widget.providers)
            RadioListTile<String?>(
              dense: true,
              title: Text(p.name),
              subtitle: Text(p.model, maxLines: 1, overflow: TextOverflow.ellipsis),
              value: p.id,
              groupValue: _pid,
              onChanged: (v) => setState(() {
                _pid = v;
                _selected = p;
                _models = p.models;
                if (widget.group.model?.isNotEmpty == true) _model.text = widget.group.model!;
              }),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: '模型名（留空用接口默认）', hintText: 'gpt-4o / deepseek-chat'),
                ),
              ),
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
              children: _models.take(30).map((m) => ActionChip(
                    label: Text(m, style: const TextStyle(fontSize: 12)),
                    onPressed: () => setState(() => _model.text = m),
                  )).toList(),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                await widget.onPick(_pid ?? '', _model.text.trim());
                if (mounted) Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ),
        ],
      ),
    );
  }
}
