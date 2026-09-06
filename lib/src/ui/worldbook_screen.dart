import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../state/app_state.dart';

class WorldbookScreen extends StatefulWidget {
  final String? ownerId; // 为空=全局世界书；非空=某拥有者（保留兼容）
  const WorldbookScreen({super.key, this.ownerId});

  @override
  State<WorldbookScreen> createState() => _WorldbookScreenState();
}

class _WorldbookScreenState extends State<WorldbookScreen> {
  List<WorldbookEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final e = await state.worldbookFor(widget.ownerId);
    if (mounted) setState(() => _entries = e);
  }

  Future<void> _edit([WorldbookEntry? entry]) async {
    final name = TextEditingController(text: entry?.name ?? '');
    final keywords = TextEditingController(text: entry?.keywords.join(', ') ?? '');
    final content = TextEditingController(text: entry?.content ?? '');
    bool enabled = entry?.enabled ?? true;
    final result = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setDialogState) => AlertDialog(
          title: Text(entry == null ? '新增世界书' : '编辑世界书'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
                const SizedBox(height: 12),
                TextField(controller: keywords, decoration: const InputDecoration(labelText: '关键词（逗号分隔）')),
                const SizedBox(height: 12),
                TextField(controller: content, maxLines: 4, decoration: const InputDecoration(labelText: '触发时注入的背景内容')),
                const SizedBox(height: 4),
                SwitchListTile(
                  title: const Text('启用'),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
            TextButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  ScaffoldMessenger.of(d).showSnackBar(const SnackBar(content: Text('请填写名称')));
                  return;
                }
                Navigator.pop(d, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      final state = context.read<AppState>();
      final w = WorldbookEntry(
        id: entry?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        characterId: widget.ownerId,
        name: name.text.trim(),
        keywords: keywords.text
            .split(RegExp(r'[,，]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        content: content.text.trim(),
        enabled: enabled,
        createdAt: entry?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      );
      await state.addWorldbook(w);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('世界书')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: _entries.isEmpty
          ? const Center(child: Text('暂无世界书条目，点击右下角添加'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final e = _entries[i];
                return Card(
                  child: ListTile(
                    leading: Switch(
                      value: e.enabled,
                      onChanged: (v) async {
                        await context.read<AppState>().updateWorldbook(e.copyWith(enabled: v));
                        await _load();
                      },
                    ),
                    title: Text(e.name),
                    subtitle: Text(
                      '关键词: ${e.keywords.join(', ')}\n${e.content}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    onTap: () => _edit(e),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await context.read<AppState>().deleteWorldbook(e.id, widget.ownerId);
                        await _load();
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
