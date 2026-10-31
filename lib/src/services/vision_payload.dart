import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/models.dart';
import '../utils/attachment_text.dart';

/// 判断附件是否图片：优先看 type，其次看扩展名。
/// （用户可能通过"选择文件"发图片，这时 type 是 file）
bool looksLikeImage(Attachment a) {
  if (a.isImage) return true;
  return isImagePath(a.name.isNotEmpty ? a.name : a.path);
}

/// 后台 isolate：压成 512 长边、JPEG 60（几百 KB → 几十 KB，接口才不易卡）
String? _encodeSync(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    if (bytes.isEmpty) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var out = decoded;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longest > 512) {
      final s = 512 / longest;
      out = img.copyResize(
        decoded,
        width: (decoded.width * s).round().clamp(1, 512),
        height: (decoded.height * s).round().clamp(1, 512),
      );
    }
    final jpg = img.encodeJpg(out, quality: 60);
    return 'data:image/jpeg;base64,${base64Encode(jpg)}';
  } catch (_) {
    return null;
  }
}

/// 图片 → data URL（后台线程 + 超时保护，永远不阻塞发送）
Future<String?> imageDataUrl(String path) async {
  try {
    final r = await compute(_encodeSync, path).timeout(const Duration(seconds: 15));
    if (r != null) return r;
  } catch (_) {}
  // 兜底：用 Flutter 自带解码器（解码时缩放），编码成 PNG
  try {
    final bytes = await File(path).readAsBytes();
    if (bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return 'data:image/png;base64,${base64Encode(data.buffer.asUint8List())}';
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}

const _textExts = {
  'txt', 'md', 'markdown', 'json', 'jsonl', 'csv', 'tsv', 'log', 'yml', 'yaml',
  'xml', 'html', 'htm', 'ini', 'cfg', 'conf', 'toml', 'dart', 'js', 'ts', 'py',
  'java', 'kt', 'c', 'h', 'cpp', 'cs', 'go', 'rs', 'php', 'rb', 'sh', 'sql', 'tex',
};

/// 读取文本类附件的内容（最多 [maxChars] 字符）。
String _readTextFile(String path, {int maxChars = 6000}) {
  try {
    final name = path.split('/').last.split('\\').last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!_textExts.contains(ext)) return '';
    final f = File(path);
    if (!f.existsSync()) return '';
    var text = f.readAsStringSync();
    if (text.length > maxChars) {
      text = '${text.substring(0, maxChars)}\n…（文件过长，已截断）';
    }
    return text;
  } catch (_) {
    return '';
  }
}

/// 为"最后一条用户消息"构造发给模型的内容：
/// - 没有图片/文本文件 → 返回 null（保持原样，纯文本）
/// - 有文本文件 → 正文后追加文件内容（String）
/// - 有图片 → 返回多模态 parts（List），图片以 data URL 内联
Future<dynamic> buildUserContent(ChatMessage m, {bool vision = true}) async {
  final atts = m.attachments;
  final baseText = contentForModel(m);

  final sb = StringBuffer(baseText);
  var hasExtra = false;
  for (final a in atts) {
    if (looksLikeImage(a)) continue;
    final t = _readTextFile(a.path);
    if (t.isEmpty) continue;
    hasExtra = true;
    final name = a.name.isNotEmpty ? a.name : a.path.split('/').last;
    sb.write('\n\n【附件内容：$name】\n$t');
  }

  final images = atts.where(looksLikeImage).toList();
  if (!vision || images.isEmpty) {
    return hasExtra ? sb.toString() : null;
  }

  final parts = <Map<String, dynamic>>[
    {'type': 'text', 'text': sb.toString()},
  ];
  for (final a in images.take(3)) {
    final url = await imageDataUrl(a.path);
    if (url != null) {
      parts.add({
        'type': 'image_url',
        'image_url': {
          'url': url,
          'detail': 'high', // 官方参考代码里的写法
        },
      });
    }
  }
  if (parts.length == 1) {
    return hasExtra ? sb.toString() : null;
  }
  return parts;
}
