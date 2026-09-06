import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/colors.dart';

/// 弹出调色盘，返回用户选择的颜色
Future<Color?> showColorPicker(BuildContext context, {Color? initial}) {
  return showDialog<Color>(
    context: context,
    builder: (d) => _ColorPickerDialog(initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final Color? initial;
  const _ColorPickerDialog({this.initial});
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  bool _init = false;

  @override
  Widget build(BuildContext context) {
    if (!_init) {
      final c = widget.initial ?? const Color(0xFF1E88E5);
      _hsv = HSVColor.fromColor(c);
      _init = true;
    }
    final color = _hsv.toColor();
    return AlertDialog(
      title: const Text('选择颜色'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 300,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black26),
              ),
            ),
            const SizedBox(height: 10),
            // 色相
            _HueSlider(
              value: _hsv.hue,
              onChanged: (v) => setState(() => _hsv = _hsv.withHue(v)),
            ),
            const SizedBox(height: 6),
            // 饱和度+明度
            _SVBox(
              hsv: _hsv,
              onChanged: (sv, v) => setState(() => _hsv = _hsv.withSaturation(sv).withValue(v)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _HueSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _HueSlider({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
            Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
          ],
        ),
      ),
      child: Slider(
        value: value,
        min: 0,
        max: 360,
        activeColor: Colors.transparent,
        inactiveColor: Colors.transparent,
        onChanged: onChanged,
      ),
    );
  }
}

class _SVBox extends StatelessWidget {
  final HSVColor hsv;
  final void Function(double sat, double val) onChanged;
  const _SVBox({required this.hsv, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [hsv.withValue(1).withSaturation(1).toColor(), Colors.black],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.white, Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: hsv.saturation * c.maxWidth - 8,
              top: (1 - hsv.value) * c.maxHeight - 8,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (g) => _update(c, g.localPosition, onChanged),
                onTapDown: (g) => _update(c, g.localPosition, onChanged),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _update(BoxConstraints c, Offset local, void Function(double, double) onChanged) {
    final sat = (local.dx / c.maxWidth).clamp(0.0, 1.0);
    final val = (1 - local.dy / c.maxHeight).clamp(0.0, 1.0);
    onChanged(sat, val);
  }
}
