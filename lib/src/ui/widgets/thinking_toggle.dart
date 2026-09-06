import 'package:flutter/material.dart';

/// 紧凑的"思考"折叠按钮：只有"思考 ›"，点击展开/收起
class ThinkingToggle extends StatefulWidget {
  final String reasoning;
  const ThinkingToggle({super.key, required this.reasoning});

  @override
  State<ThinkingToggle> createState() => _ThinkingToggleState();
}

class _ThinkingToggleState extends State<ThinkingToggle> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.reasoning.trim().isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('思考', style: TextStyle(fontSize: 12, color: scheme.primary)),
                Icon(_open ? Icons.expand_more : Icons.keyboard_arrow_right, size: 14, color: scheme.primary),
              ],
            ),
            if (_open)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(6),
                width: MediaQuery.of(context).size.width * 0.72,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(widget.reasoning, style: const TextStyle(fontSize: 12, height: 1.4)),
              ),
          ],
        ),
      ),
    );
  }
}
