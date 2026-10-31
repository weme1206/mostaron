import 'package:flutter/foundation.dart';
import '../data/db.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/export_service.dart';
import '../services/settings_resolver.dart';
import '../services/character_card_service.dart';

class AppState extends ChangeNotifier {
  final AppDatabase _db = AppDatabase.instance;

  AppSettings settings = AppSettings();
  List<ProviderConfig> providers = [];
  List<Character> characters = [];
  List<WorldbookEntry> globalWorldbook = [];
  List<ChatGroup> groups = [];
  // 每个角色/群聊的最新消息（用于主页卡片副标题）
  Map<String, String> lastCharMsg = {};
  Map<String, String> lastGroupMsg = {};
  // 每个角色/群聊的最新消息时间（ms）
  Map<String, int> lastCharTime = {};
  Map<String, int> lastGroupTime = {};

  bool initialized = false;

  Future<void> init() async {
    settings = await _db.loadSettings();
    providers = await _db.getProviders();
    characters = await _db.getCharacters();
    globalWorldbook = await _db.getWorldbook(null);
    groups = await _db.getGroups();
    await _refreshLastMessages();
    initialized = true;
    notifyListeners();
  }

  Future<void> _refreshLastMessages() async {
    lastCharMsg.clear();
    lastCharTime.clear();
    for (final c in characters) {
      lastCharMsg[c.id] = await _db.lastMessageForCharacter(c.id);
      lastCharTime[c.id] = await _db.lastMessageTimeForCharacter(c.id);
    }
    lastGroupMsg.clear();
    lastGroupTime.clear();
    for (final g in groups) {
      lastGroupMsg[g.id] = await _db.lastMessageForGroup(g.id);
      lastGroupTime[g.id] = await _db.lastMessageTimeForGroup(g.id);
    }
  }

