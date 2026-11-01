import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/memory_helper.dart';
import '../services/prompt_builder.dart';
import '../services/vision_payload.dart';
import '../services/settings_resolver.dart';
import '../state/app_state.dart';
import 'widgets/avatars.dart';
import 'widgets/message_bubble.dart';
import 'widgets/thinking_toggle.dart';
import '../utils/colors.dart';
import '../utils/file_adopt.dart';
import '../utils/attachment_text.dart';
import '../utils/image_utils.dart';
import 'memory_screen.dart';
import 'character_editor_screen.dart';
import 'worldbook_screen.dart';
import 'worldbook_picker.dart';
import 'widgets/search_history_screen.dart';
import 'widgets/ai_rewrite_button.dart';
import 'widgets/attachment_strip.dart';

class ChatScreen extends StatefulWidget {
  final String characterId;
  final String? initialSearchTargetId; // 查找聊天记录后定位到某条消息
  final int? initialSearchTargetIndex; // 该消息在会话中的全局索引（用于窗口加载）
  const ChatScreen({
    super.key,
    required this.characterId,
    this.initialSearchTargetId,
    this.initialSearchTargetIndex,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Character? _character;
  ChatSession? _session;
  /// 消息窗口，**最新在前**（_messages[0] = 最新）。配合 reverse 列表，最新在底部。
  List<ChatMessage> _messages = [];
  List<WorldbookEntry> _worldbook = [];
  List<MemoryItem> _memories = [];
  final TextEditingController _input = TextEditingController();

  // 索引锚定列表：按"第几条"定位，不依赖像素高度
  final ItemScrollController _itemScroll = ItemScrollController();
  final ItemPositionsListener _itemPositions = ItemPositionsListener.create();
  /// 普通列表（反序）
  final ScrollController _scroll = ScrollController();
  late final bool _anchored = widget.initialSearchTargetId != null;

  bool _streaming = false;
  /// 流式请求序号：用于 finally 兜底时判断"这次请求是否已被新的请求取代"
  int _streamSeq = 0;
  bool _generating = false;
  String _streamText = '';
  String _streamReasoning = '';
  /// 当前阶段提示（把"卡在哪一步"直接显示出来）
  String _stage = '';
  bool _loading = true;

  bool? _hideCharAvatar;
  bool? _hideUserAvatar;
  int _searchReturnIndex = -1; // 本地索引
  /// 查找定位是否已完成（完成前列表透明，避免看到"先贴边再居中"的那一帧）
  bool _positioned = false;
  bool _inputRewriting = false;
  final List<PendingAttachment> _attachments = [];

  // ---- 窗口加载（分页）----
  static const int _minPageSize = 30; // 普通进入最少加载 30 条
  static const int _searchBefore = 10; // 查找定位：目标上方 10 条
  static const int _searchAfter = 10; // 查找定位：目标下方 10 条
  int _pageSize = _minPageSize; // 实际单页大小（≥ 上下文轮数）
  int _total = 0; // 会话总消息数
  int _windowStart = 0; // 已加载窗口的**最老**一条在全局中的索引
  bool _loadingOlder = false;
  bool _loadingNewer = false;
  /// 定位期间/刚定位完，抑制分页触发
  int _pagingSuppressUntil = 0;
  /// 列表当前总条目数（含流式气泡/查找条），按索引定位时用
  int _rawCount = 0;
  bool get _hasOlder => _windowStart > 0;
  bool get _hasNewer => _windowStart + _messages.length < _total;
  bool get _pagingSuppressed =>
      DateTime.now().millisecondsSinceEpoch < _pagingSuppressUntil;

  @override
  void initState() {
    super.initState();
    if (_anchored) {
      _itemPositions.itemPositions.addListener(_onPositionsChanged);
    } else {
      _scroll.addListener(_onScrollPaging);
    }
    _load();
  }

  /// 普通进入：用反序 ListView（和 1.5.2 一样稳），offset 0 就是底部
  void _onScrollPaging() {
    if (_pagingSuppressed || _loading || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 400 && _hasOlder) {
      _loadOlder();
    } else if (pos.pixels <= 120 && _hasNewer) {
      _loadNewer();
    }
  }

  /// 可见条目变化 → 触发分页（按"条目索引"判断，不依赖像素高度）
  void _onPositionsChanged() {
    if (_pagingSuppressed || _loading) return;
    if (_rawCount == 0) return;
    final positions = _itemPositions.itemPositions.value;
    if (positions.isEmpty) return;
    var minIdx = positions.first.index;
    var maxIdx = positions.first.index;
    for (final p in positions) {
      if (p.index < minIdx) minIdx = p.index;
      if (p.index > maxIdx) maxIdx = p.index;
    }
    final streamOffset = _streaming ? 1 : 0;
    var minK = 1 << 30;
    var maxK = -1;
    for (final p in positions) {
      final i = _rawCount - 1 - p.index; // 距底部位置：0 = 最新
      final k = i - streamOffset;
      if (k < minK) minK = k;
      if (k > maxK) maxK = k;
    }
    // 靠近更老方向（本地索引变大）
    if (maxK >= _messages.length - 5 && _hasOlder) {
      _loadOlder();
    }
    // 靠近最新方向
    if (minK <= 1 && _hasNewer) {
      _loadNewer();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _itemPositions.itemPositions.removeListener(_onPositionsChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final c = await state.getCharacter(widget.characterId);
    final session = await state.getOrCreateSession(widget.characterId);
    final worldbook = (c == null || c.worldbookIds.isEmpty)
        ? <WorldbookEntry>[]
        : (await state.worldbookFor(null))
            .where((e) => c.worldbookIds.contains(e.id))
            .toList();
    final memories = await state.memoriesFor(widget.characterId);

    var total = await state.countMessagesForSession(session.id);
    if (total == 0 && c != null && c.greeting.trim().isNotEmpty) {
      final greeting = ChatMessage(
        id: 'g_${DateTime.now().microsecondsSinceEpoch}',
        sessionId: session.id,
        role: 'assistant',
        content: c.greeting.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await state.insertMessage(greeting);
      total = 1;
    }

    // 单页大小 = max(30, 上下文轮数)，保证发给模型的上下文不会缺
    final eff0 = c != null ? resolveCharacter(state.settings, c) : resolveSettings(state.settings);
    _pageSize = eff0.contextTurns > _minPageSize ? eff0.contextTurns : _minPageSize;

    // 计算要加载的窗口
    int start;
    int limit;
    // 始终用数据库重新计算索引（与分页切片同序，避免查找页传入索引因排序差异而偏移）
    final targetIdx = widget.initialSearchTargetId != null
        ? await state.indexOfMessageForSession(session.id, widget.initialSearchTargetId!)
        : null;
    if (targetIdx != null) {
      // 查找定位：只加载目标上方 10 条 + 下方 10 条
      start = (targetIdx - _searchBefore).clamp(0, total);
      limit = (targetIdx + _searchAfter + 1 - start).clamp(1, total - start);
      _pagingSuppressUntil = DateTime.now().millisecondsSinceEpoch + 900;
    } else {
      // 普通进入：只加载最近一页
      limit = total < _pageSize ? total : _pageSize;
      start = total - limit;
    }
    final msgs = total == 0
        ? <ChatMessage>[]
        : await state.messageSliceForSession(session.id, start, limit);

    if (!mounted) return;
    setState(() {
      _character = c;
      _session = session;
      // 转成"最新在前"
      _messages = msgs.reversed.toList();
      _total = total;
      _windowStart = start;
      _worldbook = worldbook;
      _memories = memories;
      // 本地索引：必须按**实际返回条数**算（limit 可能被 total 截断），
      // 否则会差一条、跳到相邻的另一条搜索结果
      _searchReturnIndex =
          targetIdx == null || msgs.isEmpty ? -1 : (start + msgs.length - 1 - targetIdx);
      // 非查找进入直接可见；查找进入先隐藏，等定位完成再显示
      _positioned = targetIdx == null;
      _loading = false;
    });
    if (targetIdx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToIndex(_searchReturnIndex);
      });
    } else {
      // 普通进入：定位到最后一条（内容不满一屏时是空操作，自然停在顶部）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToBottom(animate: false, force: true);
      });
    }
  }

  /// 加载更早的一页（追加到数组末尾 = 最老方向），已有条目索引不变
  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _session == null) return;
    _loadingOlder = true;
    final state = context.read<AppState>();
    final start = (_windowStart - _pageSize).clamp(0, _windowStart);
    final limit = _windowStart - start;
    final older = await state.messageSliceForSession(_session!.id, start, limit);
    if (!mounted) {
      _loadingOlder = false;
      return;
    }
    // 正序列表：往数组尾部追加"更老"会让已有条目整体下移，需要还原锚点
    int anchorRaw = -1;
    double anchorFrac = 0.0;
    final posOld = _itemPositions.itemPositions.value;
    if (posOld.isNotEmpty) {
      var topMost = posOld.first;
      for (final p in posOld) {
        if (p.index < topMost.index) topMost = p;
      }
      anchorRaw = topMost.index;
      anchorFrac = topMost.itemLeadingEdge;
    }
    setState(() {
      // older 是升序（老→新）；数组最新在前，所以倒序追加到末尾
      _messages = [..._messages, ...older.reversed];
      _windowStart = start;
      if (_searchReturnIndex >= 0) _searchReturnIndex += older.length;
      _loadingOlder = false;
    });
    if (anchorRaw >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _itemScroll.jumpTo(
            index: anchorRaw + older.length,
            alignment: anchorFrac.clamp(0.0, 0.99),
          );
        } catch (_) {}
      });
    }
  }

  /// 加载更晚的一页（插入到数组开头 = 最新方向），并保持视口锚点不跳
  Future<void> _loadNewer() async {
    if (_loadingNewer || !_hasNewer || _session == null) return;
    _loadingNewer = true;
    final state = context.read<AppState>();
    final offset = _windowStart + _messages.length;
    final remain = _total - offset;
    final limit = remain < _pageSize ? remain : _pageSize;

    final newer = await state.messageSliceForSession(_session!.id, offset, limit);
    if (!mounted) {
      _loadingNewer = false;
      return;
    }
    setState(() {
      _messages = [...newer.reversed, ..._messages];
      _loadingNewer = false;
      if (_searchReturnIndex >= 0) _searchReturnIndex += newer.length;
    });
    // 正序列表里"插入更新的消息"不改变已有条目的列表索引，无需还原锚点
  }

  /// 发送消息前：若当前不在最新窗口，先回到最新窗口
  Future<void> _ensureLatestWindow() async {
    if (!_hasNewer) return;
    final state = context.read<AppState>();
    final session = _session;
    if (session == null) return;
    final total = await state.countMessagesForSession(session.id);
    final limit = total < _pageSize ? total : _pageSize;
    final start = total - limit;
    final msgs = total == 0
        ? <ChatMessage>[]
        : await state.messageSliceForSession(session.id, start, limit);
    if (!mounted) return;
    setState(() {
      _messages = msgs.reversed.toList(); // 最新在前
      _total = total;
      _windowStart = start;
      _searchReturnIndex = -1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _itemScroll.jumpTo(index: _rawCount - 1, alignment: 1.0);
      } catch (_) {}
    });
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
  /// 把当前待发送附件转成 Attachment（图片带宽高，便于气泡预留占位）
  Future<List<Attachment>> _buildAttachments() async {
    final out = <Attachment>[];
    for (final a in _attachments) {
      // 用"扩展名"判断，避免用「选择文件」发图片时被当成普通文件
      final img = a.isImage || isImagePath(a.name.isNotEmpty ? a.name : a.path);
      if (img) {
        final size = await imageSizeOf(a.path);
        out.add(Attachment(
          type: 'image',
          path: a.path,
          name: a.name,
          width: size?.$1 ?? 0,
          height: size?.$2 ?? 0,
        ));
      } else {
        out.add(Attachment(type: 'file', path: a.path, name: a.name));
      }
    }
    return out;
  }

  /// 把附件与文字合并成一条消息内容（保留文本标记，兼容旧逻辑/模型上下文）
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
    var session = _session;
    if (session == null) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final content = _composeContent(text);
    if (mounted) setState(() => _stage = '正在处理附件…');
    final atts = await _buildAttachments();
    if (mounted) setState(() => _stage = '正在发送请求…');
    // 若正在查看历史窗口，先切回最新窗口，保证新消息接在最后
    if (_hasNewer) await _ensureLatestWindow();
    session = _session;
    if (session == null) return;
    final sid = session.id;
    await state.insertMessage(ChatMessage(
      id: id,
      sessionId: sid,
      role: 'user',
      content: content,
      attachments: atts,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    setState(() {
      // 最新在前：新消息插到数组开头
      _messages.insert(
          0,
          ChatMessage(
            id: id,
            sessionId: sid,
            role: 'user',
            content: content,
            attachments: atts,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
      _total += 1;
      _input.clear();
      _attachments.clear();
    });
    _jumpToBottom(force: true);
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
    _jumpToBottom(force: true);
    final seq = ++_streamSeq;
    try {
      await _runStreamReply(state, character, provider);
    } catch (e) {
      // 兜底：任何未预期异常都不允许把 UI 卡死在"等待模型响应…"
      if (mounted && seq == _streamSeq) _toast('生成失败：$e');
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
      _stage = '';
    });
  }

  Future<void> _runStreamReply(
      AppState state, Character character, ProviderConfig provider) async {
    // _messages 是最新在前；发给模型必须是时间正序
    final history = _messages
        .where((m) => m.role != 'system' && m.role != 'error' && m.role != 'note')
        .toList()
        .reversed
        .toList();
    final payload = PromptBuilder.buildMessages(
      character: character,
      eff: resolveCharacter(state.settings, character),
      worldbook: _worldbook,
      memories: _memories,
      history: history,
      extraPrompt: state.settings.systemPromptExtra,
    );
    // 最后一条用户消息：把图片直接发给多模态模型 / 读取文本文件内容（在下面统一处理）
    final lastUserIdx = payload.lastIndexWhere((e) => e['role'] == 'user');
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final sid = _session!.id;
    final buf = StringBuffer();
    final rbuf = StringBuffer();
    String? errText;
    var visionRejected = false;

    // 只把"最后一条用户消息"替换成多模态内容
    dynamic richContent;
    String? textOnly;
    var usedRich = false;
    if (lastUserIdx >= 0) {
      final lastUser = history.lastWhere((m) => m.role == 'user', orElse: () => history.last);
      if (lastUser.attachments.isNotEmpty) {
        textOnly = contentForModel(lastUser);
        if (mounted) setState(() => _stage = '正在读取附件…');
        richContent = await buildUserContent(lastUser, vision: true)
            .timeout(const Duration(seconds: 25), onTimeout: () => null);
        if (mounted) setState(() => _stage = '等待模型响应…');
        if (richContent != null) {
          payload[lastUserIdx] = {'role': 'user', 'content': richContent};
          usedRich = richContent is List;
        }
      }
    }

    Future<String?> run({bool stream = true}) async {
      try {
        if (stream) {
          // 统一走流式：deepseek-flash 是思考型模型，正文在 content、思考在 reasoning_content，
          // 只要拿到流式 delta 就能边生成边显示思考。
          await for (final delta in ApiClient()
              .streamChat(
                baseUrl: provider.baseUrl,
                apiKey: provider.apiKey,
                model: (character.model?.isNotEmpty ?? false) ? character.model! : provider.model,
                messages: payload,
                temperature: 0.9,
                // 思考型模型必须留足 token，否则思考吃光 token 导致正文为空
                maxTokens: usedRich ? 4096 : null,
              )
              // 首包超时：纯文字 60 秒（思考型模型首包慢）；带图 25 秒（正常几秒必回），
              // 超时就直接降级为非流式重发，不让用户干等一分钟
              .timeout(Duration(seconds: usedRich ? 25 : 60))) {
            if (delta.content.isNotEmpty) buf.write(delta.content);
            if (delta.reasoning.isNotEmpty) rbuf.write(delta.reasoning);
            if (!mounted) continue;
            setState(() {
              _streamText = buf.toString();
              _streamReasoning = rbuf.toString();
            });
            // 跟随最新（内容不满一屏时是空操作）
            _jumpToBottom();
          }
          return null;
        }
        // 非流式兜底：带图的流式挂住 / 服务端不支持流式多模态时用。
        // completeChatFull 会把 reasoning_content 一起返回，思考内容不会丢。
        final r = await ApiClient()
            .completeChatFull(
              baseUrl: provider.baseUrl,
              apiKey: provider.apiKey,
              model: (character.model?.isNotEmpty ?? false) ? character.model! : provider.model,
              messages: payload,
              temperature: 0.9,
              maxTokens: 4096,
            )
            .timeout(const Duration(seconds: 90));
        buf.write(r.content);
        rbuf.write(r.reasoning);
        if (mounted) {
          setState(() {
            _streamText = buf.toString();
            _streamReasoning = rbuf.toString();
          });
        }
        return null;
      } catch (e) {
        return e is ApiException ? e.message : e.toString();
      }
    }

    if (mounted) setState(() => _stage = '等待模型响应…');
    errText = await run();

    // 带图时流式失败（首包超时 / 服务端不接受流式多模态）→ 退回非流式重发，
    // 仍然带着图片，思考内容由 completeChatFull 一并取回
    if (errText != null && usedRich) {
      if (mounted) setState(() => _stage = '流式未响应，改用普通请求重试…');
      buf.clear();
      rbuf.clear();
      errText = await run(stream: false);
    }

    // 仍然失败 → 去掉附件，用纯文字重发一次
    if (errText != null && textOnly != null) {
      visionRejected = true;
      payload[lastUserIdx] = {'role': 'user', 'content': textOnly};
      buf.clear();
      rbuf.clear();
      errText = await run();
    }

    // 思考型模型有时只吐 reasoning_content（token 被思考吃光），
    // 这时用思考内容兜底，避免"什么都没有"
    var finalText = buf.toString().trim();
    if (finalText.isEmpty && rbuf.toString().trim().isNotEmpty) {
      final r = rbuf.toString().trim();
      final cut = r.lastIndexOf('\n');
      finalText = (cut > 0 ? r.substring(cut + 1) : r).trim();
      if (finalText.length > 400) finalText = finalText.substring(0, 400);
    }
    if (finalText.isNotEmpty) {
      final asst = ChatMessage(
        id: id,
        sessionId: sid,
        role: 'assistant',
        content: finalText,
        reasoning: rbuf.toString().trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await state.insertMessage(asst);
      if (mounted) {
        setState(() {
          _messages.insert(0, asst); // 最新在前
          _total += 1;
        });
      }
    }
    if (errText != null) {
      // 模型报错：作为一条红色错误气泡显示（同时入库，下次进入也能看到）
      final errMsg = ChatMessage(
        id: 'err_$id',
        sessionId: sid,
        role: 'error',
        content: errText,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      try {
        await state.insertMessage(errMsg);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _messages.insert(0, errMsg);
          _total += 1;
        });
      }
    }
    if (visionRejected) {
      final note = ChatMessage(
        id: 'note_$id',
        sessionId: sid,
        role: 'note',
        content: '当前模型没有接受图片，已自动改用文字描述重试（图片未被识别）。'
            '若该模型确实支持看图，请把上方的报错信息发给我。',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      try {
        await state.insertMessage(note);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _messages.insert(0, note);
          _total += 1;
        });
      }
    }
    // 先复位流式状态（解锁输入）再做自动记忆，避免长耗时阻塞发送
    _endStreaming();
    await _autoMemory(state);
  }

  /// 自动生成长记忆（每 every 条角色回复触发一次）
  Future<void> _autoMemory(AppState state) async {
    final eff = _character != null
        ? resolveCharacter(state.settings, _character!)
        : resolveSettings(state.settings);
    final every = eff.autoMemoryEvery;
    if (every <= 0 || !eff.memoryEnabled) return;
    // 用"角色已回复的条数"作为计数（查库，不受窗口加载影响），避免奇偶错位
    final turns = _session == null ? 0 : await state.countAssistantForSession(_session!.id);
    if (turns == 0 || turns % every != 0) return;
    final provider = _resolveProvider(state);
    if (provider == null || _character == null) return;
    // _messages 是最新在前；发给模型必须是时间正序
    final history = _messages
        .where((m) => m.role != 'system' && m.role != 'error' && m.role != 'note')
        .toList()
        .reversed
        .toList();
    if (history.isEmpty) return;
    // 把最近对话整理成"一段文本"交给模型提炼，避免模型把它当成对话续写
    final tail = history.length > 8 ? history.sublist(history.length - 8) : history;
    final transcript = MemoryHelper.buildTranscript(
      tail.map((m) => (m.role == 'user' ? '玩家' : _character!.name, m.content)).toList(),
    );
    final payload = MemoryHelper.buildMessages(transcript);
    try {
      final t = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: (_character!.model?.isNotEmpty ?? false) ? _character!.model! : provider.model,
        messages: payload,
        temperature: 0.3,
      )).trim();
      if (MemoryHelper.isValid(t)) {
        await state.addMemory(MemoryItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          characterId: _character!.id,
          content: MemoryHelper.clean(t),
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
    setState(() {
      _messages.removeWhere((x) => x.id == m.id);
      if (_total > 0) _total -= 1;
    });
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
    setState(() {
      // 删除这条及其之后的（更新的）消息；最新在前 → 保留比它更老的部分
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
    // _messages 是最新在前；发给模型必须是时间正序
    final history = _messages
        .where((m) => m.role != 'system' && m.role != 'error' && m.role != 'note')
        .toList()
        .reversed
        .toList();
    final payload = PromptBuilder.buildMessages(
      character: character,
      eff: resolveCharacter(state.settings, character),
      worldbook: _worldbook,
      memories: _memories,
      history: history,
      extraPrompt: state.settings.systemPromptExtra,
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
    _jumpToBottom(force: true);
    final seq = ++_streamSeq;
    try {
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
          _messages.insert(0, asst); // 最新在前
          _total += 1;
        });
      }
    } catch (e) {
      if (mounted && seq == _streamSeq) _toast('续写失败：$e');
    } finally {
      if (seq == _streamSeq) _endStreaming();
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
    // 最新在前：从索引 0 开始找最近一条角色消息
    int newestAssistant = -1;
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].role == 'assistant' && !_messages[i].id.startsWith('g_')) {
        newestAssistant = i;
        break;
      }
    }
    if (newestAssistant == -1) {
      _toast('没有可重新生成的消息');
      return;
    }
    final removed = _messages[newestAssistant];
    await state.deleteMessage(removed.id);
    setState(() {
      _messages.removeAt(newestAssistant);
      if (_total > 0) _total -= 1;
    });
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
    // _messages 是最新在前；发给模型必须是时间正序
    final history = _messages
        .where((m) => m.role != 'system' && m.role != 'error' && m.role != 'note')
        .toList()
        .reversed
        .toList();
    final payload = <Map<String, String>>[
      {
        'role': 'system',
        'content':
            '你是玩家「${eff.userName}」（${eff.userGender}，与角色的关系：${eff.userRelation.isEmpty ? '朋友' : eff.userRelation}）。'
            '你是正在和角色对话的那个人。\\n${eff.userBackground.isEmpty ? '' : '你的身份背景：${eff.userBackground}'}'
      },
    ];
    for (final m in history) {
      payload.add({'role': m.role, 'content': contentForModel(m)});
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

  /// 添加图片附件
  Future<void> _addImage() async {
    // compressionQuality: 0 关闭 file_picker 的默认压缩：
    // 默认压缩会把 JPEG 写到公共 Pictures 目录，被相册索引 → 每选一次图相册多一张。
    final r = await FilePicker.platform.pickFiles(
        type: FileType.image, withData: false, compressionQuality: 0);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    var path = f.path ?? '';
    if (path.isEmpty) return;
    // 搬进私有目录并删除选择器缓存副本，避免相册多出一张
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
  Future<void> _showPlusMenu() async {
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
      await _showModelSwitch();
    } else if (choice == 'image') {
      await _addImage();
    } else if (choice == 'file') {
      await _addFile();
    }
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

  /// 模型报错气泡：红色、左上角感叹号，明显但可读。
  Widget _errorBubble(ChatMessage m, {bool isNote = false}) {
    final scheme = Theme.of(context).colorScheme;
    final accent = isNote ? const Color(0xFFB26A00) : const Color(0xFFD93025);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          border: Border.all(color: accent, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isNote ? Icons.warning_amber_rounded : Icons.error_outline,
                    size: 18, color: accent),
                const SizedBox(width: 6),
                Text(isNote ? '图片未生效' : '模型调用失败',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: accent)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _deleteMessage(m),
                  child: Icon(Icons.close, size: 16, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              m.content,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFFFB4AB)
                    : const Color(0xFF8C1D18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 内容是否不满一屏：决定列表方向
  bool _contentFits = false;

  /// 普通列表按"内容是否满一屏"切换方向：
  /// - 不满一屏 → 正序列表，顶部对齐（空白在下方）
  /// - 满一屏   → 反序列表，offset 0 即底部，发消息/流式自动贴底
  /// 两种方向的 0 偏移含义不同，所以切换后必须显式归零（正序=顶部，反序=底部）。
  void _syncFitState() {
    if (_anchored || _loading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final fits = _scroll.position.maxScrollExtent <= 0.5;
      if (fits == _contentFits) return;
      setState(() => _contentFits = fits);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(0);
      });
    });
  }

  /// 回到底部（最新一条）。正序列表里最新在最后，按索引定位并对齐到底边。
  void _jumpToBottom({bool animate = true, bool force = false, int attempt = 0}) {
    // 普通列表：反序 offset 0 = 底部；正序且不满一屏时无需滚动
    if (!_anchored) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_scroll.hasClients && attempt < 8) {
          Future.delayed(Duration(milliseconds: 50 + attempt * 40), () {
            if (mounted) _jumpToBottom(animate: animate, force: force, attempt: attempt + 1);
          });
          return;
        }
        if (!_scroll.hasClients) return;
        final pos = _scroll.position;
        if (_contentFits) {
          // 正序列表：内容本就不满一屏，没有可滚动的空间；
          // 若刚好在这一帧溢出（方向尚未切换），先贴到底部，下一帧会切回反序列表
          if (pos.maxScrollExtent > 0.5 && pos.pixels < pos.maxScrollExtent - 0.5) {
            pos.jumpTo(pos.maxScrollExtent);
          }
          return;
        }
        // 反序列表：offset 0 = 视觉底部，直接跳 0
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
        var maxIdx = positions.first.index;
        for (final p in positions) {
          if (p.index > maxIdx) maxIdx = p.index;
        }
        // 不在底部附近就不强行拉回
        if (maxIdx < _rawCount - 3) return;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 列表还没挂载（首帧/数据刚到位）时重试，否则跳转会被静默吞掉
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
            index: _rawCount - 1,
            alignment: 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        } else {
          _itemScroll.jumpTo(index: _rawCount - 1, alignment: 1.0);
        }
      } catch (_) {}
    });
  }

  /// 消息本地索引 → SPL 原始索引（唯一换算来源，build 与定位共用同一套规则）。
  /// 私聊列表是正序 + 统一按"距底部位置"排列：rawIndex 0 = 最老那条。
  int? _rawOfMessage(int msgIndex) {
    if (msgIndex < 0 || msgIndex >= _messages.length) return null;
    final streamOffset = _streaming ? 1 : 0;
    final itemCount = _messages.length + streamOffset + (_searchReturnIndex >= 0 ? 1 : 0);
    final fromBottom = msgIndex + streamOffset; // 距底部的位置：0 = 最新
    return itemCount - 1 - fromBottom;
  }

  /// 查找聊天记录后定位到某条消息，并让它**置顶**（对齐视口顶部）。
  ///
  /// 置顶 = 目标条目的起始边落在视口顶部，这是 SPL `jumpTo` 原生能力，
  /// 不需要知道条目高度，因此**一次跳、精确、绝不出屏幕**。
  /// 正序列表（reverse:false）下 alignment: 0 就是把目标顶到最上方。
  void _scrollToIndex(int idx) {
    var msgIndex = idx;
    final targetId = widget.initialSearchTargetId;
    if (targetId != null) {
      final found = _messages.indexWhere((m) => m.id == targetId);
      if (found >= 0) msgIndex = found;
    }
    final raw = _rawOfMessage(msgIndex);
    if (raw == null) {
      // 找不到目标（消息已删等）：别让列表一直透明
      if (!_positioned && mounted) setState(() => _positioned = true);
      return;
    }
    if (!_positioned) setState(() => _positioned = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _itemScroll.jumpTo(index: raw, alignment: 0);
      } catch (_) {}
      if (!_positioned) setState(() => _positioned = true);
    });
    // 兜底：极端情况下测量/挂载失败也要把列表显示出来，不能一直透明
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted && !_positioned) setState(() => _positioned = true);
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
    // 加载中不显示转圈（长会话读库耗时会让"卡一下"更明显），
    // 直接铺主题背景，数据就绪后无缝出现内容。
    if (_loading) return const Scaffold(body: SizedBox.shrink());
    final c = _character!;
    final state = context.watch<AppState>();
    final showCharAvatar = _hideCharAvatar == null
        ? state.settings.showCharAvatar
        : !_hideCharAvatar!;
    final showUserAvatar = _hideUserAvatar == null
        ? state.settings.showUserAvatar
        : !_hideUserAvatar!;
    final effBg = _effectiveBackground(state, c);
    final hasBg = effBg.isNotEmpty && File(effBg).existsSync();

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

  /// 消息列表：索引锚定（ScrollablePositionedList）+ reverse。
  /// 索引 0 = 最新消息（视觉底部）；定位/分页都按"第几条"，不依赖像素高度，
  /// 因此不会出现"估算偏差→校正→跳到底部"的问题。
  Widget _messageList(AppState state, Character c, bool showCharAvatar, bool showUserAvatar, double topInset) {
    final showBanner = _searchReturnIndex >= 0;
    final msgCount = _messages.length;
    final streamOffset = _streaming ? 1 : 0;
    final itemCount = msgCount + streamOffset + (showBanner ? 1 : 0);
    _rawCount = itemCount;

    Widget streamItem() {
      final streamingMsg = ChatMessage(
          id: 'st', sessionId: _session!.id, role: 'assistant', content: _streamText, createdAt: 0);
      final streamTop = _streamReasoning.isNotEmpty && state.settings.showThinking
          ? ThinkingToggle(reasoning: _streamReasoning)
          : (_stage.isNotEmpty
              ? Text(_stage,
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))
              : const ThinkingIndicator());
      return MessageBubble(
        message: streamingMsg,
        isUser: false,
        avatar: buildCharacterAvatar(context, c, 34),
        senderName: c.name,
        showAvatar: showCharAvatar,
        isCurrent: true,
        fontScale: state.settings.fontSize,
        topContent: streamTop,
      );
    }

    Widget msgItem(int k) {
      final m = _messages[k];
      if (m.role == 'error' || m.role == 'note') {
        return _errorBubble(m, isNote: m.role == 'note');
      }
      final reasoning = (m.role == 'assistant' && m.reasoning.isNotEmpty) ? m.reasoning : '';
      return MessageBubble(
        message: m,
        isUser: m.role == 'user',
        avatar: m.role == 'user'
            ? buildUserAvatar(context, state.settings, 34)
            : buildCharacterAvatar(context, c, 34),
        senderName: m.role == 'user' ? state.settings.personaName : c.name,
        showAvatar: m.role == 'user' ? showUserAvatar : showCharAvatar,
        footer: k == 0 && !_streaming ? _actionFooter(state, m) : null,
        topContent: reasoning.isNotEmpty && state.settings.showThinking
            ? ThinkingToggle(reasoning: reasoning)
            : null,
        bubbleColor: m.role == 'user'
            ? parseHexColor(state.settings.bubbleSelfColor)
            : parseHexColor(state.settings.bubbleCharColor),
        bubbleOpacity: state.settings.bubbleOpacity,
        fontScale: state.settings.fontSize,
        highlight: _searchReturnIndex >= 0 && k == _searchReturnIndex,
        onCopy: () => _copy(m),
        onDelete: () => _deleteMessage(m),
        onDeleteFromHere: () => _deleteFromHere(m),
      );
    }

    // 普通进入：内容不满一屏时用**正序**列表（顶部对齐，空白落在下方，与微信一致）；
    // 内容超过一屏时用**反序**列表（offset 0 就是视觉底部，发消息/流式自动贴底）。
    // 反序列表在内容不足一屏时会把内容钉在底部、空白全在上方 —— 这就是"上方空白"的成因。
    if (!_anchored) {
      _syncFitState();
      if (_contentFits) {
        return ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.only(top: topInset + 8, bottom: 12),
          itemCount: itemCount,
          itemBuilder: (context, i) {
            // 正序：索引 0 = 最顶部（最老的一条）
            var p = i;
            if (showBanner) {
              if (p == 0) return _searchReturnBanner();
              p -= 1;
            }
            if (p >= msgCount) return streamItem();
            return msgItem(msgCount - 1 - p);
          },
        );
      }
      return ListView.builder(
        controller: _scroll,
        reverse: true, // 反序：offset 0 就是视觉底部
        padding: EdgeInsets.only(top: topInset + 8, bottom: 12),
        itemCount: itemCount,
        itemBuilder: (context, i) {
          if (streamOffset == 1 && i == 0) return streamItem();
          final k = i - streamOffset;
          if (showBanner && k == msgCount) return _searchReturnBanner();
          if (k < 0 || k >= msgCount) return const SizedBox.shrink();
          return msgItem(k);
        },
      );
    }

    // 查找定位：定位完成前整张列表透明（仍参与布局，所以能量高度），
    // 避免"先贴到起始边、下一帧才居中"的中间态被看到。
    final searchRaw = _searchReturnIndex >= 0 ? _rawOfMessage(_searchReturnIndex) : null;
    return Opacity(
      opacity: _positioned ? 1 : 0,
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScroll,
        itemPositionsListener: _itemPositions,
        initialScrollIndex: searchRaw ?? 0,
        initialAlignment: 0.0,
        reverse: false,
        padding: EdgeInsets.only(top: topInset + 8, bottom: 12),
        itemCount: itemCount,
        itemBuilder: (context, rawIndex) {
          // 统一换算成"距底部的位置"：0 = 最新
          final i = itemCount - 1 - rawIndex;
          if (streamOffset == 1 && i == 0) return streamItem();
          final k = i - streamOffset; // 本地索引：0 = 最新
          if (showBanner && k == msgCount) return _searchReturnBanner();
          if (k < 0 || k >= msgCount) return const SizedBox.shrink();
          return msgItem(k);
        },
      ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 附件预览（在输入框上方，不发送）
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
                  onTap: _streaming ? null : _showPlusMenu,
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
          ],
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
                // 模型名通常与接口绑定，换接口时必须换用新接口的默认模型。
                _modelCtrl.text = p.model;
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
