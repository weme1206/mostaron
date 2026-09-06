import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../character_editor_screen.dart';
import '../group_create_screen.dart';

/// 角色卡片长按菜单：编辑 / 建群 / 克隆 / 重置 / 删除
Future<void> showCharacterMenu(BuildContext context, Character character) async {
  final result = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('编辑角色'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: Icon(character.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(character.pinned ? '取消置顶' : '置顶'),
            onTap: () => Navigator.pop(ctx, 'pin'),
          ),
          ListTile(
            leading: const Icon(Icons.group_add),
            title: const Text('创建群聊'),
            onTap: () => Navigator.pop(ctx, 'group'),
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('克隆角色'),
            onTap: () => Navigator.pop(ctx, 'clone'),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('重置角色'),
            onTap: () => Navigator.pop(ctx, 'reset'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('删除角色'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  final state = context.read<AppState>();
  switch (result) {
    case 'edit':
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => CharacterEditorScreen(character: character)));
      break;
    case 'pin':
      await state.togglePinCharacter(character.id);
      break;
    case 'group':
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => GroupCreateScreen(initialMemberIds: [character.id])));
      break;
    case 'clone':
      await state.cloneCharacter(character);
      break;
    case 'reset':
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('重置角色'),
          content: Text('将清空「${character.name}」的人设/背景等设定（保留名字和头像），确定？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('重置')),
          ],
        ),
      );
      if (ok == true && context.mounted) await state.resetCharacter(character);
      break;
    case 'delete':
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('删除角色'),
          content: Text('确定删除「${character.name}」及所有聊天记录吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除')),
          ],
        ),
      );
      if (ok == true && context.mounted) await state.deleteCharacter(character.id);
      break;
  }
}
