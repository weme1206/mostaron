import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../utils/action_text.dart';
import '../../utils/attachment_text.dart';
import '../image_viewer_screen.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isUser;
  final Widget? avatar;
  final String senderName;
  final bool isCurrent; // 是否正在流式生成的不完整消息
  final bool showAvatar;
  final Widget? footer; // 消息下方操作区
  final Widget? topContent; // 气泡上方（昵称下方）内容，如思考
  final Color? bubbleColor; // 自定义气泡颜色
  final double bubbleOpacity;
  final double fontScale; // 全局字体倍率
  final bool highlight; // 是否高亮（查找命中）
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;
  final VoidCallback? onDeleteFromHere; // 删除该消息之后的所有消息

  const MessageBubble({
    super.key,
    required this.message,
    required this.isUser,
    this.avatar,
    this.senderName = '',
    this.isCurrent = false,
    this.showAvatar = true,
    this.footer,
    this.topContent,
    this.bubbleColor,
    this.bubbleOpacity = 1.0,
    this.fontScale = 1.0,
    this.highlight = false,
    this.onCopy,
    this.onDelete,
    this.onDeleteFromHere,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseColor = bubbleColor ?? (isUser ? scheme.primary : scheme.surfaceContainerHighest);
    final bubbleBg = baseColor.withValues(alpha: bubbleOpacity.clamp(0.0, 1.0));
    final textColor = isUser ? scheme.onPrimary : scheme.onSurface;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: GestureDetector(
        onLongPress: () => _showMenu(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser && avatar != null && showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 2),
                      child: ClipOval(child: SizedBox(width: 34, height: 34, child: avatar)),
                    ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (senderName.isNotEmpty && showAvatar)
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 3),
                            child: Text(senderName, style: TextStyle(fontSize: 12, color: scheme.primary)),
                          ),
                        if (topContent != null) topContent!,
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: bubbleBg,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isUser ? 16 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 16),
                            ),
                            border: highlight ? Border.all(color: scheme.primary, width: 2) : null,
                          ),
                          constraints:
                              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                          child: Builder(builder: (_) {
                            final (atts, text) = splitAttachments(message);
                            final imgs = atts
                                .where((a) => a.isImage || isImagePath(a.name.isNotEmpty ? a.name : a.path))
                                .toList();
                            final files = atts
                                .where((a) => !(a.isImage || isImagePath(a.name.isNotEmpty ? a.name : a.path)))
                                .toList();
                            final maxW = MediaQuery.of(context).size.width * 0.78 - 28;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (imgs.isNotEmpty) ...[
                                  _buildImages(context, imgs, maxW),
                                  if (text.trim().isNotEmpty) const SizedBox(height: 6),
                                ],
                                if (text.trim().isNotEmpty)
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        for (final seg in parseActionText(text, isUser: isUser))
                                          TextSpan(
                                            text: seg.text,
                                            style: seg.isAction
                                                ? TextStyle(
                                                    fontStyle: FontStyle.italic,
                                                    color: isUser
                                                        ? scheme.onPrimary.withValues(alpha: 0.9)
                                                        : scheme.secondary,
                                                  )
                                                : TextStyle(color: textColor),
                                          ),
                                      ],
                                    ),
                                    style: TextStyle(
                                        color: textColor,
                                        fontSize: 15.5 * fontScale,
                                        height: 1.4),
                                  ),
                                if (files.isNotEmpty) ...[
                                  if (text.trim().isNotEmpty) const SizedBox(height: 6),
                                  for (final f in files) _buildFile(context, f, textColor),
                                ],
                              ],
                            );
                          }),
                        ),
                        if (footer != null) Padding(padding: const EdgeInsets.only(top: 2), child: footer),
                      ],
                    ),
                  ),
                  if (isUser && avatar != null && showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: ClipOval(child: SizedBox(width: 34, height: 34, child: avatar)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 从消息里取附件：优先 meta；旧消息则解析正文里的 ［图片：…］ / ［文件：…］ 标记。
  /// 返回 (附件列表, 去掉标记后的正文)。
  static (List<Attachment>, String) splitAttachments(ChatMessage m) {
    var atts = List<Attachment>.of(m.attachments);
    var text = m.content;
    if (text.contains('［图片：') || text.contains('［文件：')) {
      final re = RegExp(r'［(图片|文件)：([^］]+)］\r?\n?');
      final found = <Attachment>[];
      for (final match in re.allMatches(text)) {
        final type = match.group(1) == '图片' ? 'image' : 'file';
        final path = (match.group(2) ?? '').trim();
        if (path.isEmpty) continue;
        found.add(Attachment(
          type: type,
          path: path,
          name: path.split(Platform.pathSeparator).last.split('/').last,
        ));
      }
      if (found.isNotEmpty) {
        if (atts.isEmpty) atts = found;
        text = text.replaceAll(re, '').trim();
      }
    }
    return (atts, text);
  }

  /// 图片缩略图：知道宽高时用 AspectRatio 预留高度，避免布局漂移。
  Widget _buildImages(BuildContext context, List<Attachment> imgs, double maxW) {
    Widget thumb(Attachment a, double w) {
      final hasRatio = a.width > 0 && a.height > 0;
      final file = File(a.path);
      Widget img = file.existsSync()
          ? Image.file(
              file,
              width: w,
              height: hasRatio ? null : 160,
              fit: BoxFit.cover,
              cacheWidth: (w * 2).round().clamp(1, 1600),
              errorBuilder: (_, __, ___) => Container(
                width: w,
                height: hasRatio ? w * a.height / a.width : 160,
                color: Colors.black12,
                child: const Icon(Icons.broken_image),
              ),
            )
          : Container(
              width: w,
              height: hasRatio ? w * a.height / a.width : 160,
              color: Colors.black12,
              child: const Icon(Icons.image_not_supported),
            );
      if (hasRatio) {
        img = AspectRatio(aspectRatio: a.width / a.height, child: img);
      }
      return GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ImageViewerScreen(path: a.path)),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: img),
      );
    }

    if (imgs.length == 1) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: 260),
        child: thumb(imgs[0], maxW),
      );
    }
    final cellW = (maxW - 6) / 2;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final a in imgs.take(4))
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cellW, maxHeight: 150),
            child: thumb(a, cellW),
          ),
      ],
    );
  }

  Widget _buildFile(BuildContext context, Attachment a, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, size: 16 * fontScale, color: textColor),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              a.name.isEmpty ? a.path.split(Platform.pathSeparator).last : a.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12 * fontScale, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制消息'),
              onTap: () {
                Navigator.pop(ctx);
                onCopy?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () {
                Navigator.pop(ctx);
                onDelete?.call();
              },
            ),
            if (onDeleteFromHere != null)
              ListTile(
                leading: const Icon(Icons.delete_sweep),
                title: const Text('删除从这里开始的消息'),
                onTap: () {
                  Navigator.pop(ctx);
                  onDeleteFromHere?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}
