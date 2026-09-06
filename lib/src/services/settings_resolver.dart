import '../models/models.dart';

class EffectiveSettings {
  int contextTurns;
  bool memoryEnabled;
  bool memoryAutoPrune;
  int memoryLimit;
  bool realSense;
  int autoMemoryEvery;
  String userName;
  String userGender;
  String userRelation;
  String userBackground;

  EffectiveSettings({
    required this.contextTurns,
    required this.memoryEnabled,
    required this.memoryAutoPrune,
    required this.memoryLimit,
    required this.realSense,
    required this.autoMemoryEvery,
    required this.userName,
    required this.userGender,
    required this.userRelation,
    required this.userBackground,
  });
}

EffectiveSettings resolveSettings(AppSettings main) => EffectiveSettings(
      contextTurns: main.contextTurns,
      memoryEnabled: main.memoryEnabled,
      memoryAutoPrune: main.memoryAutoPrune,
      memoryLimit: main.memoryLimit,
      realSense: main.realSense,
      autoMemoryEvery: main.autoMemoryEvery,
      userName: main.personaName,
      userGender: main.personaGender,
      userRelation: main.personaRelation,
      userBackground: main.personaBackground,
    );

/// 合并角色独立设置与身份
EffectiveSettings resolveCharacter(AppSettings main, Character c) {
  final r = resolveSettings(main);
  final s = c.settings;
  if (s['context_turns'] is int) r.contextTurns = s['context_turns'] as int;
  if (s['memory_enabled'] is bool) r.memoryEnabled = s['memory_enabled'] as bool;
  if (s['memory_auto_prune'] is bool) r.memoryAutoPrune = s['memory_auto_prune'] as bool;
  if (s['memory_limit'] is int) r.memoryLimit = s['memory_limit'] as int;
  if (s['real_sense'] is bool) r.realSense = s['real_sense'] as bool;
  if (s['auto_memory_every'] is int) r.autoMemoryEvery = s['auto_memory_every'] as int;
  if (c.userName.isNotEmpty) r.userName = c.userName;
  if (c.userGender.isNotEmpty) r.userGender = c.userGender;
  if (c.userRelation.isNotEmpty) r.userRelation = c.userRelation;
  if (c.userBackground.isNotEmpty) r.userBackground = c.userBackground;
  return r;
}

/// 合并群聊身份
EffectiveSettings resolveGroup(AppSettings main, ChatGroup g) {
  final r = resolveSettings(main);
  if (g.userName.isNotEmpty) r.userName = g.userName;
  if (g.userGender.isNotEmpty) r.userGender = g.userGender;
  if (g.userRelation.isNotEmpty) r.userRelation = g.userRelation;
  if (g.userBackground.isNotEmpty) r.userBackground = g.userBackground;
  return r;
}