  // ---------------- Settings ----------------
  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    await _db.saveSettings(s);
    notifyListeners();
  }

  // ---------------- Providers ----------------
  Future<void> addProvider(ProviderConfig c) async {
    if (providers.isEmpty) c.isDefault = true;
    await _db.upsertProvider(c);
    providers = await _db.getProviders();
    notifyListeners();
  }

  Future<void> updateProvider(ProviderConfig c) async {
    await _db.upsertProvider(c);
    providers = await _db.getProviders();
    notifyListeners();
  }

  Future<void> deleteProvider(String id) async {
    await _db.deleteProvider(id);
    providers = await _db.getProviders();
    notifyListeners();
  }

  Future<void> setDefaultProvider(String id) async {
    await _db.setDefaultProvider(id);
    providers = await _db.getProviders();
    settings.defaultProviderId = id;
    await _db.saveSettings(settings);
    notifyListeners();
  }

  ProviderConfig? getProviderById(String? id) {
    if (id == null || id.isEmpty) {
      return providers.isEmpty ? null : (providers.firstWhere((p) => p.isDefault, orElse: () => providers.first));
    }
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return providers.isEmpty ? null : providers.first;
  }

  // ---------------- Characters ----------------
  Future<void> addCharacter(Character c) async {
    if (c.lastActivity == 0) c.lastActivity = DateTime.now().millisecondsSinceEpoch;
    await _db.upsertCharacter(c);
    characters = await _db.getCharacters();
    notifyListeners();
  }

  /// 导入 SillyTavern 角色卡，创建为新角色；若带世界书则加入全局世界书库。
  /// [avatarPath]：若为图片角色卡，用该图片作为头像。
  /// 返回新建角色（失败返回 null）。
  Future<Character?> importCharacterCard(Uint8List bytes, {String? avatarPath}) async {
    final card = CharacterCardService.parseBytes(bytes);
    if (card == null) return null;
    final id = _uid();
    final c = CharacterCardService.toCharacter(card, id);
    // 图片角色卡：用图片本身作为头像
    if (avatarPath != null && avatarPath.isNotEmpty) {
      c.avatar = avatarPath;
    }
    await _db.upsertCharacter(c);
    if (card.worldbook.isNotEmpty) {
      final ids = <String>[];
      for (final w in card.worldbook) {
        await _db.upsertWorldbook(w);
        ids.add(w.id);
      }
      // 卡片自带的世界书必须挂到角色上，否则角色默认"一条都不启用"，等于没导入
      if (ids.isNotEmpty) {
        c.worldbookIds = [...c.worldbookIds, ...ids];
        await _db.upsertCharacter(c);
      }
    }
    // 如果角色卡里带有聊天记录（导出时勾选），一并恢复
    final ext = c.extensions['mostaron'];
    if (ext is Map && ext['chat'] is List) {
      final list = ext['chat'] as List;
      if (list.isNotEmpty) {
        final session = await getOrCreateSession(c.id);
        for (final raw in list) {
          if (raw is! Map) continue;
          final role = raw['role']?.toString() ?? 'user';
          if (role != 'user' && role != 'assistant' && role != 'system') continue;
          await _db.insertMessage(ChatMessage(
            id: _uid(),
            sessionId: session.id,
            role: role,
            content: raw['content']?.toString() ?? '',
            reasoning: raw['reasoning']?.toString() ?? '',
            attachments: decodeAttachments(raw['meta']),
            createdAt: (raw['created_at'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
          ));
        }
      }
    }
    characters = await _db.getCharacters();
    globalWorldbook = await _db.getWorldbook(null);
    notifyListeners();
    return c;
  }

  Future<void> updateCharacter(Character c) async {
    // 编辑角色时保留原有的最近活跃时间，避免卡片沉底
    final old = await _db.getCharacter(c.id);
    final keep = (old?.lastActivity ?? 0) > c.lastActivity ? old!.lastActivity : c.lastActivity;
    await _db.upsertCharacter(keep == c.lastActivity ? c : c.copyWith(lastActivity: keep));
    characters = await _db.getCharacters();
    await _refreshLastMessages();
    notifyListeners();
  }

  Future<void> deleteCharacter(String id) async {
    await _db.deleteCharacter(id);
    characters = await _db.getCharacters();
    notifyListeners();
  }

  Future<Character?> getCharacter(String id) => _db.getCharacter(id);

  Future<void> togglePinCharacter(String id) async {
    final c = await _db.getCharacter(id);
    if (c != null) {
      await _db.upsertCharacter(c.copyWith(pinned: !c.pinned));
      characters = await _db.getCharacters();
      notifyListeners();
    }
  }

  /// 克隆角色（新 ID，名字加"副本"；全新，不携带聊天与记忆，但保留全部设置）
  Future<void> cloneCharacter(Character c) async {    final nid = DateTime.now().microsecondsSinceEpoch.toString();
    final nc = Character(
      id: nid,
      name: '${c.name} 副本',
      avatar: c.avatar,
      persona: c.persona,
      personality: c.personality,
      tone: c.tone,
      background: c.background,
      greeting: c.greeting,
      chatBackground: c.chatBackground,
      providerId: c.providerId,
      model: c.model,
      replyStyle: c.replyStyle,
      worldbookIds: c.worldbookIds,
      settings: c.settings,
      userName: c.userName,
      userGender: c.userGender,
      userRelation: c.userRelation,
      userBackground: c.userBackground,
      scenario: c.scenario,
      exampleDialogue: c.exampleDialogue,
      creatorNotes: c.creatorNotes,
      systemPrompt: c.systemPrompt,
      postHistoryInstructions: c.postHistoryInstructions,
      alternateGreetings: c.alternateGreetings,
      tags: c.tags,
      creator: c.creator,
      characterVersion: c.characterVersion,
      extensions: c.extensions,
      lastActivity: DateTime.now().millisecondsSinceEpoch,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.upsertCharacter(nc);
    characters = await _db.getCharacters();
    notifyListeners();
  }

  /// 完整克隆角色：克隆所有设置，并可携带聊天消息与记忆。
  Future<void> cloneCharacterFull(Character c, {required bool includeHistory}) async {
    final nid = DateTime.now().microsecondsSinceEpoch.toString();
    await _db.cloneCharacterFull(c, nid, includeHistory);
    characters = await _db.getCharacters();
    notifyListeners();
  }

  /// 完整克隆群聊。
  Future<void> cloneGroupFull(ChatGroup g, {required bool includeHistory}) async {
    final nid = DateTime.now().microsecondsSinceEpoch.toString();
    await _db.cloneGroupFull(g, nid, includeHistory);
    groups = await _db.getGroups();
    notifyListeners();
  }

  /// 重置角色描述（保留名字与头像，清空其它设定）
  Future<void> resetCharacter(Character c) async {
    final nc = c.copyWith(
      persona: '',
      personality: '',
      tone: '',
      background: '',
      greeting: '',
      chatBackground: '',
      worldbookIds: [],
    );
    await _db.upsertCharacter(nc);
    characters = await _db.getCharacters();
    notifyListeners();
  }

  // ---------------- Worldbook ----------------
  Future<void> refreshWorldbook(String? characterId) async {
    if (characterId == null) {
      globalWorldbook = await _db.getWorldbook(null);
    }
    notifyListeners();
  }

  Future<List<WorldbookEntry>> worldbookFor(String? characterId) =>
      _db.getWorldbook(characterId);

  Future<void> addWorldbook(WorldbookEntry w) async {
    await _db.upsertWorldbook(w);
    await refreshWorldbook(w.characterId);
  }

  Future<void> updateWorldbook(WorldbookEntry w) async {
    await _db.upsertWorldbook(w);
    await refreshWorldbook(w.characterId);
  }

  Future<void> deleteWorldbook(String id, String? characterId) async {
    await _db.deleteWorldbook(id);
    // 清理角色/群聊里已失效的 id，避免"已启用 N 条"虚高
    var touched = false;
    for (final c in characters) {
      if (c.worldbookIds.contains(id)) {
        c.worldbookIds = c.worldbookIds.where((e) => e != id).toList();
        await _db.upsertCharacter(c);
        touched = true;
      }
    }
    for (final g in groups) {
      if (g.worldbookIds.contains(id)) {
        g.worldbookIds = g.worldbookIds.where((e) => e != id).toList();
        await _db.upsertGroup(g);
        touched = true;
      }
    }
    if (touched) {
      characters = await _db.getCharacters();
      groups = await _db.getGroups();
    }
    await refreshWorldbook(characterId);
  }

  // ---------------- Memory ----------------
  final Set<String> _compressing = {};

  Future<List<MemoryItem>> memoriesFor(String? characterId) =>
      _db.getMemories(characterId);

  /// 群聊中某角色记忆的归属键：
  /// - whole     群整体记忆，所有角色共用一份
  /// - separate  该角色在这个群里的**独立记忆**（与私聊隔离）
  /// - synced    与私聊**共用**该角色的记忆
  /// 之前 separate 和 synced 都写 character.id，两者行为完全一样，
  /// 且所谓"独立"其实是和私聊共享。
  String groupMemoryOwner(ChatGroup g, Character c) {
    switch (g.memoryMode) {
      case 'separate':
        return 'group_${g.id}_char_${c.id}';
      case 'synced':
        return c.id;
      default:
        return 'group_${g.id}';
    }
  }

  Future<void> addMemory(MemoryItem m) async {
    await _db.upsertMemory(m);
    final limit = await _memoryLimitFor(m.characterId);
    if (limit > 0) {
      // 记忆达到上限时压缩最老的记忆（不阻塞调用方）
      _maybeCompressMemories(m.characterId, limit);
    }
  }

  /// 记忆压缩（用户设定）：
  ///   compressCount = floor(非置顶记忆数 × 压缩数量比)
  ///   keepCount     = floor(compressCount × (1 − 压缩比例))
  ///   keepCount == 0 → 直接删除这批记忆
  /// 置顶记忆永不参与压缩。
  Future<void> _maybeCompressMemories(String? ownerId, int limit) async {
    final key = ownerId ?? '__global__';
    if (_compressing.contains(key)) return;
    _compressing.add(key);
    try {
      final all = await _db.getMemories(ownerId);
      final nonPinned = all.where((m) => !m.pinned).toList();
      if (nonPinned.length < limit) return;

      final countRatio = settings.memoryCompressCountRatio.clamp(0.1, 1.0);
      final keepRatio = settings.memoryCompressKeepRatio.clamp(0.1, 1.0);

      final compressCount = (nonPinned.length * countRatio).floor();
      if (compressCount < 1) return;
      final targets = nonPinned.take(compressCount).toList(); // 最老的
      final keepCount = (compressCount * (1 - keepRatio)).floor();
      final ids = targets.map((m) => m.id).toList();

      if (keepCount < 1) {
        // 压缩比例 100%（或向下取整为 0）→ 直接删除旧记忆
        await _db.deleteMemoriesByIds(ids);
        notifyListeners();
        return;
      }

      final lines = await _summarizeMemories(targets, keepCount);
      if (lines == null || lines.isEmpty) {
        // 无可用接口或失败：退化为直接删除这批，避免无限增长
        await _db.deleteMemoriesByIds(ids);
        notifyListeners();
        return;
      }
      final baseTime = targets.first.createdAt;
      final items = <MemoryItem>[];
      for (var i = 0; i < lines.length; i++) {
        items.add(MemoryItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_s$i',
          characterId: ownerId,
          content: lines[i],
          pinned: false,
          createdAt: baseTime + i,
          kind: 'summary',
          summaryOf: ids,
        ));
      }
      await _db.deleteMemoriesByIds(ids, insert: items);
      notifyListeners();
    } catch (_) {
      // 压缩失败保持原样
    } finally {
      _compressing.remove(key);
    }
  }

  /// 让模型把旧记忆压缩成 [keepCount] 条；失败返回 null。
  Future<List<String>?> _summarizeMemories(List<MemoryItem> targets, int keepCount) async {
    final provider = getProviderById(null);
    if (provider == null) return null;
    final buf = StringBuffer();
    for (final m in targets) {
      final text = m.content.trim();
      if (text.isNotEmpty) buf.writeln('- $text');
    }
    if (buf.isEmpty) return const [];
    try {
      final raw = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: provider.model,
        messages: [
          {
            'role': 'system',
            'content': '你是记忆整理助手。请把下面这些旧记忆压缩合并成 $keepCount 条更精炼的记忆：'
                '合并重复与同类内容，保留关键事实（人物关系、约定、偏好、重要事件），'
                '每行一条，以"- "开头。只输出记忆条目本身，不要解释、不要续写。',
          },
          {'role': 'user', 'content': buf.toString()},
        ],
        temperature: 0.3,
      ))
          .trim();
      final lines = raw
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^[-*•\d\.\)\s]+'), '').trim())
          .where((l) => l.isNotEmpty && l != '无' && l.length > 1)
          .toList();
      if (lines.isEmpty) return null;
      return lines.length > keepCount ? lines.sublist(0, keepCount) : lines;
    } catch (_) {
      return null;
    }
  }

  Future<int> _memoryLimitFor(String? characterId) async {
    if (characterId == null) {
      return settings.memoryAutoPrune ? settings.memoryLimit : 0;
    }
    final c = await _db.getCharacter(characterId);
    if (c == null) return settings.memoryAutoPrune ? settings.memoryLimit : 0;
    final eff = resolveCharacter(settings, c);
    return eff.memoryAutoPrune ? eff.memoryLimit : 0;
  }

  Future<void> updateMemory(MemoryItem m) async {
    await _db.upsertMemory(m);
  }

  Future<void> togglePinMemory(String id, String? characterId) async {
    final mems = await _db.getMemories(characterId);
    for (final m in mems) {
      if (m.id == id) {
        await _db.upsertMemory(m.copyWith(pinned: !m.pinned));
        break;
      }
    }
  }

  Future<void> deleteMemory(String id) async {
    await _db.deleteMemory(id);
  }

  // ---------------- Sessions & Messages (单聊) ----------------
  Future<ChatSession> getOrCreateSession(String characterId) async {
    final sessions = await _db.getSessionsForCharacter(characterId);
    if (sessions.isNotEmpty) return sessions.first;
    final t = DateTime.now().millisecondsSinceEpoch;
    final s = ChatSession(id: _uid(), characterId: characterId, title: '', createdAt: t, updatedAt: t);
    await _db.upsertSession(s);
    return s;
  }

  Future<List<ChatSession>> sessionsFor(String characterId) => _db.getSessionsForCharacter(characterId);

  Future<List<ChatMessage>> messagesFor(String sessionId) => _db.getMessages(sessionId);

  // ---- 分页（窗口加载）----
  Future<int> countMessagesForSession(String sessionId) => _db.countMessagesForSession(sessionId);
  Future<int> countMessagesForGroup(String groupId) => _db.countMessagesForGroup(groupId);
  Future<int> countAssistantForSession(String sessionId) => _db.countAssistantForSession(sessionId);
  Future<int> countAssistantForGroup(String groupId) => _db.countAssistantForGroup(groupId);
  Future<List<ChatMessage>> messageSliceForSession(String sessionId, int offset, int limit) =>
      _db.messageSliceForSession(sessionId, offset, limit);
  Future<List<ChatMessage>> messageSliceForGroup(String groupId, int offset, int limit) =>
      _db.messageSliceForGroup(groupId, offset, limit);
  Future<int> indexOfMessageForSession(String sessionId, String messageId) =>
      _db.indexOfMessageForSession(sessionId, messageId);
  Future<int> indexOfMessageForGroup(String groupId, String messageId) =>
      _db.indexOfMessageForGroup(groupId, messageId);

  /// 关键词搜索（SQL 侧过滤，不把整段会话读进内存）
  Future<List<ChatMessage>> searchMessages({
    String? sessionId,
    String? groupId,
    required List<String> words,
  }) =>
      _db.searchMessages(sessionId: sessionId, groupId: groupId, words: words);

  Future<void> insertMessage(ChatMessage m) async {
    await _db.insertMessage(m);
    // 只更新受影响的那一个角色/群聊的活跃时间与最后一条消息。
    // 原来每次都 getCharacters + getGroups + 2×(角色数+群数) 次查询，
    // 群聊连续回复时每句都要跑一遍，角色一多主页就明显卡顿。
    final t = DateTime.now().millisecondsSinceEpoch;
    if (m.sessionId != null) {
      final sess = await _db.getSession(m.sessionId!);
      final cid = sess?.characterId;
      if (cid != null) {
        for (final c in characters) {
          if (c.id == cid) c.lastActivity = t;
        }
        lastCharMsg[cid] = m.content;
        lastCharTime[cid] = t;
      }
    }
    if (m.groupId != null) {
      for (final g in groups) {
        if (g.id == m.groupId) g.lastActivity = t;
      }
      lastGroupMsg[m.groupId!] = m.content;
      lastGroupTime[m.groupId!] = t;
    }
    notifyListeners();
  }

  Future<void> updateMessageContent(String id, String content) =>
      _db.updateMessageContent(id, content);

  Future<void> deleteMessage(String id) => _db.deleteMessage(id);

  Future<void> deleteSession(String id) => _db.deleteSession(id);

  /// 删除某会话/群聊从某时间点之后的所有消息，并同步删除其产生的长记忆。
  Future<void> deleteMessagesFrom(String? sessionId, String? groupId, int cutoff,
      {List<String> memoryOwners = const []}) async {
    await _db.deleteMessagesFrom(sessionId, groupId, cutoff);
    // 只删这一时间点之后产生的记忆（并且保留置顶记忆）。
    // 原实现是整段清空，会把置顶记忆和其它会话的记忆一起删掉。
    for (final owner in memoryOwners) {
      await _db.deleteMemoriesFor(owner, fromMs: cutoff);
    }
    characters = await _db.getCharacters();
    groups = await _db.getGroups();
    await _refreshLastMessages();
    notifyListeners();
  }

  // ---------------- Groups (群聊) ----------------
  Future<List<ChatGroup>> allGroups() => _db.getGroups();

  Future<ChatGroup?> getGroup(String id) => _db.getGroup(id);

  Future<void> addGroup(ChatGroup g) async {
    if (g.lastActivity == 0) g.lastActivity = DateTime.now().millisecondsSinceEpoch;
    await _db.upsertGroup(g);
    groups = await _db.getGroups();
    notifyListeners();
  }

  Future<void> updateGroup(ChatGroup g) async {
    // 编辑群聊时保留原有的最近活跃时间，避免卡片沉底
    final old = await _db.getGroup(g.id);
    final keep = (old?.lastActivity ?? 0) > g.lastActivity ? old!.lastActivity : g.lastActivity;
    await _db.upsertGroup(keep == g.lastActivity ? g : g.copyWith(lastActivity: keep));
    groups = await _db.getGroups();
    await _refreshLastMessages();
    notifyListeners();
  }

  Future<void> deleteGroup(String id) async {
    await _db.deleteGroup(id);
    groups = await _db.getGroups();
    notifyListeners();
  }

  Future<void> togglePinGroup(String id) async {
    final g = await _db.getGroup(id);
    if (g != null) {
      await _db.upsertGroup(g.copyWith(pinned: !g.pinned));
      groups = await _db.getGroups();
      notifyListeners();
    }
  }

  Future<List<ChatMessage>> groupMessages(String groupId) => _db.getGroupMessages(groupId);

  // ---------------- Export / Import ----------------
  Future<Map<String, dynamic>> exportData({bool includeProviders = true}) =>
      _db.exportAll(includeProviders: includeProviders);

  Future<bool> exportToFile(String name, {bool includeProviders = true}) async {
    final data = await _db.exportAll(includeProviders: includeProviders);
    return ExportService.exportToFile(data, name);
  }

  Future<bool> importFromFile() async {
    final data = await ExportService.importFromFile();
    if (data == null) return false;
    // 合并导入：不覆盖已存在的角色/接口/世界书等
    await _db.importAll(data);
    await init();
    return true;
  }

  String _uid() => DateTime.now().microsecondsSinceEpoch.toString();
}
