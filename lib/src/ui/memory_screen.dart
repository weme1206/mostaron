import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../services/api_client.dart';

class MemoryScreen extends StatefulWidget {
  final String characterId;
  final String? memoryModeLabel; // 群聊记忆模式小字提示
  const MemoryScreen({super.key, required this.characterId, this.memoryModeLabel});

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
    if (mounted) setState(() => _items = e);
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
    if (widget.characterId.startsWith('group_')) {
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
      final payload = <Map<String, String>>[
        {
          'role': 'system',
          'content': '读取这段对话，提炼 1~3 条值得长期记住的关键信息（人物关系、偏好、重要约定等），每行一条简短陈述，直接输出，不要解释。'
        },
        for (final m in history)
          {'role': m.role == 'user' ? 'user' : 'assistant', 'content': m.content},
      ];
      final text = (await ApiClient().completeChat(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: provider.model,
        messages: payload,
      )).trim();
      if (text.isNotEmpty) {
        await state.addMemory(MemoryItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          characterId: widget.characterId,
          content: text,
          pinned: true,
        ));
        await _load();
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
