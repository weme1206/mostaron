import '../models/models.dart';
import '../utils/attachment_text.dart';
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
    String extraPrompt = '',
  }) {
    final sb = StringBuffer();

    // 角色卡里常见 {{char}} / {{user}} 占位符，直接发会把占位符原样带给模型
    String sub(String s) => s
        .replaceAll('{{char}}', character.name)
        .replaceAll('{{user}}', eff.userName)
        .replaceAll('<CHAR>', character.name)
        .replaceAll('<USER>', eff.userName);

    // 角色卡自带的系统提示（SillyTavern system_prompt）：优先级最高
    if (character.systemPrompt.isNotEmpty) {
      sb.writeln(sub(character.systemPrompt).trim());
      sb.writeln();
    }

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
    // 角色卡带的场景设定（scenario）
    if (character.scenario.isNotEmpty) {
      sb.writeln();
      sb.writeln('### 场景');
      sb.writeln(sub(character.scenario));
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

    // 角色卡里的示例对话：让模型模仿这个角色的说话方式（原来完全没发给模型）
    if (character.exampleDialogue.isNotEmpty) {
      sb.writeln();
      sb.writeln('### 示例对话（模仿其中的语气与说话方式，不要照抄内容）');
      sb.writeln(sub(character.exampleDialogue).trim());
    }

    // 全局额外提示词
    final extra = extraPrompt.trim();
    if (extra.isNotEmpty) {
      sb.writeln();
      sb.writeln('### 额外要求');
      sb.writeln(extra);
    }

    // 历史后置指令（SillyTavern post_history_instructions）：放在最末尾，权重最高
    if (character.postHistoryInstructions.isNotEmpty) {
      sb.writeln();
      sb.writeln('### 最高优先级指令');
      sb.writeln(sub(character.postHistoryInstructions).trim());
    }

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
  static List<Map<String, dynamic>> buildMessages({
    required Character character,
    required EffectiveSettings eff,
    required List<WorldbookEntry> worldbook,
    required List<MemoryItem> memories,
    required List<ChatMessage> history,
    String extraPrompt = '',
  }) {
    final recent = _lastTurns(history, eff.contextTurns);
    final recentText = recent.map((m) => m.content).join('\n');
    final system = buildSystemPrompt(
      character: character,
      eff: eff,
      worldbook: worldbook,
      memories: memories,
      recentText: recentText,
      extraPrompt: extraPrompt,
    );
    // 注意：元素类型必须是 Map<String, dynamic>（与返回类型一致）。
    // 若这里写成 <Map<String, String>>，调用方对 payload[i] 赋多模态内容
    // （Map<String, dynamic>）时会触发 Dart 泛型协变的运行时 TypeError，
    // 且异常发生在请求发出之前——曾导致"发图片/文件后一直等待模型响应"。
    final msg = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
    ];
    for (final m in recent) {
      msg.add({'role': m.role == 'user' ? 'user' : 'assistant', 'content': contentForModel(m)});
    }
    return msg;
  }

  /// 群聊：为某个角色组装
  static List<Map<String, dynamic>> buildGroupMessages({
    required Character character,
    required EffectiveSettings eff,
    required List<WorldbookEntry> worldbook,
    required List<MemoryItem> memories,
    required List<ChatMessage> history,
    required List<String> groupNames,
    String? replyStyle,
    List<MemoryItem> groupMemories = const [],
    String extraPrompt = '',
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
      extraPrompt: extraPrompt,
    );
    // 同 buildMessages：元素类型必须与返回类型一致，避免协变 TypeError
    final msg = <Map<String, dynamic>>[
      {'role': 'system', 'content': system},
    ];
    for (final m in recent) {
      msg.add({'role': m.role == 'user' ? 'user' : 'assistant', 'content': contentForModel(m)});
    }
    return msg;
  }

  /// 取最近 [turns] 条消息作为上下文（参考 chatbox：系统提示 + 限定历史 + 当前问题）。
  /// 加固点：
  /// 1) 过滤空消息；
  /// 2) 截断后若首条是 assistant，则从之后第一条 user 开始，保证首条 user 在前
  ///    （部分接口要求第一条非 system 消息必须是 user）；
  /// 3) 末尾必须保留当前消息（最后一条），避免被裁掉。
  static List<ChatMessage> _lastTurns(List<ChatMessage> history, int turns) {
    final list = history.where((m) => m.content.trim().isNotEmpty).toList();
    if (list.isEmpty) return const [];
    if (turns <= 0 || list.length <= turns) return list;
    final tail = list.sublist(list.length - turns);
    // 首条不能是 assistant（否则跳过它，直到遇到 user）
    var start = 0;
    while (start < tail.length - 1 && tail[start].role != 'user') {
      start++;
    }
    final out = tail.sublist(start);
    // 若全部都是 assistant（没有 user 可对齐），保留最后一条即可
    if (out.isEmpty) return [list.last];
    return out;
  }
}
