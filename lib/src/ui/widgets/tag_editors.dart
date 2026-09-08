import 'package:flutter/material.dart';

/// 简单的标签编辑：显示已添加的 Chip，可添加/删除。
class TagEditors extends StatefulWidget {
  final List<String> values;
  final String label;
  final ValueChanged<List<String>> onChange;
  const TagEditors({super.key, required this.values, required this.label, required this.onChange});

  @override
  State<TagEditors> createState() => _TagEditorsState();
}

class _TagEditorsState extends State<TagEditors> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    if (!widget.values.contains(t)) {
      widget.onChange([...widget.values, t]);
    }
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(labelText: widget.label, hintText: '输入后回车添加'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: _add, icon: const Icon(Icons.add)),
            ],
          ),
          if (widget.values.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in widget.values)
                    InputChip(
                      label: Text(v, style: const TextStyle(fontSize: 12)),
                      onDeleted: () => widget.onChange(widget.values.where((e) => e != v).toList()),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
