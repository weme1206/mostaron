import 'package:flutter/foundation.dart';
import '../data/db.dart';
import '../models/models.dart';
import '../services/export_service.dart';
import '../services/settings_resolver.dart';

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
    for (final c in characters) {
      lastCharMsg[c.id] = await _db.lastMessageForCharacter(c.id);
    }
    lastGroupMsg.clear();
    for (final g in groups) {
      lastGroupMsg[g.id] = await _db.lastMessageForGroup(g.id);
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

  Future<void> updateCharacter(Character c) async {
    await _db.upsertCharacter(c);
    characters = await _db.getCharacters();
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

  /// 克隆角色（新 ID，名字加"副本"）
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
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.upsertCharacter(nc);
    characters = await _db.getCharacters();
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
    await refreshWorldbook(characterId);
  }

  // ---------------- Memory ----------------
  Future<List<MemoryItem>> memoriesFor(String? characterId) =>
      _db.getMemories(characterId);

  Future<void> addMemory(MemoryItem m) async {
    await _db.upsertMemory(m);
    final limit = await _memoryLimitFor(m.characterId);
    if (limit > 0) {
      await _db.pruneMemories(m.characterId, limit);
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

  Future<void> insertMessage(ChatMessage m) async {
    await _db.insertMessage(m);
    // 刷新角色/群聊的最近活跃时间，使主页排序即时更新
    characters = await _db.getCharacters();
    groups = await _db.getGroups();
    await _refreshLastMessages();
    notifyListeners();
  }

  Future<void> updateMessageContent(String id, String content) =>
      _db.updateMessageContent(id, content);

  Future<void> deleteMessage(String id) => _db.deleteMessage(id);

  Future<void> deleteSession(String id) => _db.deleteSession(id);

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
    await _db.upsertGroup(g);
    groups = await _db.getGroups();
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
  Future<Map<String, dynamic>> exportData() => _db.exportAll();

  Future<bool> exportToFile(String name) async {
    final data = await _db.exportAll();
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
