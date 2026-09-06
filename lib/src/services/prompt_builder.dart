import '../models/models.dart';
import 'settings_resolver.dart';

class PromptBuilder {
  /// 组装系统提示词
  static String buildSystemPrompt({
    required Character character,
    required EffectiveSettings eff,
    required List<WorldbookEntry> worldbook,
    required List<MemoryItem> memories,
    required String recentText,
    bool isGroup = false,
    List<String> groupNames = const [],
    String? replyStyle,
  }) {
    final sb = StringBuffer();

    sb.writeln('### 角色设定');
    sb.writeln('你是「${character.name}」，请始终保持这个角色身份，用第一人称扮演。');
    if (character.persona.isNotEmpty) sb.writeln('人设：${character.persona}');
    if (character.personality.isNotEmpty) sb.writeln('性格：${character.personality}');
    if (character.tone.isNotEmpty) sb.writeln('语气：${character.tone}');
    if (character.background.isNotEmpty) {
      sb.writeln();
      sb.writeln('### 背景故事');
      sb.writeln(character.background);
    }

    if (isGroup && groupNames.isNotEmpty) {
      sb.writeln();
      sb.writeln('### 群聊场景');
      sb.writeln('你和 ${groupNames.join('、')} 在同一个群里。你只会说「${character.name}」该说的话，'
          '可以看见其他角色和用户的发言，但不要模仿或替别人说话。');
    }

    // 感应现实：告诉角色当前日期时间
    if (eff.realSense) {
      final now = DateTime.now();
      final d = '${now.year}-${_p2(now.month)}-${_p2(now.day)} ${_p2(now.hour)}:${_p2(now.minute)}';
      sb.writeln();
      sb.writeln('### 现实时间');
      sb.writeln('现在是 $d。');
    }

    final triggered = triggerWorldbook(worldbook, recentText);
    if (triggered.isNotEmpty) {
      sb.writeln();
      sb.writeln('### 世界观设定（仅在相关时自然融入扮演，不要直白复述）');
      for (final e in triggered) {
        if (e.content.isNotEmpty) {
          sb.writeln('- ${e.content.replaceAll('\n', ' ')}');
        }
      }
    }

    sb.writeln();
    sb.writeln('### 玩家');
    sb.writeln(
        '正在与你对话的是「${eff.userName}」（${eff.userGender.isEmpty ? '未知' : eff.userGender}），与你的关系是「${eff.userRelation.isEmpty ? '朋友' : eff.userRelation}」。');
    if (eff.userBackground.isNotEmpty) {
      sb.writeln('玩家的身份背景：${eff.userBackground}');
    }

    final agents = agentsMd(memories); // 置顶/关键规则
    if (agents.isNotEmpty) {
      sb.writeln();
      sb.writeln('### 长期记忆（AGENTS.md，必须遵守并保持一致）');
      sb.writeln(agents);
    }
    final recent = recentMemories(memories);
    if (recent.isNotEmpty) {
      sb.writeln();
      sb.writeln('### 相关记忆（自然融入，不要直白复述）');
      sb.writeln(recent);
    }

    sb.writeln();
    sb.writeln('### 回复要求');
    final style = replyStyle ?? character.replyStyle;
    if (style == 'short') {
      sb.writeln('请用一句简短、口语化的话回复，贴近日常对话，不要长篇大论。');
    } else {
      sb.writeln('回复保持自然、有细节，但不要一次性写太长，可分多次推进。');
    }
    sb.writeln('用圆括号（或半角括号）包住你的动作，例如（轻轻笑了一下）。台词直接说出来。'
        '不要使用星号包裹动作。');

    return sb.toString();
  }

  static String _p2(int v) => v.toString().padLeft(2, '0');

  static List<WorldbookEntry> triggerWorldbook(List<WorldbookEntry> all, String text) {
    final lower = text.toLowerCase();
    return all
        .where((e) =>
            e.enabled &&
            e.keywords.isNotEmpty &&
            e.keywords.any((k) => k.isNotEmpty && lower.contains(k.toLowerCase())))
        .toList();
  }

  static String agentsMd(List<MemoryItem> memories) {
    final pinned = memories.where((m) => m.pinned && m.content.trim().isNotEmpty).toList();
    if (pinned.isEmpty) return '';
    final sb = StringBuffer();
    for (final m in pinned) {
      sb.writeln('- ${m.content.trim()}');
    }
    return sb.toString();
  }

  /// 最近若干条记忆（非置顶也纳入上下文）
  static String recentMemories(List<MemoryItem> memories) {
    final list = memories.where((m) => m.content.trim().isNotEmpty).toList();
    if (list.isEmpty) return '';
    final recent = list.length > 8 ? list.sublist(list.length - 8) : list;
    final sb = StringBuffer();
    for (final m in recent) {
      sb.writeln('- ${m.content.trim()}');
    }
    return sb.toString();
  }

  /// 单聊
  static List<Map<String, String>> buildMessages({
    required Character character,
    required EffectiveSettings eff,
    required List<WorldbookEntry> worldbook,
    required List<MemoryItem> memories,
    required List<ChatMessage> history,
  }) {
    final recent = _lastTurns(history, eff.contextTurns);
    final recentText = recent.map((m) => m.content).join('\n');
    final system = buildSystemPrompt(
      character: character,
      eff: eff,
      worldbook: worldbook,
      memories: memories,
      recentText: recentText,
    );
    final msg = <Map<String, String>>[
      {'role': 'system', 'content': system},
    ];
    for (final m in recent) {
      msg.add({'role': m.role == 'user' ? 'user' : 'assistant', 'content': m.content});
    }
    return msg;
  }

  /// 群聊：为某个角色组装
  static List<Map<String, String>> buildGroupMessages({
    required Character character,
    required EffectiveSettings eff,
    required List<WorldbookEntry> worldbook,
    required List<MemoryItem> memories,
    required List<ChatMessage> history,
    required List<String> groupNames,
    String? replyStyle,
    List<MemoryItem> groupMemories = const [],
  }) {
    final recent = _lastTurns(history, eff.contextTurns);
    final recentText = recent.map((m) => m.content).join('\n');
    final system = buildSystemPrompt(
      character: character,
      eff: eff,
      worldbook: worldbook,
      memories: [...memories, ...groupMemories],
      recentText: recentText,
      isGroup: true,
      groupNames: groupNames,
      replyStyle: replyStyle,
    );
    final msg = <Map<String, String>>[
      {'role': 'system', 'content': system},
    ];
    for (final m in recent) {
      msg.add({'role': m.role == 'user' ? 'user' : 'assistant', 'content': m.content});
    }
    return msg;
  }

  static List<ChatMessage> _lastTurns(List<ChatMessage> history, int turns) {
    if (turns <= 0) return history;
    if (history.length <= turns) return history;
    return history.sublist(history.length - turns);
  }
}
