import 'dart:async';
import 'package:flutter/material.dart';

/// 输入框右上角的 AI 改写 / 撤销按钮。
/// 逻辑：
/// - 输入框无内容 → 不显示
/// - 输入框内容是刚刚 AI 改写的结果 → 显示"撤销"
/// - 其余有内容 → 显示"AI改写"
/// - 改写中显示"撤销"，可点击取消改写（丢弃结果，还原原消息）
class AiRewriteButton extends StatefulWidget {
  final TextEditingController controller;
  final Future<String> Function(String text) rewrite;
  final double size;
  final Color? color;
  final double fontSize;
  final ValueChanged<bool>? onRewriting;
  const AiRewriteButton({
    super.key,
    required this.controller,
    required this.rewrite,
    this.size = 16,
    this.color,
    this.fontSize = 10,
    this.onRewriting,
  });

  @override
  State<AiRewriteButton> createState() => _AiRewriteButtonState();
}

class _AiRewriteButtonState extends State<AiRewriteButton> {
  bool _rewriting = false;
  String _original = ''; // 改写前输入框内容
  String? _rewritten; // 最新 AI 改写结果
  bool _cancel = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _debounce?.cancel();
    super.dispose();
  }

  /// 输入框内容变化（用户手输或脚本设置）：刷新按钮显隐；若不再是"AI 改写结果"，切回 AI改写。
  void _onChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      if (!_rewriting) {
        final cur = widget.controller.text;
        if (_rewritten != null) {
          // 用户改了输入框内容，清掉"改写结果"状态
          if (cur != _rewritten && cur != _original) {
            setState(() => _rewritten = null);
            return;
          }
          if (cur == _original) {
            // 还原到原文
            setState(() => _rewritten = null);
            return;
          }
        }
        // 至少刷新一次以显示/隐藏按钮
        setState(() {});
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _startRewrite() async {
    final text = widget.controller.text;
    if (text.trim().isEmpty) return;
    _original = text;
    _cancel = false;
    setState(() {
      _rewriting = true;
      _rewritten = null;
    });
    widget.onRewriting?.call(true);
    try {
      final result = await widget.rewrite(text);
      if (!mounted) return;
      widget.onRewriting?.call(false);
      if (_cancel) {
        // 已取消：输入框保持原消息（从未被改动）
        setState(() {
          _rewriting = false;
          _rewritten = null;
        });
        return;
      }
      widget.controller.text = result;
      setState(() {
        _rewritten = result;
        _rewriting = false;
      });
    } catch (_) {
      if (!mounted) return;
      widget.onRewriting?.call(false);
      setState(() {
        _rewriting = false;
        _rewritten = null;
      });
    }
  }

  void _undo() {
    if (_rewriting) {
      // 取消改写：输入框保持原消息
      _cancel = true;
      widget.onRewriting?.call(false);
      setState(() {
        _rewriting = false;
        _rewritten = null;
      });
      return;
    }
    // 撤销改写结果，还原原消息
    widget.controller.text = _original;
    setState(() {
      _rewritten = null;
      _original = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.text.trim().isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final mainColor = widget.color ?? scheme.primary;
    final isUndo = _rewriting || (controller.text == _rewritten && _rewritten != null);
    return InkWell(
      onTap: isUndo ? _undo : _startRewrite,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(left: 2, top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isUndo ? Icons.undo : Icons.auto_awesome,
              size: widget.size,
              color: mainColor,
            ),
            const SizedBox(width: 2),
            Text(isUndo ? '撤销' : 'AI改写',
                style: TextStyle(fontSize: widget.fontSize, color: mainColor)),
          ],
        ),
      ),
    );
  }
}
