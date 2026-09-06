import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import 'widgets/preset_avatar.dart';
import 'worldbook_screen.dart';
import 'worldbook_picker.dart';
import 'avatar_crop_screen.dart';
import '../utils/file_utils.dart';

class CharacterEditorScreen extends StatefulWidget {
  final Character? character;
  const CharacterEditorScreen({super.key, this.character});

  @override
  State<CharacterEditorScreen> createState() => _CharacterEditorScreenState();
}

class _CharacterEditorScreenState extends State<CharacterEditorScreen> {
  late TextEditingController _name;
  late TextEditingController _persona;
  late TextEditingController _personality;
  late TextEditingController _tone;
  late TextEditingController _background;
  late TextEditingController _greeting;
  late TextEditingController _chatBg;
  late TextEditingController _genText;
  late TextEditingController _model;
  late TextEditingController _uname;
  late TextEditingController _ugender;
  late TextEditingController _urelation;
  late TextEditingController _ubg;
  // 独立角色设置
  int _charCtx = 20;
  int _charMemLimit = 500;
  int _charAutoEvery = 6;
  bool _charMemAutoPrune = true;
  bool _charMemEnabled = true;
  bool _charRealSense = true;
  String _avatar = '';
  String _providerId = '';
  String _replyStyle = 'default';
  List<String> _worldbookIds = [];
  bool _busy = false;

  // 用于撤销 AI 生成
  Map<String, String?> _beforeGen = {};
  bool _canUndo = false;
  late final String _charId;

  @override
  void initState() {
    super.initState();
    _charId = widget.character?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final c = widget.character;
    _name = TextEditingController(text: c?.name ?? '');
    _persona = TextEditingController(text: c?.persona ?? '');
    _personality = TextEditingController(text: c?.personality ?? '');
    _tone = TextEditingController(text: c?.tone ?? '');
    _background = TextEditingController(text: c?.background ?? '');
    _greeting = TextEditingController(text: c?.greeting ?? '');
    _chatBg = TextEditingController(text: c?.chatBackground ?? '');
    _genText = TextEditingController();
    _model = TextEditingController(text: c?.model ?? '');
    _replyStyle = c?.replyStyle ?? 'default';
    _avatar = c?.avatar ?? '';
    _providerId = c?.providerId ?? '';
    _worldbookIds = List.of(c?.worldbookIds ?? []);
    final s = context.read<AppState>().settings;
    _uname = TextEditingController(text: c?.userName.isNotEmpty == true ? c!.userName : s.personaName);
    _ugender = TextEditingController(text: c?.userGender.isNotEmpty == true ? c!.userGender : s.personaGender);
    _urelation = TextEditingController(text: c?.userRelation.isNotEmpty == true ? c!.userRelation : s.personaRelation);
    _ubg = TextEditingController(text: c?.userBackground.isNotEmpty == true ? c!.userBackground : s.personaBackground);
    // 独立角色设置（默认用主设置）
    final cs = c?.settings ?? {};
    _charCtx = cs['context_turns'] is int ? cs['context_turns'] as int : s.contextTurns;
    _charMemLimit = cs['memory_limit'] is int ? cs['memory_limit'] as int : s.memoryLimit;
    _charAutoEvery = cs['auto_memory_every'] is int ? cs['auto_memory_every'] as int : s.autoMemoryEvery;
    _charMemAutoPrune = cs['memory_auto_prune'] is bool ? cs['memory_auto_prune'] as bool : s.memoryAutoPrune;
    _charMemEnabled = cs['memory_enabled'] is bool ? cs['memory_enabled'] as bool : s.memoryEnabled;
    _charRealSense = cs['real_sense'] is bool ? cs['real_sense'] as bool : s.realSense;
  }

  @override
  void dispose() {
    for (final t in [_name, _persona, _personality, _tone, _background, _greeting, _chatBg, _genText, _model, _uname, _ugender, _urelation, _ubg]) {
      t.dispose();
    }
    super.dispose();
  }

