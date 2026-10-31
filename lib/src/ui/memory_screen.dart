import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../services/api_client.dart';
import '../services/memory_helper.dart';

class MemoryScreen extends StatefulWidget {
  final String characterId; // 记忆归属键（角色 id / group_x / group_x_char_y）
  final String? memoryModeLabel; // 群聊记忆模式小字提示
  /// 从哪个群的聊天记录生成记忆（角色在群里的独立记忆用）
  final String? historyGroupId;
  const MemoryScreen({
    super.key,
    required this.characterId,
    this.memoryModeLabel,
    this.historyGroupId,
  });

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<MemoryItem> _items = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = await context.read<AppState>().memoriesFor(widget.characterId);
    // 置顶的记忆排在最上方（其余按时间）
    final sorted = List<MemoryItem>.of(e);
    sorted.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    if (mounted) setState(() => _items = sorted);
  }

  /// AI 生成记忆
  Future<void> _aiGenerate() async {
    if (_busy) return;
    final state = context.read<AppState>();
    final provider = state.getProviderById(null);
    if (provider == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先配置接口')));
      }
      return;
    }
    var history = <ChatMessage>[];
    if (widget.historyGroupId != null) {
      history = await state.groupMessages(widget.historyGroupId!);
    } else if (widget.characterId.startsWith('group_')) {
      history = await state.groupMessages(widget.characterId.substring(6));
    } else {
      final session = await state.getOrCreateSession(widget.characterId);
      history = await state.messagesFor(session.id);
    }
    if (history.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('还没有对话可生成记忆')));
      }
      return;
    }
    setState(() => _busy = true);
    try {
      // 把对话整理成一段文本交给模型"提炼记忆"，而不是当作对话轮次（否则模型会续写）
      final transcript = MemoryHelper.buildTranscript(
        history
            .map((m) => (m.role == 'user' ? '玩家' : '角色', m.content))
            .toList(),
      );
      final text = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: provider.model,
        messages: MemoryHelper.buildMessages(transcript),
        temperature: 0.3,
      )).trim();
      if (MemoryHelper.isValid(text)) {
        await state.addMemory(MemoryItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          characterId: widget.characterId,
          content: MemoryHelper.clean(text),
          pinned: true,
        ));
        await _load();
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('没有提炼出可用的记忆')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('新增记忆'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(labelText: '记忆内容（关键规则会被写入 AGENTS.md）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(d, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await context.read<AppState>().addMemory(MemoryItem(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            characterId: widget.characterId,
            content: ctrl.text.trim(),
            pinned: false,
          ));
      await _load();
    }
  }

  Future<void> _edit(MemoryItem m) async {
    final ctrl = TextEditingController(text: m.content);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('编辑记忆'),
        content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(labelText: '内容')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(d, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await context.read<AppState>().updateMemory(m.copyWith(content: ctrl.text.trim()));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('长期记忆'),
        actions: [
          IconButton(
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            tooltip: 'AI 生成记忆',
            onPressed: _busy ? null : _aiGenerate,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('置顶的记忆会写入 AGENTS.md，进入系统提示词并长期生效。', style: TextStyle(fontSize: 12)),
          ),
          if (widget.memoryModeLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.memoryModeLabel!,
                    style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
              ),
            ),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('暂无记忆，点击右下角添加'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final m = _items[i];
                      return Card(
                        child: ListTile(
                          tileColor: m.pinned
                              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                              : null,
                          leading: IconButton(
                            icon: Icon(
                              m.pinned ? Icons.bookmark : Icons.bookmark_border,
                              color: m.pinned ? Theme.of(context).colorScheme.primary : null,
                            ),
                            onPressed: () async {
                              await context.read<AppState>().togglePinMemory(m.id, widget.characterId);
                              await _load();
                            },
                          ),
                          title: Text(m.content, maxLines: 3, overflow: TextOverflow.ellipsis),
                          subtitle: m.pinned ? const Text('已写入 AGENTS.md') : null,
                          onTap: () => _edit(m),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await context.read<AppState>().deleteMemory(m.id);
                              await _load();
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
