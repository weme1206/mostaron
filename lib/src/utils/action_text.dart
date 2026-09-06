class RichSegment {
  final String text;
  final bool isAction; // 是否 (动作)
  final bool isUser; // 是否用户方（玩家）
  RichSegment(this.text, {this.isAction = false, this.isUser = false});
}

/// 将消息文本解析为多个片段，`（...）` 或 `(...)` 视为动作
List<RichSegment> parseActionText(String raw, {bool isUser = false}) {
  final segs = <RichSegment>[];
  final re = RegExp(r'[（(]([^（）()]+)[）)]');
  int last = 0;
  for (final m in re.allMatches(raw)) {
    if (m.start > last) {
      segs.add(RichSegment(raw.substring(last, m.start), isUser: isUser));
    }
    segs.add(RichSegment(m.group(1)!, isAction: true, isUser: isUser));
    last = m.end;
  }
  if (last < raw.length) {
    segs.add(RichSegment(raw.substring(last), isUser: isUser));
  }
  if (segs.isEmpty) {
    segs.add(RichSegment(raw, isUser: isUser));
  }
  return segs;
}
