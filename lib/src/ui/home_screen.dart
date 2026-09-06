import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import 'character_editor_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'usage_help_screen.dart';
import 'group_create_screen.dart';
import 'group_chat_screen.dart';
import 'model_settings_screen.dart';
import 'widgets/avatars.dart';
import 'widgets/character_actions.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _listMode = true;

  // 合并后的条目
  List<_HomeItem> _items(AppState state) {
    final items = <_HomeItem>[
      for (final g in state.groups) _HomeItem.group(g),
      for (final c in state.characters) _HomeItem.character(c),
    ];
    items.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.lastActivity.compareTo(a.lastActivity);
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = _items(state);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmExit();
      },
      child: Scaffold(
        body: _homeBody(state, items),
      ),
    );
  }

  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('mostaron：'),
        content: const Text('你确定要退出应用吗？qwq'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) {
      SystemNavigator.pop();
    }
  }

  Widget _homeBody(AppState state, List<_HomeItem> items) {
    final content = items.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_outline, size: 72, color: Colors.blueGrey),
                const SizedBox(height: 12),
                const Text('还没有内容，点右上角 + 添加', style: TextStyle(color: Colors.blueGrey)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CharacterEditorScreen())),
                  child: const Text('添加第一个角色'),
                ),
              ],
            ),
          )
        : _listMode ? _listView(context, state, items) : _gridView(context, state, items);

    final column = SafeArea(
      bottom: false,
      child: Column(
        children: [
          _header(state),
          Expanded(child: content),
        ],
      ),
    );

    final bg = state.settings.chatBackground;
    if (bg.isNotEmpty && File(bg).existsSync()) {
      return Stack(
        children: [
          Positioned.fill(child: Image.file(File(bg), fit: BoxFit.cover)),
          column,
        ],
      );
    }
    return column;
  }

  /// 主页自定义头部（最上、在内容列里）
  Widget _header(AppState state) {
    return SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Center(
            child: Text('mostaron', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildUserAvatar(context, state.settings, 30),
                    const SizedBox(width: 4),
                    Text(state.settings.personaName,
                        style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(_listMode ? Icons.grid_view : Icons.view_list, size: 22),
                  onPressed: () => setState(() => _listMode = !_listMode),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add),
                  onSelected: (v) async {
                    if (v == 'char') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CharacterEditorScreen()));
                    } else if (v == 'group') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupCreateScreen()));
                    } else if (v == 'models') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ModelSettingsScreen()));
                    } else if (v == 'settings') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                    } else if (v == 'help') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const UsageHelpScreen()));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'char', child: ListTile(leading: Icon(Icons.person_add_alt_1), title: Text('添加角色'))),
                    PopupMenuItem(value: 'group', child: ListTile(leading: Icon(Icons.groups), title: Text('创建群聊'))),
                    PopupMenuItem(value: 'models', child: ListTile(leading: Icon(Icons.model_training), title: Text('模型设置'))),
                    PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings), title: Text('设置'))),
                    PopupMenuItem(value: 'help', child: ListTile(leading: Icon(Icons.help_outline), title: Text('使用说明'))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listView(BuildContext context, AppState state, List<_HomeItem> items) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        final bg = state.settings.chatBackground;
        final hasBg = bg.isNotEmpty && File(bg).existsSync();
        if (it.group != null) {
          return _GroupTile(group: it.group!, hasBg: hasBg, lastMsg: state.lastGroupMsg[it.group!.id] ?? '');
        }
        return _CharacterTile(character: it.character!, hasBg: hasBg, lastMsg: state.lastCharMsg[it.character!.id] ?? '');
      },
    );
  }

  Widget _gridView(BuildContext context, AppState state, List<_HomeItem> items) {
    final bg = state.settings.chatBackground;
    final hasBg = bg.isNotEmpty && File(bg).existsSync();
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, childAspectRatio: 0.86, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        if (it.group != null) {
          return _GroupCardGrid(group: it.group!, hasBg: hasBg, lastMsg: state.lastGroupMsg[it.group!.id] ?? '');
        }
        return _CharacterCardGrid(character: it.character!, hasBg: hasBg, lastMsg: state.lastCharMsg[it.character!.id] ?? '');
      },
    );
  }
}

class _HomeItem {
  final Character? character;
  final ChatGroup? group;
  _HomeItem.character(this.character) : group = null;
  _HomeItem.group(this.group) : character = null;
  bool get pinned => character?.pinned ?? group?.pinned ?? false;
  int get createdAt => character?.createdAt ?? group?.createdAt ?? 0;
  int get lastActivity =>
      character?.lastActivity ?? group?.lastActivity ?? createdAt;
}

