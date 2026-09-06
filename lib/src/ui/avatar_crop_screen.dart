import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

/// 头像裁剪：可缩放/平移，固定圆，保存后返回裁剪文件路径
class AvatarCropScreen extends StatefulWidget {
  final String imagePath;
  const AvatarCropScreen({super.key, required this.imagePath});

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      final f = File(path);
      await f.writeAsBytes(byteData!.buffer.asUint8List());
      if (mounted) Navigator.pop(context, path);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = 340.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('裁剪头像'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('拖动/缩放图片，圆形区域即为头像', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RepaintBoundary(
                    key: _repaintKey,
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 4.0,
                        clipBehavior: Clip.none,
                        child: SizedBox(
                          width: size,
                          height: size,
                          child: Image.file(File(widget.imagePath), fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('裁剪后会保存圆形区域', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          ],
        ),
      ),
    );
  }
}
