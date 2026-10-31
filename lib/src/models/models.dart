import 'dart:convert';

// ---------------- Provider (BYOK) ----------------
class ProviderConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final List<String> models; // 该接口可用模型列表
  bool isDefault;

  ProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.models = const [],
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'base_url': baseUrl,
        'api_key': apiKey,
        'model': model,
        'models': jsonEncode(models),
        'is_default': isDefault ? 1 : 0,
      };

  factory ProviderConfig.fromMap(Map<String, dynamic> m) => ProviderConfig(
        id: m['id'] as String,
        name: m['name'] as String,
        baseUrl: m['base_url'] as String? ?? '',
        apiKey: m['api_key'] as String? ?? '',
        model: m['model'] as String? ?? '',
        models: _decodeList(m['models']),
        isDefault: (m['is_default'] as int? ?? 0) == 1,
      );

  ProviderConfig copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    List<String>? models,
    bool? isDefault,
  }) =>
      ProviderConfig(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        models: models ?? this.models,
        isDefault: isDefault ?? this.isDefault,
      );
}

// ---------------- Character ----------------
class Character {
  final String id;
  final String name;
  String avatar;
  String persona;
  String personality;
  String tone;
  String background;
  String greeting;
  String chatBackground;
  String? providerId;
  String? model;
  String replyStyle; // default / short
  List<String> worldbookIds;
  // 每角色独立设置覆盖（空=用主设置）
  Map<String, dynamic> settings;
  // 每角色独立身份（空=用主设置）
  String userName;
  String userGender;
  String userRelation;
  String userBackground;
  bool pinned;
  int lastActivity;
  final int createdAt;

  // ---- SillyTavern 角色卡扩展字段 ----
  String scenario; // 场景
  String exampleDialogue; // 示例对话 mes_example
  String creatorNotes; // 作者注释
  String systemPrompt; // 系统提示
  String postHistoryInstructions; // 历史后置指令
  List<String> alternateGreetings; // 备选开场白
  List<String> tags; // 标签
  String creator;
  String characterVersion;
  Map<String, dynamic> extensions; // 扩展字段（保留原样）

