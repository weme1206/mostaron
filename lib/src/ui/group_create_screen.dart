import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'widgets/avatars.dart';
import 'widgets/preset_avatar.dart';
import 'worldbook_screen.dart';
import 'worldbook_picker.dart';
import 'avatar_crop_screen.dart';
import '../utils/file_utils.dart';

class GroupCreateScreen extends StatefulWidget {
  final ChatGroup? group;
  final List<String>? initialMemberIds;
  const GroupCreateScreen({super.key, this.group, this.initialMemberIds});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  late TextEditingController _name;
  late TextEditingController _uname;
  late TextEditingController _ugender;
  late TextEditingController _ubg;
  List<String> _memberIds = [];
  String _avatar = '';
  String _background = '';
  String _replyMode = 'natural';
  String _replyStyle = 'default';
  int _maxReplies = 1;
  int _autoEvery = 6;
  List<String> _worldbookIds = [];
  late final String _gid;

  @override
  void initState() {
    super.initState();
    _gid = widget.group?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    _autoEvery = widget.group != null && widget.group!.autoMemoryEvery > 0
        ? widget.group!.autoMemoryEvery
        : context.read<AppState>().settings.autoMemoryEvery;
    final g = widget.group;
    final s = context.read<AppState>().settings;
    _name = TextEditingController(text: g?.name ?? '');
    _uname = TextEditingController(text: g?.userName.isNotEmpty == true ? g!.userName : s.personaName);
    _ugender = TextEditingController(text: g?.userGender.isNotEmpty == true ? g!.userGender : s.personaGender);
    _ubg = TextEditingController(text: g?.userBackground.isNotEmpty == true ? g!.userBackground : s.personaBackground);
    _memberIds = List.of(g?.memberIds ?? widget.initialMemberIds ?? []);
    _avatar = g?.avatar ?? '';
    _background = g?.background ?? '';
    _replyMode = g?.replyMode ?? 'natural';
    _maxReplies = g?.maxReplies ?? 1;
    _replyStyle = g?.replyStyle ?? 'default';
    _worldbookIds = List.of(g?.worldbookIds ?? []);
  }

