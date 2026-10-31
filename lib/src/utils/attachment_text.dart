import '../models/models.dart';

const kImageExtensions = {
  'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif', 'jfif',
};

/// 按扩展名判断是不是图片（用户可能用"选择文件"发图片）。
bool isImagePath(String pathOrName) {
  final name = pathOrName.split('/').last.split('\\').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return kImageExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// 把消息正文里的附件"存储路径"换成模型看得懂的自然描述。
///
/// 默认（纯文本模型）：`［图片：/storage/.../IMG_1234.jpg］`
///   → `［用户发送了一张图片：IMG_1234.jpg（1024×768）］`
/// 文件同理，只保留文件名，不暴露内部路径。
///
/// 说明：真正的"看图"需要视觉模型 + 多模态 payload，属于后续接入项；
/// 这里先保证角色不会念出一长串系统路径。
String contentForModel(ChatMessage m) {
  final atts = m.attachments;
  var text = m.content;
  if (!text.contains('［图片：') && !text.contains('［文件：')) return text;

  Attachment? find(String p) {
    for (final a in atts) {
      if (a.path == p) return a;
    }
    return null;
  }

  text = text.replaceAllMapped(RegExp(r'［(图片|文件)：([^］]+)］'), (mt) {
    final kind = mt.group(1)!;
    final path = (mt.group(2) ?? '').trim();
    final a = find(path);
    final name = (a != null && a.name.isNotEmpty)
        ? a.name
        : path.split('/').last.split('\\').last;
    if (kind == '图片' || isImagePath(path)) {
      final size = (a != null && a.width > 0 && a.height > 0) ? '（${a.width}×${a.height}）' : '';
      return '［用户发送了一张图片：$name$size］';
    }
    return '［用户发送了一个文件：$name］';
  });

  // 去掉附件标记后若正文为空，给个占位，避免模型收到空消息
  if (text.trim().isEmpty && atts.isNotEmpty) {
    return atts.any((a) => a.isImage) ? '［用户发送了一张图片］' : '［用户发送了一个文件］';
  }
  return text;
}
