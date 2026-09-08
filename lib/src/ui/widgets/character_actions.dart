import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../services/character_card_service.dart';
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
            subtitle: const Text('全新角色（不携带聊天与记忆）'),
            onTap: () => Navigator.pop(ctx, 'clone'),
          ),
          ListTile(
            leading: const Icon(Icons.copy_all),
            title: const Text('克隆角色（含聊天与记忆）'),
            onTap: () => Navigator.pop(ctx, 'cloneFull'),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('重置角色'),
            onTap: () => Navigator.pop(ctx, 'reset'),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导出角色卡'),
            onTap: () => Navigator.pop(ctx, 'export'),
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
    case 'cloneFull':
      await state.cloneCharacterFull(character, includeHistory: true);
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
    case 'export':
      if (context.mounted) await _exportCharacterCard(context, state, character);
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

/// 导出角色为 SillyTavern 角色卡文件（可选 JSON 或 PNG）。
Future<void> _exportCharacterCard(BuildContext context, AppState state, Character c) async {
  try {
    final gwb = await state.worldbookFor(null);
    final selected = gwb.where((e) => c.worldbookIds.contains(e.id)).toList();
    final jsonStr = CharacterCardService.toV2Json(c, worldbook: selected);
    // 判断头像是否为 PNG 文件，可导出为 PNG 角色卡
    Uint8List? avatarBytes;
    if (c.avatar.isNotEmpty && !c.avatar.startsWith('asset:') && File(c.avatar).existsSync()) {
      try {
        final b = await File(c.avatar).readAsBytes();
        if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50) avatarBytes = b;
      } catch (_) {}
    }
    final fmt = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('导出角色卡'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'json'),
            child: const Text('导出为 JSON 角色卡'),
          ),
          if (avatarBytes != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, 'png'),
              child: const Text('导出为 PNG 角色卡（含头像）'),
            ),
          SimpleDialogOption(onPressed: () => Navigator.pop(d), child: const Text('取消')),
        ],
      ),
    );
    if (fmt == null || !context.mounted) return;
    if (fmt == 'png' && avatarBytes != null) {
      final png = CharacterCardService.toPng(avatarBytes, jsonStr);
      if (png == null) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PNG 导出失败')));
        return;
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出 PNG 角色卡',
        fileName: '${c.name}.png',
        type: FileType.any,
        bytes: png,
      );
      if (path != null && path.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PNG 角色卡已导出')));
      }
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出 JSON 角色卡',
        fileName: '${c.name}.json',
        type: FileType.any,
        bytes: utf8.encode(jsonStr),
      );
      if (path != null && path.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON 角色卡已导出')));
      }
    }
  } catch (_) {}
}