  @override
  void dispose() {
    _name.dispose();
    _uname.dispose();
    _ugender.dispose();
    _ubg.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    if (r != null && r.files.isNotEmpty) {
      final path = r.files.first.path ?? '';
      if (path.isEmpty) return;
      final cropped = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => AvatarCropScreen(imagePath: path)));
      if (cropped != null && mounted) setState(() => _avatar = cropped);
    }
  }

  Future<void> _pickBackground() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    if (r != null && r.files.isNotEmpty) {
      setState(() => _background = r.files.first.path ?? '');
    }
  }

  /// 添加成员（拉人）
  Future<void> _addMember(AppState state) async {
    final available = state.characters.where((c) => !_memberIds.contains(c.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可添加的角色')));
      return;
    }
    final picked = await showModalBottomSheet<Character>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('选择要添加的角色', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final c in available)
              ListTile(
                leading: buildCharacterAvatar(context, c, 36),
                title: Text(c.name),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _memberIds.add(picked.id));
    }
  }

  /// 移除成员（踢人），需确认
  Future<void> _removeMember(Character c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定将「${c.name}」移出群聊吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('移除')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _memberIds.remove(c.id));
    }
  }

  Future<void> _save(AppState state) async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写群名')));
      return;
    }
    if (_memberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少选择两个角色')));
      return;
    }
    final g = ChatGroup(
      id: widget.group?.id ?? _gid,
      name: _name.text.trim(),
      avatar: _avatar,
      background: _background,
      memberIds: _memberIds,
      replyMode: _replyMode,
      maxReplies: _maxReplies,
      replyStyle: _replyStyle,
      autoMemoryEvery: _autoEvery,
      worldbookIds: _worldbookIds,
      lastActivity: widget.group?.lastActivity ?? 0,
      userName: _uname.text.trim(),
      userGender: _ugender.text.trim(),
      userBackground: _ubg.text.trim(),
      createdAt: widget.group?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      pinned: widget.group?.pinned ?? false,
    );
    if (widget.group == null) {
      await state.addGroup(g);
    } else {
      await state.updateGroup(g);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group == null ? '创建群聊' : '编辑群聊'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: () => _save(state))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: _avatar.isEmpty
                      ? CircleAvatar(child: Text(_name.text.isEmpty ? '群' : _name.text.substring(0, 1)))
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
                        icon: const Icon(Icons.image, size: 16),
                        label: const Text('选择图片'),
                        onPressed: _pickAvatar),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: '群名', prefixIcon: Icon(Icons.groups))),
          const SizedBox(height: 12),
          // 成员管理（添加/删除）
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('群成员（${_memberIds.length}）', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('添加成员'),
                        onPressed: () => _addMember(state),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_memberIds.isEmpty)
                    const Text('还没有成员，点击"添加成员"添加', style: TextStyle(color: Colors.blueGrey))
                  else
                    for (final mid in _memberIds)
                      for (final c in state.characters.where((c) => c.id == mid))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: buildCharacterAvatar(context, c, 36),
                          title: Text(c.name),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            tooltip: '移除成员',
                            onPressed: () => _removeMember(c),
                          ),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 回复模式
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('回复模式', style: TextStyle(fontWeight: FontWeight.bold)),
                  RadioListTile<String>(
                    dense: true,
                    title: const Text('全员回复'),
                    subtitle: const Text('所有人都回复一条，用户提到的角色优先'),
                    value: 'all',
                    groupValue: _replyMode,
                    onChanged: (v) => setState(() => _replyMode = v!),
                  ),
                  RadioListTile<String>(
                    dense: true,
                    title: const Text('指定发言'),
                    subtitle: const Text('用户发消息后点某个角色它才回复'),
                    value: 'designated',
                    groupValue: _replyMode,
                    onChanged: (v) => setState(() => _replyMode = v!),
                  ),
                  RadioListTile<String>(
                    dense: true,
                    title: const Text('自然聊天'),
                    subtitle: const Text('角色自动判断，至少一人回复'),
                    value: 'natural',
                    groupValue: _replyMode,
                    onChanged: (v) => setState(() => _replyMode = v!),
                  ),
                  if (_replyMode == 'natural')
                    Row(
                      children: [
                        const Text('每角色最多回复'),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: _maxReplies,
                          items: [
                            for (final n in [1, 2, 3])
                              DropdownMenuItem(value: n, child: Text('$n 条')),
                          ],
                          onChanged: (v) {
                            if (v == 2 || v == 3) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('设置过高容易让角色互相刷屏，建议 1 条')));
                            }
                            setState(() => _maxReplies = v ?? 1);
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 回复风格
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('回复风格', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('自动记忆间隔'),
                      Expanded(
                        child: Slider(
                          value: _autoEvery.toDouble().clamp(2, 20),
                          min: 2, max: 20, divisions: 18,
                          onChanged: (v) => setState(() => _autoEvery = v.round()),
                        ),
                      ),
                      Text('$_autoEvery条', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
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
                  TextField(controller: _uname, decoration: const InputDecoration(labelText: '你的名字')),
                  const SizedBox(height: 12),
                  TextField(controller: _ugender, decoration: const InputDecoration(labelText: '你的性别')),
                  const SizedBox(height: 12),
                  TextField(controller: _ubg, maxLines: 2, decoration: const InputDecoration(labelText: '你的身份背景')),
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
          const SizedBox(height: 12),
          // 背景
          Card(
            child: ListTile(
              leading: _background.isEmpty
                  ? const Icon(Icons.image)
                  : CircleAvatar(backgroundImage: FileImage(File(_background))),
              title: const Text('群聊背景'),
              subtitle: Text(_background.isEmpty ? '未设置' : '已设置'),
              trailing: _background.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '恢复默认',
                      onPressed: () => setState(() => _background = ''),
                    )
                  : null,
              onTap: _pickBackground,
            ),
          ),
        ],
      ),
    );
  }
}
