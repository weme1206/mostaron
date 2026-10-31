import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

/// 全屏查看图片：支持双指缩放 / 双击放大，长按保存到相册。
class ImageViewerScreen extends StatefulWidget {
  final String path;
  const ImageViewerScreen({super.key, required this.path});

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final TransformationController _tc = TransformationController();

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final has = await Gal.hasAccess();
      if (!has) {
        final ok = await Gal.requestAccess();
        if (!ok) {
          messenger.showSnackBar(const SnackBar(content: Text('没有相册写入权限，无法保存')));
          return;
        }
      }
      await Gal.putImage(widget.path);
      messenger.showSnackBar(const SnackBar(content: Text('已保存到相册')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.path);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '保存到相册',
            onPressed: _save,
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        // 长按不再触发保存（保存按钮在右上角）
        onDoubleTap: () {
          if (_tc.value.isIdentity()) {
            _tc.value = Matrix4.identity()..scale(2.0);
          } else {
            _tc.value = Matrix4.identity();
          }
        },
        child: Center(
          child: file.existsSync()
              ? InteractiveViewer(
                  transformationController: _tc,
                  minScale: 1,
                  maxScale: 5,
                  child: Image.file(file),
                )
              : const Text('图片不存在', style: TextStyle(color: Colors.white70)),
        ),
      ),
    );
  }
}