  Character({
    required this.id,
    required this.name,
    this.avatar = '',
    this.persona = '',
    this.personality = '',
    this.tone = '',
    this.background = '',
    this.greeting = '',
    this.chatBackground = '',
    this.providerId,
    this.model,
    this.replyStyle = 'default',
    this.worldbookIds = const [],
    this.settings = const {},
    this.userName = '',
    this.userGender = '',
    this.userRelation = '',
    this.userBackground = '',
    this.pinned = false,
    this.lastActivity = 0,
    this.createdAt = 0,
    this.scenario = '',
    this.exampleDialogue = '',
    this.creatorNotes = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.alternateGreetings = const [],
    this.tags = const [],
    this.creator = '',
    this.characterVersion = '',
    this.extensions = const {},
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'persona': persona,
        'personality': personality,
        'tone': tone,
        'background': background,
        'greeting': greeting,
        'chat_background': chatBackground,
        'provider_id': providerId,
        'model': model,
        'reply_style': replyStyle,
        'worldbook_ids': jsonEncode(worldbookIds),
        'settings_json': jsonEncode(settings),
        'user_name': userName,
        'user_gender': userGender,
        'user_relation': userRelation,
        'user_background': userBackground,
        'pinned': pinned ? 1 : 0,
        'last_activity': lastActivity,
        'created_at': createdAt,
        'scenario': scenario,
        'example_dialogue': exampleDialogue,
        'creator_notes': creatorNotes,
        'system_prompt': systemPrompt,
        'post_history_instructions': postHistoryInstructions,
        'alt_greetings': jsonEncode(alternateGreetings),
        'tags': jsonEncode(tags),
        'creator': creator,
        'character_version': characterVersion,
        'extensions': jsonEncode(extensions),
      };

  factory Character.fromMap(Map<String, dynamic> m) => Character(
        id: m['id'] as String,
        name: m['name'] as String,
        avatar: m['avatar'] as String? ?? '',
        persona: m['persona'] as String? ?? '',
        personality: m['personality'] as String? ?? '',
        tone: m['tone'] as String? ?? '',
        background: m['background'] as String? ?? '',
        greeting: m['greeting'] as String? ?? '',
        chatBackground: m['chat_background'] as String? ?? '',
        providerId: m['provider_id'] as String?,
        model: m['model'] as String?,
        replyStyle: m['reply_style'] as String? ?? 'default',
        worldbookIds: _decodeList(m['worldbook_ids']),
        settings: _decodeMap(m['settings_json']),
        userName: m['user_name'] as String? ?? '',
        userGender: m['user_gender'] as String? ?? '',
        userRelation: m['user_relation'] as String? ?? '',
        userBackground: m['user_background'] as String? ?? '',
        pinned: (m['pinned'] as int? ?? 0) == 1,
        lastActivity: m['last_activity'] as int? ?? 0,
        createdAt: m['created_at'] as int? ?? 0,
        scenario: m['scenario'] as String? ?? '',
        exampleDialogue: m['example_dialogue'] as String? ?? '',
        creatorNotes: m['creator_notes'] as String? ?? '',
        systemPrompt: m['system_prompt'] as String? ?? '',
        postHistoryInstructions: m['post_history_instructions'] as String? ?? '',
        alternateGreetings: _decodeList(m['alt_greetings']),
        tags: _decodeList(m['tags']),
        creator: m['creator'] as String? ?? '',
        characterVersion: m['character_version'] as String? ?? '',
        extensions: _decodeMap(m['extensions']),
      );

  Character copyWith({
    String? id,
    String? name,
    String? avatar,
    String? persona,
    String? personality,
    String? tone,
    String? background,
    String? greeting,
    String? chatBackground,
    Object? providerId = _sentinel,
    Object? model = _sentinel,
    String? replyStyle,
    List<String>? worldbookIds,
    Map<String, dynamic>? settings,
    String? userName,
    String? userGender,
    String? userRelation,
    String? userBackground,
    bool? pinned,
    int? lastActivity,
    String? scenario,
    String? exampleDialogue,
    String? creatorNotes,
    String? systemPrompt,
    String? postHistoryInstructions,
    List<String>? alternateGreetings,
    List<String>? tags,
    String? creator,
    String? characterVersion,
    Map<String, dynamic>? extensions,
  }) =>
      Character(
        id: id ?? this.id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        persona: persona ?? this.persona,
        personality: personality ?? this.personality,
        tone: tone ?? this.tone,
        background: background ?? this.background,
        greeting: greeting ?? this.greeting,
        chatBackground: chatBackground ?? this.chatBackground,
        providerId: providerId == _sentinel ? this.providerId : providerId as String?,
        model: model == _sentinel ? this.model : model as String?,
        replyStyle: replyStyle ?? this.replyStyle,
        worldbookIds: worldbookIds ?? this.worldbookIds,
        settings: settings ?? this.settings,
        userName: userName ?? this.userName,
        userGender: userGender ?? this.userGender,
        userRelation: userRelation ?? this.userRelation,
        userBackground: userBackground ?? this.userBackground,
        pinned: pinned ?? this.pinned,
        lastActivity: lastActivity ?? this.lastActivity,
        scenario: scenario ?? this.scenario,
        exampleDialogue: exampleDialogue ?? this.exampleDialogue,
        creatorNotes: creatorNotes ?? this.creatorNotes,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        postHistoryInstructions: postHistoryInstructions ?? this.postHistoryInstructions,
        alternateGreetings: alternateGreetings ?? this.alternateGreetings,
        tags: tags ?? this.tags,
        creator: creator ?? this.creator,
        characterVersion: characterVersion ?? this.characterVersion,
        extensions: extensions ?? this.extensions,
        createdAt: createdAt,
      );
}

const Object _sentinel = Object();

List<String> _decodeList(dynamic v) {
  if (v == null) return [];
  if (v is String) {
    try {
      final d = jsonDecode(v);
      if (d is List) return d.map((e) => e.toString()).toList();
    } catch (_) {}
    return [];
  }
  if (v is List) return v.map((e) => e.toString()).toList();
  return [];
}

Map<String, dynamic> _decodeMap(dynamic v) {
  if (v == null) return {};
  if (v is String) {
    try {
      final d = jsonDecode(v);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return {};
  }
  if (v is Map) return Map<String, dynamic>.from(v);
  return {};
}

// ---------------- Attachment ----------------
/// 消息附件：图片（带宽高，便于预留占位避免布局漂移）或普通文件。
class Attachment {
  final String type; // image / file
  final String path;
  final int width;
  final int height;
  final String name;

  const Attachment({
    required this.type,
    required this.path,
    this.width = 0,
    this.height = 0,
    this.name = '',
  });

  bool get isImage => type == 'image';

  Map<String, dynamic> toMap() => {
        'type': type,
        'path': path,
        if (width > 0) 'w': width,
        if (height > 0) 'h': height,
        if (name.isNotEmpty) 'name': name,
      };

  factory Attachment.fromMap(Map<String, dynamic> m) => Attachment(
        type: m['type'] as String? ?? 'file',
        path: m['path'] as String? ?? '',
        width: (m['w'] as num?)?.toInt() ?? 0,
        height: (m['h'] as num?)?.toInt() ?? 0,
        name: m['name'] as String? ?? '',
      );
}

List<Attachment> decodeAttachments(dynamic v) {
  dynamic raw = v;
  if (raw is String) {
    if (raw.trim().isEmpty) return const [];
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }
  if (raw is List) {
    final out = <Attachment>[];
    for (final e in raw) {
      if (e is Map) out.add(Attachment.fromMap(Map<String, dynamic>.from(e)));
    }
    return out;
  }
  return const [];
}

// ---------------- Chat ----------------
class ChatSession {
  final String id;
  final String characterId;
  final String title;
  final int createdAt;
  final int updatedAt;

  ChatSession({
    required this.id,
    required this.characterId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'character_id': characterId,
        'title': title,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ChatSession.fromMap(Map<String, dynamic> m) => ChatSession(
        id: m['id'] as String,
        characterId: m['character_id'] as String,
        title: m['title'] as String? ?? '',
        createdAt: m['created_at'] as int? ?? 0,
        updatedAt: m['updated_at'] as int? ?? 0,
      );
}

class ChatMessage {
  final String id;
  final String? sessionId;
  final String? groupId;
  final String role;
  final String content;
  final String reasoning;
  final String? senderCharacterId;
  final int createdAt;
  final List<Attachment> attachments;

  ChatMessage({
    required this.id,
    this.sessionId,
    this.groupId,
    required this.role,
    required this.content,
    this.reasoning = '',
    this.senderCharacterId,
    required this.createdAt,
    this.attachments = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'group_id': groupId,
        'role': role,
        'content': content,
        'reasoning': reasoning,
        'sender_id': senderCharacterId,
        'created_at': createdAt,
        'meta': attachments.isEmpty
            ? null
            : jsonEncode(attachments.map((a) => a.toMap()).toList()),
      };

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
        id: m['id'] as String,
        sessionId: m['session_id'] as String?,
        groupId: m['group_id'] as String?,
        role: m['role'] as String,
        content: m['content'] as String? ?? '',
        reasoning: m['reasoning'] as String? ?? '',
        senderCharacterId: m['sender_id'] as String?,
        createdAt: m['created_at'] as int? ?? 0,
        attachments: decodeAttachments(m['meta']),
      );

  ChatMessage copyWith({String? content, String? reasoning, List<Attachment>? attachments}) => ChatMessage(
        id: id,
        sessionId: sessionId,
        groupId: groupId,
        role: role,
        content: content ?? this.content,
        reasoning: reasoning ?? this.reasoning,
        senderCharacterId: senderCharacterId,
        createdAt: createdAt,
        attachments: attachments ?? this.attachments,
      );
}

// ---------------- Group chat ----------------
class ChatGroup {
  final String id;
  final String name;
  String avatar;
  String background;
  List<String> memberIds;
  String replyMode;
  int maxReplies;
  // 群聊独立身份
  String userName;
  String userGender;
  String userRelation;
  String userBackground;
  bool pinned;
  String? providerId;
  String? model;
  String replyStyle;
  int autoMemoryEvery;
  int lastActivity;
  List<String> worldbookIds;
  String memoryMode; // whole / separate / synced
  final int createdAt;
  int updatedAt;

  ChatGroup({
    required this.id,
    required this.name,
    this.avatar = '',
    this.background = '',
    this.memberIds = const [],
    this.replyMode = 'natural',
    this.maxReplies = 1,
    this.userName = '',
    this.userGender = '',
    this.userRelation = '',
    this.userBackground = '',
    this.pinned = false,
    this.providerId,
    this.model,
    this.replyStyle = 'default',
    this.autoMemoryEvery = 0,
    this.lastActivity = 0,
    this.worldbookIds = const [],
    this.memoryMode = 'whole',
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'background': background,
        'member_ids': jsonEncode(memberIds),
        'reply_mode': replyMode,
        'max_replies': maxReplies,
        'user_name': userName,
        'user_gender': userGender,
        'user_relation': userRelation,
        'user_background': userBackground,
        'pinned': pinned ? 1 : 0,
        'provider_id': providerId,
        'model': model,
        'reply_style': replyStyle,
        'auto_memory_every': autoMemoryEvery,
        'last_activity': lastActivity,
        'worldbook_ids': jsonEncode(worldbookIds),
        'memory_mode': memoryMode,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ChatGroup.fromMap(Map<String, dynamic> m) => ChatGroup(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        avatar: m['avatar'] as String? ?? '',
        background: m['background'] as String? ?? '',
        memberIds: _decodeList(m['member_ids']),
        replyMode: m['reply_mode'] as String? ?? 'natural',
        maxReplies: m['max_replies'] as int? ?? 1,
        userName: m['user_name'] as String? ?? '',
        userGender: m['user_gender'] as String? ?? '',
        userRelation: m['user_relation'] as String? ?? '',
        userBackground: m['user_background'] as String? ?? '',
        pinned: (m['pinned'] as int? ?? 0) == 1,
        providerId: m['provider_id'] as String?,
        model: m['model'] as String?,
        replyStyle: m['reply_style'] as String? ?? 'default',
        autoMemoryEvery: m['auto_memory_every'] as int? ?? 0,
        lastActivity: m['last_activity'] as int? ?? 0,
        worldbookIds: _decodeList(m['worldbook_ids']),
        memoryMode: m['memory_mode'] as String? ?? 'whole',
        createdAt: m['created_at'] as int? ?? 0,
        updatedAt: m['updated_at'] as int? ?? 0,
      );

  ChatGroup copyWith({
    String? id,
    String? name,
    String? avatar,
    String? background,
    List<String>? memberIds,
    String? replyMode,
    int? maxReplies,
    String? userName,
    String? userGender,
    String? userRelation,
    String? userBackground,
    bool? pinned,
    Object? providerId = _sentinel,
    Object? model = _sentinel,
    String? replyStyle,
    int? autoMemoryEvery,
    int? lastActivity,
    List<String>? worldbookIds,
    String? memoryMode,
  }) =>
      ChatGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        background: background ?? this.background,
        memberIds: memberIds ?? this.memberIds,
        replyMode: replyMode ?? this.replyMode,
        maxReplies: maxReplies ?? this.maxReplies,
        userName: userName ?? this.userName,
        userGender: userGender ?? this.userGender,
        userRelation: userRelation ?? this.userRelation,
        userBackground: userBackground ?? this.userBackground,
        pinned: pinned ?? this.pinned,
        providerId: providerId == _sentinel ? this.providerId : providerId as String?,
        model: model == _sentinel ? this.model : model as String?,
        replyStyle: replyStyle ?? this.replyStyle,
        autoMemoryEvery: autoMemoryEvery ?? this.autoMemoryEvery,
        lastActivity: lastActivity ?? this.lastActivity,
        worldbookIds: worldbookIds ?? this.worldbookIds,
        memoryMode: memoryMode ?? this.memoryMode,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

// ---------------- Memory ----------------
class MemoryItem {
  final String id;
  final String? characterId;
  final String content;
  bool pinned;
  final int createdAt;
  /// normal=普通记忆；summary=压缩后的摘要记忆
  final String kind;
  /// 摘要记忆的来源记忆 id（用于追溯/避免重复压缩）
  final List<String> summaryOf;

  MemoryItem({
    required this.id,
    this.characterId,
    required this.content,
    this.pinned = false,
    this.createdAt = 0,
    this.kind = 'normal',
    this.summaryOf = const [],
  });

  bool get isSummary => kind == 'summary';

  Map<String, dynamic> toMap() => {
        'id': id,
        'character_id': characterId,
        'content': content,
        'pinned': pinned ? 1 : 0,
        'created_at': createdAt,
        'kind': kind,
        'summary_of': summaryOf.isEmpty ? null : jsonEncode(summaryOf),
      };

  factory MemoryItem.fromMap(Map<String, dynamic> m) => MemoryItem(
        id: m['id'] as String,
        characterId: m['character_id'] as String?,
        content: m['content'] as String? ?? '',
        pinned: (m['pinned'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as int? ?? 0,
        kind: m['kind'] as String? ?? 'normal',
        summaryOf: _decodeList(m['summary_of']),
      );

  MemoryItem copyWith({String? content, bool? pinned, String? kind, List<String>? summaryOf}) => MemoryItem(
        id: id,
        characterId: characterId,
        content: content ?? this.content,
        pinned: pinned ?? this.pinned,
        createdAt: createdAt,
        kind: kind ?? this.kind,
        summaryOf: summaryOf ?? this.summaryOf,
      );
}

// ---------------- Worldbook ----------------
class WorldbookEntry {
  final String id;
  final String? characterId;
  final String name;
  List<String> keywords;
  String content;
  bool enabled;
  final int createdAt;

  WorldbookEntry({
    required this.id,
    this.characterId,
    required this.name,
    this.keywords = const [],
    this.content = '',
    this.enabled = true,
    this.createdAt = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'character_id': characterId,
        'name': name,
        'keywords': jsonEncode(keywords),
        'content': content,
        'enabled': enabled ? 1 : 0,
        'created_at': createdAt,
      };

  factory WorldbookEntry.fromMap(Map<String, dynamic> m) => WorldbookEntry(
        id: m['id'] as String,
        characterId: m['character_id'] as String?,
        name: m['name'] as String? ?? '',
        keywords: _decodeList(m['keywords']),
        content: m['content'] as String? ?? '',
        enabled: (m['enabled'] as int? ?? 1) == 1,
        createdAt: m['created_at'] as int? ?? 0,
      );

  WorldbookEntry copyWith({
    String? name,
    List<String>? keywords,
    String? content,
    bool? enabled,
  }) =>
      WorldbookEntry(
        id: id,
        characterId: characterId,
        name: name ?? this.name,
        keywords: keywords ?? this.keywords,
        content: content ?? this.content,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt,
      );
}

// ---------------- Settings ----------------
class AppSettings {
  String defaultProviderId;
  String personaName;
  String personaGender;
  String personaRelation;
  String personaBackground; // 身份背景
  int contextTurns;
  bool memoryEnabled;
  String themeMode;
  String systemPromptExtra;

  String userAvatar;
  bool showCharAvatar;
  bool showUserAvatar;

  bool realSense;
  bool memoryAutoPrune;
  int memoryLimit;
  int autoMemoryEvery; // 每多少条对话自动生成一次记忆
  /// 压缩数量比：记忆达到上限时，压缩最老记忆的比例（0.1~1.0）
  double memoryCompressCountRatio;
  /// 压缩比例：被压缩的那批记忆保留多少成文本（0.1~1.0，1.0 表示全部删除）
  double memoryCompressKeepRatio;

  /// 是否在消息里显示思考过程（默认显示）
  bool showThinking;

  String themeAccent;
  String chatBackground;
  bool nightAutoDark;
  int nightStartHour;
  int nightEndHour;
  String bubbleSelfColor; // 我的气泡颜色 hex
  String bubbleCharColor; // 角色气泡颜色 hex
  double bubbleOpacity; // 气泡透明度 0.4~1.0
  double fontSize; // 全局字体大小倍率

  AppSettings({
    this.defaultProviderId = '',
    this.personaName = '你',
    this.personaGender = '男',
    this.personaRelation = '',
    this.personaBackground = '',
    this.contextTurns = 20,
    this.memoryEnabled = true,
    this.themeMode = 'system',
    this.systemPromptExtra = '',
    this.userAvatar = '',
    this.showCharAvatar = true,
    this.showUserAvatar = true,
    this.realSense = true,
    this.memoryAutoPrune = true,
    this.memoryLimit = 100,
    this.autoMemoryEvery = 6,
    this.memoryCompressCountRatio = 0.2,
    this.memoryCompressKeepRatio = 0.5,
    this.showThinking = true,
    this.themeAccent = 'blue',
    this.chatBackground = '',
    this.nightAutoDark = false,
    this.nightStartHour = 22,
    this.nightEndHour = 6,
    this.bubbleSelfColor = '',
    this.bubbleCharColor = '',
    this.bubbleOpacity = 1.0,
    this.fontSize = 1.0,
  });

  Map<String, dynamic> toMap() => {
        'default_provider_id': defaultProviderId,
        'persona_name': personaName,
        'persona_gender': personaGender,
        'persona_relation': personaRelation,
        'persona_background': personaBackground,
        'context_turns': contextTurns,
        'memory_enabled': memoryEnabled ? 1 : 0,
        'theme_mode': themeMode,
        'system_prompt_extra': systemPromptExtra,
        'user_avatar': userAvatar,
        'show_char_avatar': showCharAvatar ? 1 : 0,
        'show_user_avatar': showUserAvatar ? 1 : 0,
        'real_sense': realSense ? 1 : 0,
        'memory_auto_prune': memoryAutoPrune ? 1 : 0,
        'memory_limit': memoryLimit,
        'auto_memory_every': autoMemoryEvery,
        'memory_compress_count_ratio': memoryCompressCountRatio,
        'memory_compress_keep_ratio': memoryCompressKeepRatio,
        'show_thinking': showThinking ? 1 : 0,
        'theme_accent': themeAccent,
        'chat_background': chatBackground,
        'night_auto_dark': nightAutoDark ? 1 : 0,
        'night_start_hour': nightStartHour,
        'night_end_hour': nightEndHour,
        'bubble_self_color': bubbleSelfColor,
        'bubble_char_color': bubbleCharColor,
        'bubble_opacity': bubbleOpacity,
        'font_size': fontSize,
      };

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        defaultProviderId: m['default_provider_id'] as String? ?? '',
        personaName: m['persona_name'] as String? ?? '你',
        personaGender: m['persona_gender'] as String? ?? '男',
        personaRelation: m['persona_relation'] as String? ?? '',
        personaBackground: m['persona_background'] as String? ?? '',
        contextTurns: m['context_turns'] as int? ?? 20,
        memoryEnabled: (m['memory_enabled'] as int? ?? 1) == 1,
        themeMode: m['theme_mode'] as String? ?? 'system',
        systemPromptExtra: m['system_prompt_extra'] as String? ?? '',
        userAvatar: m['user_avatar'] as String? ?? '',
        showCharAvatar: (m['show_char_avatar'] as int? ?? 1) == 1,
        showUserAvatar: (m['show_user_avatar'] as int? ?? 1) == 1,
        realSense: (m['real_sense'] as int? ?? 1) == 1,
        memoryAutoPrune: (m['memory_auto_prune'] as int? ?? 1) == 1,
        memoryLimit: m['memory_limit'] as int? ?? 100,
        autoMemoryEvery: m['auto_memory_every'] as int? ?? 6,
        memoryCompressCountRatio:
            (m['memory_compress_count_ratio'] as num? ?? 0.2).toDouble(),
        memoryCompressKeepRatio:
            (m['memory_compress_keep_ratio'] as num? ?? 0.5).toDouble(),
        // 旧字段 output_thinking 是无效开关（以前只存不用），不再读取；
        // 新字段默认开启，保证"发图后看不到思考"这类问题不会因迁移再犯。
        showThinking: (m['show_thinking'] as int? ?? 1) == 1,
        themeAccent: m['theme_accent'] as String? ?? 'blue',
        chatBackground: m['chat_background'] as String? ?? '',
        nightAutoDark: (m['night_auto_dark'] as int? ?? 0) == 1,
        nightStartHour: m['night_start_hour'] as int? ?? 22,
        nightEndHour: m['night_end_hour'] as int? ?? 6,
        bubbleSelfColor: m['bubble_self_color'] as String? ?? '',
        bubbleCharColor: m['bubble_char_color'] as String? ?? '',
        bubbleOpacity: (m['bubble_opacity'] as num? ?? 1.0).toDouble(),
        fontSize: (m['font_size'] as num? ?? 1.0).toDouble(),
      );

  AppSettings copyWith({
    String? defaultProviderId,
    String? personaName,
    String? personaGender,
    String? personaRelation,
    String? personaBackground,
    int? contextTurns,
    bool? memoryEnabled,
    String? themeMode,
    String? systemPromptExtra,
    String? userAvatar,
    bool? showCharAvatar,
    bool? showUserAvatar,
    bool? realSense,
    bool? memoryAutoPrune,
    int? memoryLimit,
    int? autoMemoryEvery,
    double? memoryCompressCountRatio,
    double? memoryCompressKeepRatio,
    bool? showThinking,
    String? themeAccent,
    String? chatBackground,
    bool? nightAutoDark,
    int? nightStartHour,
    int? nightEndHour,
    String? bubbleSelfColor,
    String? bubbleCharColor,
    double? bubbleOpacity,
    double? fontSize,
  }) =>
      AppSettings(
        defaultProviderId: defaultProviderId ?? this.defaultProviderId,
        personaName: personaName ?? this.personaName,
        personaGender: personaGender ?? this.personaGender,
        personaRelation: personaRelation ?? this.personaRelation,
        personaBackground: personaBackground ?? this.personaBackground,
        contextTurns: contextTurns ?? this.contextTurns,
        memoryEnabled: memoryEnabled ?? this.memoryEnabled,
        themeMode: themeMode ?? this.themeMode,
        systemPromptExtra: systemPromptExtra ?? this.systemPromptExtra,
        userAvatar: userAvatar ?? this.userAvatar,
        showCharAvatar: showCharAvatar ?? this.showCharAvatar,
        showUserAvatar: showUserAvatar ?? this.showUserAvatar,
        realSense: realSense ?? this.realSense,
        memoryAutoPrune: memoryAutoPrune ?? this.memoryAutoPrune,
        memoryLimit: memoryLimit ?? this.memoryLimit,
        autoMemoryEvery: autoMemoryEvery ?? this.autoMemoryEvery,
        memoryCompressCountRatio:
            memoryCompressCountRatio ?? this.memoryCompressCountRatio,
        memoryCompressKeepRatio:
            memoryCompressKeepRatio ?? this.memoryCompressKeepRatio,
        showThinking: showThinking ?? this.showThinking,
        themeAccent: themeAccent ?? this.themeAccent,
        chatBackground: chatBackground ?? this.chatBackground,
        nightAutoDark: nightAutoDark ?? this.nightAutoDark,
        nightStartHour: nightStartHour ?? this.nightStartHour,
        nightEndHour: nightEndHour ?? this.nightEndHour,
        bubbleSelfColor: bubbleSelfColor ?? this.bubbleSelfColor,
        bubbleCharColor: bubbleCharColor ?? this.bubbleCharColor,
        bubbleOpacity: bubbleOpacity ?? this.bubbleOpacity,
        fontSize: fontSize ?? this.fontSize,
      );
}
