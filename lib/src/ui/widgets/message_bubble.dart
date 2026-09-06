import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../utils/action_text.dart';

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
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;

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
    this.onCopy,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseColor = bubbleColor ?? (isUser ? scheme.primary : scheme.surfaceContainerHighest);
    final bubbleBg = baseColor.withValues(alpha: bubbleOpacity.clamp(0.0, 1.0));
    final textColor = isUser ? scheme.onPrimary : scheme.onSurface;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    final segs = parseActionText(message.content, isUser: isUser);

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
                          ),
                          constraints:
                              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                for (final seg in segs)
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
                            style: TextStyle(color: textColor, fontSize: 15.5, height: 1.4),
                          ),
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
          ],
        ),
      ),
    );
  }
}
