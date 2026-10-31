import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/memory_helper.dart';
import '../services/prompt_builder.dart';
import '../services/vision_payload.dart';
import '../services/settings_resolver.dart';
import '../utils/colors.dart';
import '../utils/file_adopt.dart';
import '../utils/attachment_text.dart';
import '../utils/image_utils.dart';
import '../state/app_state.dart';
import 'widgets/avatars.dart';
import 'widgets/message_bubble.dart';
import 'widgets/thinking_toggle.dart';
import 'group_create_screen.dart';
import 'character_editor_screen.dart';
import 'memory_screen.dart';
import 'worldbook_screen.dart';
import 'worldbook_picker.dart';
import 'widgets/search_history_screen.dart';
import 'widgets/ai_rewrite_button.dart';
import 'widgets/attachment_strip.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String? initialSearchTargetId; // 查找聊天记录后定位到某条消息
  final int? initialSearchTargetIndex; // 全局索引（保留兼容，实际按 DB 重算）
  const GroupChatScreen({
    super.key,
    required this.groupId,
    this.initialSearchTargetId,
    this.initialSearchTargetIndex,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  ChatGroup? _group;
  /// 消息窗口，最新在前（_messages[0] = 最新）
  List<ChatMessage> _messages = [];
  Map<String, Character> _members = {};
  final TextEditingController _input = TextEditingController();

  bool _streaming = false;
  /// 流式请求序号：finally 兜底时判断"是否已被新的请求取代"
  int _streamSeq = 0;
  bool _generating = false;
  String _streamSender = '';
  String _streamText = '';
  String _streamReasoning = '';
  bool _loading = true;
  int _turn = 0; // 用于轮流回复起始位置
  int _searchReturnIndex = -1;
  bool _inputRewriting = false;
  final List<PendingAttachment> _attachments = [];

  // 索引锚定列表（只在"查找定位"时使用）
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _itemPositions = ItemPositionsListener.create();
  /// 普通进入：正序/反序 ListView 共用（和私聊一致，offset 0 恒为可视起点）
  final ScrollController _plainScroll = ScrollController();

  /// 是否处于"查找定位"模式：只有这时才用索引锚定列表
  bool get _anchored => widget.initialSearchTargetId != null || _searchReturnIndex >= 0;

  // ---- 窗口加载（分页）----
  static const int _minPageSize = 30;
  static const int _searchBefore = 10;
  static const int _searchAfter = 10;
  int _pageSize = _minPageSize;
  int _total = 0;
  int _windowStart = 0; // 已加载窗口中最老一条的全局索引
  bool _loadingOlder = false;
  bool _loadingNewer = false;
  int _pagingSuppressUntil = 0;
  bool get _hasOlder => _windowStart > 0;
  bool get _hasNewer => _windowStart + _messages.length < _total;
  bool get _pagingSuppressed =>
      DateTime.now().millisecondsSinceEpoch < _pagingSuppressUntil;

  @override
  void initState() {
    super.initState();
    // 两种模式各挂一个监听：查找定位用条目索引，普通进入用像素偏移（和私聊一致）
    _itemPositions.itemPositions.addListener(_onPositionsChanged);
    _plainScroll.addListener(_onPlainScrollPaging);
    _load();
  }

  /// 普通进入：反序 ListView 的像素监听（offset 0 = 底部）
  void _onPlainScrollPaging() {
    if (_anchored || _pagingSuppressed || _loading) return;
    if (!_plainScroll.hasClients) return;
    final pos = _plainScroll.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 400 && _hasOlder) {
      _loadOlder();
    } else if (pos.pixels <= 120 && _hasNewer) {
      _loadNewer();
    }
  }

  void _onPositionsChanged() {
    if (!_anchored || _pagingSuppressed || _loading) return;
    final positions = _itemPositions.itemPositions.value;
    if (positions.isEmpty) return;
    var minIdx = positions.first.index;
    var maxIdx = positions.first.index;
    for (final p in positions) {
      if (p.index < minIdx) minIdx = p.index;
      if (p.index > maxIdx) maxIdx = p.index;
    }
    final streamOffset = _streaming ? 1 : 0;
    final msgMax = maxIdx - streamOffset;
    final msgMin = minIdx - streamOffset;
    if (msgMax >= _messages.length - 5 && _hasOlder) _loadOlder();
    if (msgMin <= 1 && _hasNewer) _loadNewer();
  }

  @override
  void dispose() {
    _input.dispose();
    _itemPositions.itemPositions.removeListener(_onPositionsChanged);
    _plainScroll.removeListener(_onPlainScrollPaging);
    _plainScroll.dispose();
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
    final total = g == null ? 0 : await state.countMessagesForGroup(g.id);
    // 单页大小 = max(30, 上下文轮数)
    final eff0 = g == null
        ? resolveSettings(state.settings)
        : resolveGroup(state.settings, g);
    _pageSize = eff0.contextTurns > _minPageSize ? eff0.contextTurns : _minPageSize;

    int start;
    int limit;
    int? targetIdx;
    if (g != null && widget.initialSearchTargetId != null) {
      // 用数据库按同一排序重算索引，避免排序差异导致偏移
      targetIdx = await state.indexOfMessageForGroup(g.id, widget.initialSearchTargetId!);
      start = (targetIdx - _searchBefore).clamp(0, total);
      limit = (targetIdx + _searchAfter + 1 - start).clamp(1, total - start);
      _pagingSuppressUntil = DateTime.now().millisecondsSinceEpoch + 900;
    } else {
      limit = total < _pageSize ? total : _pageSize;
      start = total - limit;
    }
    final msgs = (g == null || total == 0)
        ? <ChatMessage>[]
        : await state.messageSliceForGroup(g.id, start, limit);

    if (!mounted) return;
    setState(() {
      _group = g;
      _members = members;
      _messages = msgs.reversed.toList(); // 最新在前
      _total = total;
      _windowStart = start;
      _searchReturnIndex =
          targetIdx == null || msgs.isEmpty ? -1 : (start + msgs.length - 1 - targetIdx);
      _loading = false;
    });
    if (targetIdx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToIndex(_searchReturnIndex);
      });
    }
  }

  /// 加载更早的一页（追加到末尾 = 最老方向）
  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _group == null) return;
    _loadingOlder = true;
    final state = context.read<AppState>();
    final start = (_windowStart - _pageSize).clamp(0, _windowStart);
    final limit = _windowStart - start;
    final older = await state.messageSliceForGroup(_group!.id, start, limit);
    if (!mounted) {
      _loadingOlder = false;
      return;
    }
    setState(() {
      _messages = [..._messages, ...older.reversed];
      _windowStart = start;
      if (_searchReturnIndex >= 0) _searchReturnIndex += older.length;
      _loadingOlder = false;
    });
  }

  /// 加载更晚的一页（插入到开头 = 最新方向），保持视口锚点
  Future<void> _loadNewer() async {
    if (_loadingNewer || !_hasNewer || _group == null) return;
    _loadingNewer = true;
    final state = context.read<AppState>();
    final offset = _windowStart + _messages.length;
    final remain = _total - offset;
    final limit = remain < _pageSize ? remain : _pageSize;

    int anchorIndex = 0;
    double anchorAlign = 0.0;
    final positions = _itemPositions.itemPositions.value;
    if (positions.isNotEmpty) {
      var first = positions.first;
      for (final p in positions) {
        if (p.index < first.index) first = p;
      }
      anchorIndex = first.index;
      anchorAlign = first.itemLeadingEdge;
    }

    final newer = await state.messageSliceForGroup(_group!.id, offset, limit);
    if (!mounted) {
      _loadingNewer = false;
      return;
    }
    setState(() {
      _messages = [...newer.reversed, ..._messages];
      _loadingNewer = false;
      if (_searchReturnIndex >= 0) _searchReturnIndex += newer.length;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _itemScroll.jumpTo(
          index: anchorIndex + newer.length,
          alignment: anchorAlign.clamp(0.0, 0.99),
        );
      } catch (_) {}
    });
  }

  /// 发送前确保处于最新窗口
  Future<void> _ensureLatestWindow() async {
    if (!_hasNewer || _group == null) return;
    final state = context.read<AppState>();
    final total = await state.countMessagesForGroup(_group!.id);
    final limit = total < _pageSize ? total : _pageSize;
    final start = total - limit;
    final msgs = total == 0
        ? <ChatMessage>[]
        : await state.messageSliceForGroup(_group!.id, start, limit);
    if (!mounted) return;
    final wasAnchored = _anchored;
    setState(() {
      _messages = msgs.reversed.toList();
      _total = total;
      _windowStart = start;
      _searchReturnIndex = -1;
    });
    if (!wasAnchored) {
      _jumpToBottom(force: true);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _itemScroll.jumpTo(index: 0);
      } catch (_) {}
    });
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

  /// 把附件与文字合并成一条消息内容。
  String _composeContent(String text) {
    final sb = StringBuffer();
    for (final a in _attachments) {
      sb.writeln(a.isImage ? '［图片：${a.path}］' : '［文件：${a.path}］');
    }
    if (text.isNotEmpty) sb.write(text);
    return sb.toString();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _attachments.isEmpty) || _streaming) return;
    final state = context.read<AppState>();
    var g = _group;
    if (g == null) return;
    // 若正在查看历史窗口，先回到最新窗口
    if (_hasNewer) {
      await _ensureLatestWindow();
      g = _group;
      if (g == null) return;
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final content = _composeContent(text);
    final atts = <Attachment>[];
    for (final a in _attachments) {
      if (a.isImage) {
        final size = await imageSizeOf(a.path);
        atts.add(Attachment(
          type: 'image',
          path: a.path,
          name: a.name,
          width: size?.$1 ?? 0,
          height: size?.$2 ?? 0,
        ));
      } else {
        atts.add(Attachment(type: 'file', path: a.path, name: a.name));
      }
    }
    final userMsg = ChatMessage(
      id: id,
      groupId: g.id,
      role: 'user',
      content: content,
      attachments: atts,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await state.insertMessage(userMsg);
    setState(() {
      _messages.insert(0, userMsg); // 最新在前
      _total += 1;
      _input.clear();
      _attachments.clear();
    });
    _jumpToBottom(force: true);

    if (g.replyMode == 'designated') return;

    await _triggerReplies(state, g);
  }

  /// 添加图片附件
  Future<void> _addImage() async {
    // compressionQuality: 0 关闭插件压缩，避免公共 Pictures 目录留副本（相册重复）
    final r = await FilePicker.platform.pickFiles(
        type: FileType.image, withData: false, compressionQuality: 0);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    var path = f.path ?? '';
    if (path.isEmpty) return;
    path = await adoptPickedFile(path);
    if (!mounted) return;
    setState(() => _attachments.add(PendingAttachment(path: path, name: f.name, isImage: true)));
  }

  /// 添加文件附件
  Future<void> _addFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    var path = f.path ?? '';
    if (path.isEmpty) return;
    path = await adoptPickedFile(path);
    if (!mounted) return;
    setState(() => _attachments.add(PendingAttachment(path: path, name: f.name, isImage: false)));
  }

  /// 左下角"＋"按钮：展开小面板（切换模型 / 添加图片 / 选择文件）
  Future<void> _showPlusMenu(AppState state, ChatGroup g) async {
    if (_streaming) return;
    final scheme = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                leading: Icon(Icons.model_training, size: 20, color: scheme.primary),
                title: const Text('切换模型', style: TextStyle(fontSize: 14)),
                onTap: () => Navigator.pop(ctx, 'model'),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.image_outlined, size: 20, color: scheme.primary),
                title: const Text('添加图片', style: TextStyle(fontSize: 14)),
                onTap: () => Navigator.pop(ctx, 'image'),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.attach_file, size: 20, color: scheme.primary),
                title: const Text('选择文件', style: TextStyle(fontSize: 14)),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'model') {
      await _showGroupModelSwitch(state, g);
    } else if (choice == 'image') {
      await _addImage();
    } else if (choice == 'file') {
      await _addFile();
    }
  }

  /// 每个角色本轮最多连续发几条（群设置里的"每角色最多回复 N 条"）
  int _replyLimitOf(ChatGroup g) => g.maxReplies <= 0 ? 1 : g.maxReplies.clamp(1, 3);

  Future<void> _autoAll(AppState state, ChatGroup g) async {
    final members = _members.values.toList();
    if (members.isEmpty) return;
    final last = _messages.isNotEmpty ? _messages.last.content : '';
    final mentioned = members.where((m) => last.contains(m.name)).toList();
    final rest = members.where((m) => !mentioned.contains(m)).toList();
    final order = [...mentioned, ...rest];
    final limit = _replyLimitOf(g);
    for (final m in order) {
      for (var i = 0; i < limit; i++) {
        if (!mounted) return;
        await _streamReply(state, g, m, m.id);
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  Future<void> _autoNatural(AppState state, ChatGroup g) async {
    final members = _members.values.toList();
    if (members.isEmpty) return;
    // 轮流：从上次起始位置之后开始
    int start = _turn % members.length;
    final order = [...members.sublist(start), ...members.sublist(0, start)];
    // 一次请求判定全员是否开口（原来是每个角色各发一次"是/否"请求，
    // 5 人群一条消息就要 5 次额外调用，又慢又费钱）
    final picked = await _decideReplies(state, g, order);
    final limit = _replyLimitOf(g);
    var replied = 0;
    for (final m in order) {
      if (!picked.contains(m.id)) continue;
      for (var i = 0; i < limit; i++) {
        if (!mounted) return;
        await _streamReply(state, g, m, m.id);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      replied++;
    }
    _turn++;
    if (replied == 0 && order.isNotEmpty) {
      // 至少一人回复
      await _streamReply(state, g, order.first, order.first.id);
    }
  }

  /// 一次调用决定本群这一轮由谁开口，返回角色 id 集合。
  Future<Set<String>> _decideReplies(
      AppState state, ChatGroup g, List<Character> members) async {
    final provider = _providerFor(members.first, state);
    if (provider == null) return <String>{};
    final last = _messages.isNotEmpty ? _messages.last.content : '';
    final names = members.map((m) => m.name).join('、');
    try {
      final r = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: provider.model,
        messages: [
          {
            'role': 'system',
            'content': '你是群聊调度器。群成员：$names。'
                '根据每个人的性格判断谁适合回复刚发的这条消息。'
                '严格只输出 JSON 数组，元素是应回复的角色名，例如 ["甲","乙"]；'
                '没有人适合回复时输出 []。不要输出任何其他文字。',
          },
          {'role': 'user', 'content': last},
        ],
        temperature: 0.3,
      ))
          .trim();
      final open = r.indexOf('[');
      final close = r.lastIndexOf(']');
      if (open < 0 || close <= open) return <String>{};
      final list = jsonDecode(r.substring(open, close + 1));
      final out = <String>{};
      if (list is List) {
        for (final e in list) {
          final name = e?.toString().trim() ?? '';
          for (final m in members) {
            if (m.name == name) out.add(m.id);
          }
        }
      }
      return out;
    } catch (_) {
      return <String>{};
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
    setState(() {
      _messages.removeWhere((x) => x.id == m.id);
      if (_total > 0) _total -= 1;
    });
  }

  /// 删除该消息及其之后的所有消息，并同步删除记忆（取决于记忆模式）。
  Future<void> _deleteFromHere(ChatMessage m) async {
    final state = context.read<AppState>();
    final g = _group;
    if (g == null) return;
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
    if (ok != true || !mounted) return;
    final idx = _messages.indexWhere((x) => x.id == m.id);
    if (idx < 0) return;
    final owners =
        _members.values.map((c) => state.groupMemoryOwner(g, c)).toSet().toList();
    await state.deleteMessagesFrom(null, g.id, m.createdAt, memoryOwners: owners);
    setState(() {
      // 删除该条及其后（更新）的消息；最新在前 → 保留比它更老的部分
      final keep = idx + 1;
      _total = _windowStart + (_messages.length - keep).clamp(0, _messages.length);
      _messages = keep >= _messages.length ? <ChatMessage>[] : _messages.sublist(keep);
      _searchReturnIndex = -1;
    });
    _jumpToBottom(animate: false, force: true);
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

  /// 让角色继续接着上一条回复自然续写（不插入用户消息，角色自己生成新消息）。
  Future<void> _continueReply() async {
    if (_streaming) return;
    final state = context.read<AppState>();
    final g = _group;
    if (g == null) return;
    // 最新在前：从索引 0 开始找最近一条角色消息
    ChatMessage? last;
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].role == 'assistant' && _messages[i].senderCharacterId != null) {
        last = _messages[i];
        break;
      }
    }
    if (last == null || !_members.containsKey(last.senderCharacterId)) return;
    final character = _members[last.senderCharacterId]!;
    final histories = _messages.where((m) => m.role != 'system').toList().reversed.toList();
    final gwb = g.worldbookIds.isEmpty
        ? <WorldbookEntry>[]
        : (await state.worldbookFor(null)).where((e) => g.worldbookIds.contains(e.id)).toList();
    final memOwner = state.groupMemoryOwner(g, character);
    final groupWhole = g.memoryMode == 'whole';
    final charMems = groupWhole ? <MemoryItem>[] : await state.memoriesFor(memOwner);
    final groupMems = groupWhole ? await state.memoriesFor(memOwner) : <MemoryItem>[];
    final payload = PromptBuilder.buildGroupMessages(
      character: character,
      eff: _eff,
      worldbook: gwb,
      memories: charMems,
      groupMemories: groupMems,
      history: histories,
      groupNames: _members.values.map((m) => m.name).toList(),
      replyStyle: g.replyStyle,
      extraPrompt: state.settings.systemPromptExtra,
    );
    // 先把最后一条真实用户消息替换成多模态内容（图片/文件），
    // 再追加"继续"指令。顺序反了会把指令本身替换成图片，
    // 模型就会去回答图片而不是续写。
    final lastUserIdx = payload.lastIndexWhere((e) => e['role'] == 'user');
    if (lastUserIdx >= 0) {
      final users = histories.where((m) => m.role == 'user').toList();
      if (users.isNotEmpty && users.last.attachments.isNotEmpty) {
        final rich = await buildUserContent(users.last, vision: true);
        if (rich != null) payload[lastUserIdx] = {'role': 'user', 'content': rich};
      }
    }
    payload.add({
      'role': 'user',
      'content': '请接着你上一句话继续说下去，自然续写，不要重复。',
    });
    final provider = _providerFor(character, state);
    if (provider == null) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _streaming = true;
      _streamSender = character.name;
      _streamText = '';
      _streamReasoning = '';
    });
    _jumpToBottom();
    final seq = ++_streamSeq;
    try {
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
      final asst = ChatMessage(
        id: id,
        groupId: g.id,
        role: 'assistant',
        senderCharacterId: character.id,
        content: _streamText.trim(),
        reasoning: _streamReasoning.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await state.insertMessage(asst);
      if (mounted) {
        setState(() {
          _messages.insert(0, asst); // 最新在前
          _total += 1;
        });
      }
      _jumpToBottom();
    } catch (e) {
      if (mounted && seq == _streamSeq) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('续写失败：$e')));
      }
    } finally {
      if (seq == _streamSeq) _endStreaming();
    }
  }

  /// 复位流式状态：成功 / 失败 / 异常都必须走到这里
  void _endStreaming() {
    if (!mounted) {
      _streaming = false;
      return;
    }
    setState(() {
      _streaming = false;
      _streamText = '';
      _streamReasoning = '';
    });
  }

  Future<void> _regenerateMessage(ChatMessage m) async {
    final state = context.read<AppState>();
    final g = _group;
    if (g == null || m.senderCharacterId == null) return;
    final character = _members[m.senderCharacterId];
    if (character == null) return;
    await state.deleteMessage(m.id);
    setState(() {
      _messages.removeWhere((x) => x.id == m.id);
      if (_total > 0) _total -= 1;
    });
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
      payload.add({
        'role': m.role == 'user' ? 'user' : 'assistant',
        'content': contentForModel(m),
      });
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

  /// 润色一句话，用于输入框的 AI 改写按钮（用群聊默认接口）。
  Future<String> _rewriteText(String text) async {
    final state = context.read<AppState>();
    final provider = state.getProviderById(null);
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先配置接口')));
      return text;
    }
    final result = await ApiClient().completeChat(
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      model: provider.model,
      messages: [
        {'role': 'system', 'content': '把下面这句话润色成更自然的角色扮演输入，保留原意，直接输出。'},
        {'role': 'user', 'content': text},
      ],
    );
    return result.trim();
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
        setState(() => _generating = false);
        // 改写后替换原消息并让群聊自动回复
        await state.updateMessageContent(m.id, text);
        setState(() {
          final idx = _messages.indexWhere((x) => x.id == m.id);
          if (idx >= 0) _messages[idx] = _messages[idx].copyWith(content: text);
        });
        if (_group != null && _group!.replyMode != 'designated') {
          await _triggerReplies(state, _group!);
        }
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
              _btn(scheme, Icons.arrow_forward_ios, () => _continueReply()),
              _btn(scheme, Icons.auto_awesome, () => _rewriteUser(m)),
            ])
          : Row(mainAxisSize: MainAxisSize.min, children: [
              _btn(scheme, Icons.refresh, () => _regenerateMessage(m)),
              _btn(scheme, Icons.delete_outline, () => _deleteMessage(m)),
              _btn(scheme, Icons.edit, () => _editMessage(m)),
              _btn(scheme, Icons.arrow_forward_ios, () => _continueReply()),
              _btn(scheme, Icons.chat_bubble_outline, () => _generateMyReply()),
            ]),
    );
  }

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

  Future<void> _streamReply(AppState state, ChatGroup g, Character character, String senderCharId) async {
    if (_streaming) return;
    final provider = _providerFor(character, state);
    if (provider == null) {
      final note = ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        groupId: g.id,
        role: 'assistant',
        senderCharacterId: senderCharId,
        content: '（$character.name 未配置接口）',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await state.insertMessage(note);
      // 同步到本地列表，否则提示只进了数据库、界面要重进群才看得到
      if (mounted) {
        setState(() {
          _messages.insert(0, note);
          _total += 1;
        });
      }
      return;
    }
    final histories = _messages.where((m) => m.role != 'system').toList().reversed.toList();
    final gwb = g.worldbookIds.isEmpty
        ? <WorldbookEntry>[]
        : (await state.worldbookFor(null)).where((e) => g.worldbookIds.contains(e.id)).toList();
    // 记忆模式：whole=群整体；separate/synced=按角色独立
    final memOwner = state.groupMemoryOwner(g, character);
    final bool groupWhole = g.memoryMode == 'whole';
    final charMems = groupWhole ? <MemoryItem>[] : await state.memoriesFor(memOwner);
    final groupMems = groupWhole ? await state.memoriesFor(memOwner) : <MemoryItem>[];
    final payload = PromptBuilder.buildGroupMessages(
      character: character,
      eff: _eff,
      worldbook: gwb,
      memories: charMems,
      groupMemories: groupMems,
      history: histories,
      groupNames: _members.values.map((m) => m.name).toList(),
      replyStyle: g.replyStyle,
      extraPrompt: state.settings.systemPromptExtra,
    );

    // 最后一条用户消息：图片直接发给多模态模型 / 读取文本文件内容
    final lastUserIdx = payload.lastIndexWhere((e) => e['role'] == 'user');
    var usedRich = false;
    var textOnly = '';
    if (lastUserIdx >= 0) {
      final users = histories.where((m) => m.role == 'user').toList();
      if (users.isNotEmpty && users.last.attachments.isNotEmpty) {
        textOnly = contentForModel(users.last);
        final rich = await buildUserContent(users.last, vision: true)
            .timeout(const Duration(seconds: 25), onTimeout: () => null);
        if (rich != null) {
          payload[lastUserIdx] = {'role': 'user', 'content': rich};
          usedRich = rich is List;
        }
      }
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _streaming = true;
      _streamSender = character.name;
      _streamText = '';
      _streamReasoning = '';
    });
    _jumpToBottom();

    final seq = ++_streamSeq;
    try {
      Future<String?> run({bool stream = true}) async {
        try {
          if (stream) {
            await for (final delta in ApiClient()
                .streamChat(
                  baseUrl: provider.baseUrl,
                  apiKey: provider.apiKey,
                  model: _replyModelFor(character, provider),
                  messages: payload,
                  temperature: 0.9,
                  maxTokens: usedRich ? 4096 : null,
                )
                .timeout(Duration(seconds: usedRich ? 25 : 60))) {
              if (!mounted) return null;
              if (delta.content.isNotEmpty) setState(() => _streamText += delta.content);
              if (delta.reasoning.isNotEmpty) setState(() => _streamReasoning += delta.reasoning);
            }
            return null;
          }
          // 非流式兜底：正文与思考一起取回
          final r = await ApiClient()
              .completeChatFull(
                baseUrl: provider.baseUrl,
                apiKey: provider.apiKey,
                model: _replyModelFor(character, provider),
                messages: payload,
                temperature: 0.9,
                maxTokens: 4096,
              )
              .timeout(const Duration(seconds: 90));
          if (!mounted) return null;
          setState(() {
            _streamText += r.content;
            _streamReasoning += r.reasoning;
          });
          return null;
        } catch (e) {
          return e is ApiException ? e.message : e.toString();
        }
      }

      var errText = await run();
      if (!mounted) return;
      // 带图流式失败（首包超时 / 服务端不支持流式多模态）→ 非流式重发，仍带图
      if (errText != null && usedRich) {
        _streamText = '';
        _streamReasoning = '';
        setState(() {});
        errText = await run(stream: false);
      }
      // 仍失败 → 去掉附件，用纯文字重试
      if (errText != null && textOnly.isNotEmpty) {
        payload[lastUserIdx] = {'role': 'user', 'content': textOnly};
        _streamText = '';
        _streamReasoning = '';
        setState(() {});
        errText = await run();
      }
      if (errText != null && mounted) {
        setState(() => _streamText += '\n[错误] $errText');
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
          _messages.insert(0, asst); // 最新在前
          _total += 1;
        });
      }
      _jumpToBottom();
    } catch (e) {
      // 兜底：未预期异常不能把群聊卡在"等待模型响应…"
      if (mounted && seq == _streamSeq) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('生成失败：$e')));
      }
    } finally {
      if (seq == _streamSeq) _endStreaming();
    }
    // 自动长记忆：按"角色回复条数"计数（查库，不受窗口加载影响）
    final every = g.autoMemoryEvery > 0 ? g.autoMemoryEvery : state.settings.autoMemoryEvery;
    final turns = await state.countAssistantForGroup(g.id);
    if (every > 0 && turns > 0 && turns % every == 0 && state.settings.memoryEnabled) {
      _autoMemory(state, g);
    }
  }

  Future<void> _autoMemory(AppState state, ChatGroup g) async {
    final provider = state.getProviderById(null);
    if (provider == null) return;
    final history = _messages.where((m) => m.role != 'system').toList().reversed.toList();
    if (history.isEmpty) return;
    final tail = history.length > 8 ? history.sublist(history.length - 8) : history;
    // 整理成一段文本，避免模型把它当成对话续写
    final transcript = MemoryHelper.buildTranscript(
      tail.map((m) {
        final who = m.role == 'user'
            ? (m.senderCharacterId != null ? (_members[m.senderCharacterId]?.name ?? '我') : '我')
            : (_members[m.senderCharacterId]?.name ?? '角色');
        return (who, m.content);
      }).toList(),
    );
    try {
      final groupWhole = g.memoryMode == 'whole';
      if (groupWhole) {
        final t = (await ApiClient().completeChat(
          baseUrl: provider.baseUrl,
          apiKey: provider.apiKey,
          model: provider.model,
          messages: MemoryHelper.buildMessages(transcript),
          temperature: 0.3,
        )).trim();
        if (MemoryHelper.isValid(t)) {
          await state.addMemory(MemoryItem(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            characterId: 'group_${g.id}',
            content: MemoryHelper.clean(t),
          ));
        }
        return;
      }
      // 角色独立记忆：每个角色从自己的视角记录（separate / synced）
      final members = _members.values.toList();
      if (members.isEmpty) return;
      final names = members.map((m) => m.name).join('、');
      final prompt = '你是记忆整理助手。下面是群聊记录。请分别以每个角色的**第一人称视角**'
          '各写一条该角色值得记住的关键信息（只写该角色自己关心的：与玩家的关系、约定、'
          '自己承诺过的事、自己在乎的偏好等），不要写其他角色的视角。\n'
          '角色列表：$names\n'
          '严格只输出 JSON 对象，格式：{"角色名": "该角色的记忆条目"}，不要其他文字。\n\n'
          '对话记录：\n$transcript';
      final raw = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: provider.model,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        temperature: 0.4,
      )).trim();
      final map = _parseJsonMap(raw);
      var saved = 0;
      for (final m in members) {
        final text = map[m.name]?.toString().trim();
        if (text == null || text.isEmpty) continue;
        await state.addMemory(MemoryItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${m.id}',
          // separate=群内独立；synced=与私聊共用角色记忆
          characterId: state.groupMemoryOwner(g, m),
          content: text,
        ));
        saved++;
      }
      // 兜底：模型没返回可解析的 JSON 时，逐个角色单独提炼（各自视角）
      if (saved == 0) {
        for (final m in members) {
          try {
            final one = (await ApiClient().completeChat(
              baseUrl: provider.baseUrl,
              apiKey: provider.apiKey,
              model: provider.model,
              messages: [
                {
                  'role': 'user',
                  'content': '你是「${m.name}」。请从你自己的第一人称视角，'
                      '从下面的群聊记录里提炼 1 条你值得记住的信息（只写你关心的），'
                      '只输出记忆内容本身。\n\n对话记录：\n$transcript',
                },
              ],
              temperature: 0.3,
            )).trim();
            if (MemoryHelper.isValid(one)) {
              await state.addMemory(MemoryItem(
                id: '${DateTime.now().microsecondsSinceEpoch}_${m.id}',
                characterId: state.groupMemoryOwner(g, m),
                content: MemoryHelper.clean(one),
              ));
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// 从模型输出里解析出 {角色名: 记忆} 的 JSON（容忍 ``` 代码块与多余文字）。
  Map<String, dynamic> _parseJsonMap(String raw) {
    var t = raw.trim();
    if (t.startsWith('```')) {
      final i = t.indexOf('\n');
      if (i >= 0) t = t.substring(i + 1);
      final j = t.lastIndexOf('```');
      if (j >= 0) t = t.substring(0, j);
      t = t.trim();
    }
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start >= 0 && end > start) t = t.substring(start, end + 1);
    try {
      final v = jsonDecode(t);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return {};
  }

  /// 回到底部（最新一条）
  void _jumpToBottom({bool animate = true, bool force = false, int attempt = 0}) {
    // 普通进入：和私聊一样用普通 ListView，
    // 反序列表 offset 0 = 底部；正序（内容不满一屏）时无需滚动
    if (!_anchored) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_plainScroll.hasClients && attempt < 8) {
          Future.delayed(Duration(milliseconds: 50 + attempt * 40), () {
            if (mounted) _jumpToBottom(animate: animate, force: force, attempt: attempt + 1);
          });
          return;
        }
        if (!_plainScroll.hasClients) return;
        final pos = _plainScroll.position;
        if (_contentFits) {
          // 正序列表：内容本就不满一屏；若这一帧刚好溢出，先贴底，下一帧会切回反序
          if (pos.maxScrollExtent > 0.5 && pos.pixels < pos.maxScrollExtent - 0.5) {
            pos.jumpTo(pos.maxScrollExtent);
          }
          return;
        }
        if (pos.pixels > 0.5) {
          if (animate) {
            pos.animateTo(0,
                duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
          } else {
            pos.jumpTo(0);
          }
        }
      });
      return;
    }
    if (!force) {
      final positions = _itemPositions.itemPositions.value;
      if (positions.isNotEmpty) {
        var minIdx = positions.first.index;
        for (final p in positions) {
          if (p.index < minIdx) minIdx = p.index;
        }
        if (minIdx > 2) return;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_itemScroll.isAttached && attempt < 8) {
        Future.delayed(Duration(milliseconds: 50 + attempt * 40), () {
          if (mounted) {
            _jumpToBottom(animate: animate, force: true, attempt: attempt + 1);
          }
        });
        return;
      }
      try {
        if (animate) {
          _itemScroll.scrollTo(
            index: 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        } else {
          _itemScroll.jumpTo(index: 0);
        }
      } catch (_) {}
    });
  }

  /// 查找聊天记录后定位到某条消息（本地索引）：滑动到居中
  void _scrollToIndex(int idx) {
    if (idx < 0 || idx >= _messages.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _itemScroll.jumpTo(index: idx, alignment: 0.0);
      } catch (_) {}
      Future.delayed(const Duration(milliseconds: 16), () {
        if (!mounted) return;
        try {
          _itemScroll.scrollTo(
            index: idx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } catch (_) {}
      });
    });
  }

  /// 选择成员查看其独立记忆（separate/synced 模式）。
  Future<void> _showMemberMemoryPicker(AppState state, ChatGroup g) async {
    final c = await showModalBottomSheet<Character>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('选择要查看记忆的角色', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final m in _members.values)
              ListTile(
                leading: buildCharacterAvatar(context, m, 36),
                title: Text(m.name),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (c != null && mounted) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MemoryScreen(
                  characterId: state.groupMemoryOwner(g, c),
                  historyGroupId: g.id,
                  memoryModeLabel: _memoryModeLabel(g.memoryMode))));
      if (mounted) setState(() {});
    }
  }

  String _memoryModeLabel(String mode) {
    switch (mode) {
      case 'separate':
        return '记忆模式：角色独立全新记忆';
      case 'synced':
        return '记忆模式：角色独立同步记忆';
      default:
        return '记忆模式：全新整体记忆';
    }
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
                if (g.memoryMode == 'whole') {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => MemoryScreen(characterId: 'group_${g.id}', memoryModeLabel: _memoryModeLabel(g.memoryMode))));
                  if (mounted) setState(() {});
                } else {
                  _showMemberMemoryPicker(state, g);
                }
              } else if (v == 'search') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SearchHistoryScreen(groupId: g.id)),
                );
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
              PopupMenuItem(value: 'search', child: Text('查找聊天记录')),
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

  /// 消息列表：索引锚定 + reverse，索引 0 = 最新（底部）
  Widget _messageList(AppState state, ChatGroup g, double topInset) {
    final showCharAvatar = _hideCharAvatar == null
        ? state.settings.showCharAvatar
        : !_hideCharAvatar!;
    final showUserAvatar = _hideUserAvatar == null
        ? state.settings.showUserAvatar
        : !_hideUserAvatar!;
    final msgCount = _messages.length;
    final showBanner = _searchReturnIndex >= 0;
    final streamOffset = _streaming ? 1 : 0;

    Widget itemAt(int i) {
        // 视觉最底部：流式输出气泡
        if (streamOffset == 1 && i == 0) {
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
          final streamTop = _streamReasoning.isNotEmpty && state.settings.showThinking
              ? ThinkingToggle(reasoning: _streamReasoning)
              : const ThinkingIndicator();
          return MessageBubble(
            message: st,
            isUser: false,
            avatar: sender != null ? buildCharacterAvatar(context, sender, 34) : null,
            senderName: _streamSender,
            showAvatar: showCharAvatar,
            isCurrent: true,
            fontScale: state.settings.fontSize,
            topContent: streamTop,
          );
        }
        final k = i - streamOffset;
        // 视觉最顶部：查找返回条
        if (showBanner && k == msgCount) return _searchReturnBanner();
        if (k < 0 || k >= msgCount) return const SizedBox.shrink();
        final m = _messages[k];
        final foot = (k == 0 && !_streaming) ? _actionFooter(state, m) : null;
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
            fontScale: state.settings.fontSize,
            highlight: _searchReturnIndex >= 0 && k == _searchReturnIndex,
            onDeleteFromHere: () => _deleteFromHere(m),
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
          topContent: m.reasoning.trim().isNotEmpty && state.settings.showThinking
              ? ThinkingToggle(reasoning: m.reasoning)
              : null,
          bubbleColor: parseHexColor(state.settings.bubbleCharColor),
          bubbleOpacity: state.settings.bubbleOpacity,
          fontScale: state.settings.fontSize,
          highlight: _searchReturnIndex >= 0 && k == _searchReturnIndex,
          onDeleteFromHere: () => _deleteFromHere(m),
        );
    }

    final itemCount = msgCount + streamOffset + (showBanner ? 1 : 0);

    // 与私聊完全同一套做法：
    // - 内容不满一屏 → 正序 ListView，顶部对齐（空白落在下方，和微信一致）
    // - 内容超过一屏 → 反序 ListView（offset 0 = 视觉底部，发消息/流式自动贴底）
    // 反序列表在内容不足一屏时会把内容钉在底部、空白全在上方 —— 那就是"上方空白"。
    // 只有"查找聊天记录后定位"才用索引锚定列表（需要按条目定位）。
    if (!_anchored) {
      _syncGroupFit();
      if (_contentFits) {
        return ListView.builder(
          controller: _plainScroll,
          padding: EdgeInsets.only(top: topInset + 8, bottom: 12),
          itemCount: itemCount,
          itemBuilder: (context, i) {
            // 正序：索引 0 = 最顶部（最老的一条）
            return itemAt(itemCount - 1 - i);
          },
        );
      }
      return ListView.builder(
        controller: _plainScroll,
        reverse: true, // 反序：offset 0 就是视觉底部
        padding: EdgeInsets.only(top: topInset + 8, bottom: 12),
        itemCount: itemCount,
        itemBuilder: (context, i) => itemAt(i),
      );
    }

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScroll,
      itemPositionsListener: _itemPositions,
      reverse: true,
      padding: EdgeInsets.only(top: topInset + 8, bottom: 12),
      itemCount: itemCount,
      itemBuilder: (context, i) => itemAt(i),
    );
  }

  /// 内容是否不满一屏：决定列表方向
  bool _contentFits = false;

  /// 按"内容是否满一屏"切换列表方向（与私聊同一套判断）：
  /// - 不满一屏 → 正序列表，顶部对齐（空白在下方）
  /// - 满一屏   → 反序列表，offset 0 即底部
  /// 两种方向的 0 偏移含义不同，所以切换后必须显式归零
  ///（正序 = 顶部，反序 = 底部，刚好都是 0）。
  void _syncGroupFit() {
    if (_anchored || _loading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_plainScroll.hasClients) return;
      final fits = _plainScroll.position.maxScrollExtent <= 0.5;
      if (fits == _contentFits) return;
      setState(() => _contentFits = fits);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_plainScroll.hasClients) return;
        _plainScroll.jumpTo(0);
      });
    });
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
                  // 未单独设置过时跟随主设置
                  value: _hideCharAvatar == null
                      ? state.settings.showCharAvatar
                      : !_hideCharAvatar!,
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
                  value: _hideUserAvatar == null
                      ? state.settings.showUserAvatar
                      : !_hideUserAvatar!,
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

  // null = 跟随设置里的全局开关；非 null 是本群的临时覆盖
  bool? _hideCharAvatar;
  bool? _hideUserAvatar;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AttachmentStrip(
                items: _attachments,
                scale: state.settings.fontSize,
                onRemove: (i) => setState(() => _attachments.removeAt(i)),
              ),
            ),
            Row(
              children: [
                InkWell(
                  onTap: _streaming ? null : () => _showPlusMenu(state, g),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add, size: 22, color: Theme.of(context).colorScheme.primary),
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
                      style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
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
          ],
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
