import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../services/character_card_service.dart';
import '../../utils/image_utils.dart';
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

/// 导出角色为 SillyTavern 角色卡文件（JSON，或 PNG 图片卡）。
/// PNG 卡：头像自动转 PNG；头像为空/不支持转换则提示不支持；也可另选图片导出。
Future<void> _exportCharacterCard(BuildContext context, AppState state, Character c) async {
  try {
    final gwb = await state.worldbookFor(null);
    final selected = gwb.where((e) => c.worldbookIds.contains(e.id)).toList();
    final fmt = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('导出角色卡'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'json'),
            child: const Text('导出为 JSON 角色卡'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'pngAvatar'),
            child: const Text('导出为 PNG 角色卡（用头像）'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'pngPick'),
            child: const Text('导出为 PNG 角色卡（选择图片）'),
          ),
          SimpleDialogOption(onPressed: () => Navigator.pop(d), child: const Text('取消')),
        ],
      ),
    );
    if (fmt == null || !context.mounted) return;

    // 是否包含聊天记录
    var includeChat = false;
    final msgs = <ChatMessage>[];
    final sessions = await state.sessionsFor(c.id);
    if (sessions.isNotEmpty) {
      final all = <ChatMessage>[];
      for (final s in sessions) {
        all.addAll(await state.messagesFor(s.id));
      }
      all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (all.isNotEmpty && context.mounted) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('包含聊天记录？'),
            content: Text('共 ${all.length} 条消息，会写入角色卡的扩展字段（其他前端会忽略，不影响使用）。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('不包含')),
              TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('包含')),
            ],
          ),
        );
        includeChat = choice == true;
        if (includeChat) msgs.addAll(all);
      }
    }
    final jsonStr = CharacterCardService.toV2Json(
      c,
      worldbook: selected,
      chatMessages: msgs,
    );
    if (!context.mounted) return;

    if (fmt == 'json') {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出 JSON 角色卡',
        fileName: '${c.name}.json',
        type: FileType.any,
        bytes: utf8.encode(jsonStr),
      );
      if (path != null && path.isNotEmpty && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON 角色卡已导出')));
      }
      return;
    }

    // ---- PNG 卡：先取得原始图片字节 ----
    Uint8List? srcBytes;
    if (fmt == 'pngAvatar') {
      if (c.avatar.isEmpty || c.avatar.startsWith('asset:')) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('不支持：该角色没有可用的头像图片')));
        }
        return;
      }
      try {
        final f = File(c.avatar);
        if (!f.existsSync()) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('不支持：头像文件不存在')));
          }
          return;
        }
        srcBytes = await f.readAsBytes();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('不支持：读取头像失败')));
        }
        return;
      }
    } else {
      // 另选图片
      final r = await FilePicker.platform.pickFiles(
          type: FileType.image, withData: true, compressionQuality: 0);
      if (r == null || r.files.isEmpty) return;
      final f = r.files.first;
      srcBytes = f.bytes;
      if ((srcBytes == null || srcBytes.isEmpty) && (f.path?.isNotEmpty ?? false)) {
        try {
          srcBytes = await File(f.path!).readAsBytes();
        } catch (_) {}
      }
      if (srcBytes == null || srcBytes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('不支持：无法读取所选图片')));
        }
        return;
      }
    }

    // ---- 统一转换为 PNG ----
    final pngBytes = await convertImageToPng(srcBytes);
    if (pngBytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('不支持：该图片无法转换为 PNG')));
      }
      return;
    }
    final cardPng = CharacterCardService.toPng(pngBytes, jsonStr);
    if (cardPng == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PNG 角色卡生成失败')));
      }
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出 PNG 角色卡',
      fileName: '${c.name}.png',
      type: FileType.any,
      bytes: cardPng,
    );
    if (path != null && path.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PNG 角色卡已导出')));
    }
  } catch (_) {}
}