// ---------------- List tiles ----------------
class _CharacterTile extends StatelessWidget {
  final Character character;
  final bool hasBg;
  final String lastMsg;
  const _CharacterTile({required this.character, this.hasBg = false, this.lastMsg = ''});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gradient = LinearGradient(colors: [
      scheme.primaryContainer.withValues(alpha: 0.5),
      scheme.tertiaryContainer.withValues(alpha: 0.4),
    ]);
    return Container(
      decoration: BoxDecoration(
        gradient: hasBg ? null : gradient,
        color: hasBg ? Colors.transparent : null,
        border: hasBg ? null : Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: ListTile(
        leading: buildCharacterAvatar(context, character, 44),
        tileColor: character.pinned
            ? scheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        title: Text(character.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(lastMsg.isEmpty ? '暂无消息' : lastMsg,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(characterId: character.id))),
        onLongPress: () => showCharacterMenu(context, character),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final ChatGroup group;
  final bool hasBg;
  final String lastMsg;
  const _GroupTile({required this.group, this.hasBg = false, this.lastMsg = ''});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gradient = LinearGradient(colors: [
      scheme.primaryContainer.withValues(alpha: 0.5),
      scheme.tertiaryContainer.withValues(alpha: 0.4),
    ]);
    return Container(
      decoration: BoxDecoration(
        gradient: hasBg ? null : gradient,
        color: hasBg ? Colors.transparent : null,
        border: hasBg ? null : Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: ListTile(
        leading: buildGroupAvatar(context, group, 44),
        tileColor: group.pinned
            ? scheme.primaryContainer.withValues(alpha: 0.3)
            : null,
        title: Text(group.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(lastMsg.isEmpty ? '暂无消息' : lastMsg, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id))),
        onLongPress: () => _groupMenu(context, group),
      ),
    );
  }

  Future<void> _groupMenu(BuildContext context, ChatGroup group) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(group.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(group.pinned ? '取消置顶' : '置顶'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑群聊'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除群聊'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final state = context.read<AppState>();
    switch (action) {
      case 'pin':
        await state.togglePinGroup(group.id);
        break;
      case 'edit':
        Navigator.push(context, MaterialPageRoute(builder: (_) => GroupCreateScreen(group: group)));
        break;
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('删除群聊'),
            content: Text('确定删除群聊「${group.name}」？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除')),
            ],
          ),
        );
        if (ok == true && context.mounted) await state.deleteGroup(group.id);
        break;
    }
  }

  static String _modeLabel(String mode) {
    switch (mode) {
      case 'all':
        return '全员回复';
      case 'designated':
        return '指定发言';
      default:
        return '自然聊天';
    }
  }
}

// ---------------- Grid cards ----------------
class _CharacterCardGrid extends StatelessWidget {
  final Character character;
  final bool hasBg;
  final String lastMsg;
  const _CharacterCardGrid({required this.character, this.hasBg = false, this.lastMsg = ''});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: hasBg ? Colors.transparent : null,
      elevation: hasBg ? 0 : null,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(characterId: character.id))),
        onLongPress: () => showCharacterMenu(context, character),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: character.pinned
                            ? [scheme.primaryContainer.withValues(alpha: 0.75), scheme.tertiaryContainer.withValues(alpha: 0.55)]
                            : [scheme.primaryContainer.withValues(alpha: 0.55), scheme.tertiaryContainer.withValues(alpha: 0.35)],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: buildCharacterAvatar(context, character, 64),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Text(character.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(lastMsg.isEmpty ? '暂无消息' : lastMsg,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCardGrid extends StatelessWidget {
  final ChatGroup group;
  final bool hasBg;
  final String lastMsg;
  const _GroupCardGrid({required this.group, this.hasBg = false, this.lastMsg = ''});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: hasBg ? Colors.transparent : null,
      elevation: hasBg ? 0 : null,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: group.id))),
        onLongPress: () => _GroupTile(group: group)._groupMenu(context, group),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: group.pinned
                            ? [scheme.primaryContainer.withValues(alpha: 0.7), scheme.tertiaryContainer.withValues(alpha: 0.5)]
                            : [scheme.primaryContainer.withValues(alpha: 0.55), scheme.tertiaryContainer.withValues(alpha: 0.35)],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: buildGroupAvatar(context, group, 64),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Text(group.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(lastMsg.isEmpty ? '暂无消息' : lastMsg,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