  ProviderConfig? _resolveProvider(AppState state) =>
      state.getProviderById(_providerId.isEmpty ? null : _providerId);

  Future<void> _generateCharacter(AppState state) async {
    final desc = _genText.text.trim();
    if (desc.isEmpty) {
      _toast('请先填写角色描述');
      return;
    }
    final p = _resolveProvider(state);
    if (p == null) {
      _toast('请先在设置中添加一个可用接口');
      return;
    }
    // 记录生成前状态用于撤销
    _beforeGen = {
      'name': _name.text,
      'persona': _persona.text,
      'personality': _personality.text,
      'tone': _tone.text,
      'background': _background.text,
      'greeting': _greeting.text,
    };
    setState(() => _busy = true);
    try {
      final prompt =
          '你是角色卡生成器。根据描述生成一个角色，严格返回 JSON（不要多余文字），字段：name, persona, personality, tone, background, greeting(开场白,一句话)。\n描述：$desc\n仅返回 JSON。';
      final reply = await ApiClient().completeChat(
        baseUrl: p.baseUrl,
        apiKey: p.apiKey,
        model: _model.text.isNotEmpty ? _model.text : p.model,
        messages: [
          {'role': 'system', 'content': '你是角色卡生成器，只输出 JSON。'},
          {'role': 'user', 'content': prompt},
        ],
      );
      final obj = jsonDecode(_stripJson(reply)) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _name.text = obj['name']?.toString() ?? _name.text;
          _persona.text = obj['persona']?.toString() ?? '';
          _personality.text = obj['personality']?.toString() ?? '';
          _tone.text = obj['tone']?.toString() ?? '';
          _background.text = obj['background']?.toString() ?? '';
          _greeting.text = obj['greeting']?.toString() ?? '';
          _canUndo = true;
        });
      }
    } catch (e) {
      _toast('生成失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _undoGenerate() {
    setState(() {
      _name.text = _beforeGen['name'] ?? '';
      _persona.text = _beforeGen['persona'] ?? '';
      _personality.text = _beforeGen['personality'] ?? '';
      _tone.text = _beforeGen['tone'] ?? '';
      _background.text = _beforeGen['background'] ?? '';
      _greeting.text = _beforeGen['greeting'] ?? '';
      _canUndo = false;
    });
  }

  String _stripJson(String s) {
    var t = s.trim();
    if (t.startsWith('```')) {
      final i = t.indexOf('\n');
      if (i >= 0) t = t.substring(i + 1);
      if (t.endsWith('```')) t = t.substring(0, t.length - 3);
      t = t.trim();
    }
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start >= 0 && end > start) t = t.substring(start, end + 1);
    return t;
  }

  Future<void> _pickAvatar() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    if (r != null && r.files.isNotEmpty) {
      final path = r.files.first.path ?? '';
      if (path.isEmpty) return;
      final cropped = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => AvatarCropScreen(imagePath: path)),
      );
      if (cropped != null && mounted) setState(() => _avatar = cropped);
    }
  }

  Future<void> _save(AppState state) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('请填写角色名');
      return;
    }
    final id = _charId;
    final c = Character(
      id: id,
      name: name,
      avatar: _avatar,
      persona: _persona.text.trim(),
      personality: _personality.text.trim(),
      tone: _tone.text.trim(),
      background: _background.text.trim(),
      greeting: _greeting.text.trim(),
      chatBackground: _chatBg.text.trim(),
      providerId: _providerId.isEmpty ? null : _providerId,
      model: _model.text.trim().isEmpty ? null : _model.text.trim(),
      replyStyle: _replyStyle,
      worldbookIds: _worldbookIds,
      settings: {
        'context_turns': _charCtx,
        'memory_limit': _charMemLimit,
        'auto_memory_every': _charAutoEvery,
        'memory_auto_prune': _charMemAutoPrune,
        'memory_enabled': _charMemEnabled,
        'real_sense': _charRealSense,
      },
      userName: _uname.text.trim(),
      userGender: _ugender.text.trim(),
      userRelation: _urelation.text.trim(),
      userBackground: _ubg.text.trim(),
      createdAt: widget.character?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    if (widget.character == null) {
      await state.addCharacter(c);
    } else {
      await state.updateCharacter(c);
    }
    // 不再改主设置；身份/设置独立存储在角色上
    if (mounted) Navigator.pop(context);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = _resolveProvider(state);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.character == null ? '创建角色' : '编辑角色'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: () => _save(state))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _avatarSection(state),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: '角色名', prefixIcon: Icon(Icons.badge))),
          const SizedBox(height: 12),
          // 回复模式
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('回复模式', style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Radio<String>(
                        value: 'default', groupValue: _replyStyle,
                        onChanged: (v) => setState(() => _replyStyle = v!),
                      ),
                      const Text('默认'),
                      const SizedBox(width: 12),
                      Radio<String>(
                        value: 'short', groupValue: _replyStyle,
                        onChanged: (v) => setState(() => _replyStyle = v!),
                      ),
                      const Text('简短对话'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _generateCard(state),
          const SizedBox(height: 12),
          _field(_persona, '人设', maxLines: 3),
          _field(_personality, '性格', maxLines: 2),
          _field(_tone, '语气', maxLines: 2),
          _field(_background, '背景故事', maxLines: 4),
          _field(_greeting, '开场白（进入时显示）', maxLines: 2),
          // 自定义聊天背景（上传图片）
          Card(
            child: ListTile(
              leading: _chatBg.text.isEmpty
                  ? const Icon(Icons.image)
                  : CircleAvatar(backgroundImage: FileImage(File(_chatBg.text))),
              title: const Text('自定义聊天背景'),
              subtitle: Text(_chatBg.text.isEmpty ? '未设置' : '已设置'),
              trailing: _chatBg.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '恢复默认',
                      onPressed: () => setState(() => _chatBg.text = ''),
                    )
                  : null,
              onTap: () async {
                final r = await FilePicker.platform.pickFiles(type: FileType.image);
                if (r != null && r.files.isNotEmpty) {
                  setState(() => _chatBg.text = r.files.first.path ?? '');
                }
              },
            ),
          ),
          const SizedBox(height: 12),

          // 你的身份
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('你的身份（默认沿用主设置）', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _field(_uname, '你的名字', maxLines: 1, pad: false),
                  _field(_ugender, '你的性别', maxLines: 1, pad: false),
                  _field(_urelation, '与角色的关系', maxLines: 1, pad: false),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextField(
                      controller: _ubg,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: '你的身份背景'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 模型/Key
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('独立模型 / Key', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _providerId,
                    decoration: const InputDecoration(labelText: '接口 (Provider)'),
                    items: [
                      const DropdownMenuItem<String>(value: '', child: Text('使用默认接口')),
                      for (final pr in state.providers)
                        DropdownMenuItem<String>(value: pr.id, child: Text(pr.name)),
                    ],
                    onChanged: (v) => setState(() => _providerId = v ?? ''),
                  ),
                  const SizedBox(height: 8),
                  if (p != null && p.models.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: p.models.contains(_model.text) ? _model.text : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '模型名', prefixIcon: Icon(Icons.model_training)),
                      items: [
                        for (final m in p.models)
                          DropdownMenuItem<String>(value: m, child: Text(m, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _model.text = v ?? ''),
                    )
                  else
                    TextField(
                      controller: _model,
                      decoration: const InputDecoration(labelText: '模型名（留空用接口默认）', hintText: 'gpt-4o / deepseek-chat'),
                    ),
                  if (p != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('将使用: ${p.baseUrl} · ${_model.text.isEmpty ? p.model : _model.text}',
                          style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 世界书（选择全局世界书里启用哪些，可在主设置里管理全局条目）
          Card(
            child: ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('选择世界书'),
              subtitle: Text(
                _worldbookIds.isEmpty ? '未启用（默认全部不启用）' : '已启用 ${_worldbookIds.length} 条',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final r = await showWorldbookPicker(context, initial: _worldbookIds);
                if (r == null || !mounted) return;
                if (r.manage) {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const WorldbookScreen()));
                  return;
                }
                setState(() => _worldbookIds = r.ids);
              },
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorldbookScreen())),
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('管理全局世界书'),
          ),
          const SizedBox(height: 8),
          // 独立角色设置
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.tune),
              title: const Text('角色设置', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('独立设置，默认沿用主设置'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                Row(
                  children: [
                    const Text('上下文轮数'),
                    Expanded(
                      child: Slider(
                        value: _charCtx.toDouble().clamp(4, 60),
                        min: 4,
                        max: 60,
                        divisions: 56,
                        onChanged: (v) => setState(() => _charCtx = v.round()),
                      ),
                    ),
                    Text('$_charCtx'),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('记忆注入 (AGENTS.md)'),
                  value: _charMemEnabled,
                  onChanged: (v) => setState(() => _charMemEnabled = v),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('感应现实(知道现实日期时间)'),
                  value: _charRealSense,
                  onChanged: (v) => setState(() => _charRealSense = v),
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('记忆达上限自动删除'),
                  value: _charMemAutoPrune,
                  onChanged: (v) => setState(() => _charMemAutoPrune = v),
                ),
                if (_charMemAutoPrune)
                  Row(
                    children: [
                      const Text('记忆上限'),
                      Expanded(
                        child: Slider(
                          value: _charMemLimit.toDouble().clamp(50, 2000),
                          min: 50,
                          max: 2000,
                          divisions: 39,
                          onChanged: (v) => setState(() => _charMemLimit = v.round()),
                        ),
                      ),
                      Text('$_charMemLimit'),
                    ],
                  ),
                if (_charMemAutoPrune)
                  Row(
                    children: [
                      const Text('自动记忆间隔'),
                      Expanded(
                        child: Slider(
                          value: _charAutoEvery.toDouble().clamp(2, 20),
                          min: 2,
                          max: 20,
                          divisions: 18,
                          onChanged: (v) => setState(() => _charAutoEvery = v.round()),
                        ),
                      ),
                      Text('$_charAutoEvery条'),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _avatarSection(AppState state) {
    return Center(
      child: Column(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: _avatar.isEmpty
                ? CircleAvatar(child: Text(_name.text.isEmpty ? '?' : _name.text.substring(0, 1)))
                : _avatar.startsWith('asset:')
                    ? PresetAvatar(id: _avatar.substring(6), size: 84)
                    : CircleAvatar(backgroundImage: FileImage(File(_avatar))),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final id in ['a', 'b', 'c', 'd', 'e', 'f'])
                GestureDetector(
                    onTap: () => setState(() => _avatar = 'asset:$id'),
                    child: PresetAvatar(id: id, size: 34)),
              TextButton.icon(
                  icon: const Icon(Icons.image, size: 16), label: const Text('选择图片'), onPressed: _pickAvatar),
            ],
          ),
        ],
      ),
    );
  }

  Widget _generateCard(AppState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('用文字快速生成角色（需已配置接口）', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _genText,
              maxLines: 2,
              decoration: const InputDecoration(hintText: '例：一个活泼调皮的猫娘，喜欢捉弄主人，傲娇', prefixIcon: Icon(Icons.auto_awesome)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_canUndo)
                  TextButton.icon(
                      icon: const Icon(Icons.undo), label: const Text('撤销生成'), onPressed: _undoGenerate),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_busy ? '生成中...' : '生成角色'),
                  onPressed: _busy ? null : () => _generateCharacter(state),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 1, bool pad = true}) {
    return Padding(
      padding: EdgeInsets.only(bottom: pad ? 12 : 6),
      child: TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(labelText: label)),
    );
  }
}
