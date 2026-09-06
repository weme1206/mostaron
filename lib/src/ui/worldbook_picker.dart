import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

/// 选择结果：
/// - [WorldbookPickResult.ids] 已选中的全局世界书条目 id 列表（在非 manage 时有效）
/// - [WorldbookPickResult.manage] 为 true 表示用户想打开“管理全局世界书”
class WorldbookPickResult {
  const WorldbookPickResult.selected(this.ids) : manage = false;
  const WorldbookPickResult.manage()
      : ids = const [],
        manage = true;
  final List<String> ids;
  final bool manage;
}

/// 底部弹出勾选对话框，从全局世界书里为角色/群勾选启用哪些。
/// 返回 null 表示取消。
Future<WorldbookPickResult?> showWorldbookPicker(
  BuildContext context, {
  required List<String> initial,
}) async {
  final state = context.read<AppState>();
  final entries = await state.worldbookFor(null); // 全局世界书
  final selected = List<String>.from(initial);
  if (!context.mounted) return null;

  final result = await showModalBottomSheet<WorldbookPickResult>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) {
        void toggle(String id, bool v) {
          setSheet(() {
            if (v) {
              if (!selected.contains(id)) selected.add(id);
            } else {
              selected.remove(id);
            }
          });
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '启用哪些世界书',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetCtx, const WorldbookPickResult.manage()),
                      child: const Text('管理全局'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetCtx, WorldbookPickResult.selected(selected)),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('暂无全局世界书，请先在“设置 → 世界书”添加', textAlign: TextAlign.center),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (ctx, i) {
                      final e = entries[i];
                      return CheckboxListTile(
                        value: selected.contains(e.id),
                        title: Text(e.name),
                        subtitle: e.keywords.isNotEmpty ? Text('关键词: ${e.keywords.join(', ')}') : null,
                        onChanged: (v) => toggle(e.id, v ?? false),
                      );
                    },
                  ),
                ),
              if (entries.isNotEmpty) const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
  return result;
}
