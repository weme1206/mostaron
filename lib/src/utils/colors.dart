import 'package:flutter/material.dart';

/// 解析 "#RRGGBB" 或 "#AARRGGBB"；失败返回 null
Color? parseHexColor(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  var t = s.trim();
  if (t.startsWith('#')) t = t.substring(1);
  if (t.length == 6) t = 'FF$t';
  if (t.length != 8) return null;
  final v = int.tryParse(t, radix: 16);
  if (v == null) return null;
  return Color(v);
}

const List<Color> bubbleColorChoices = [
  Color(0xFFFFFFFF), // 白
  Color(0xFFFF9800), // 橙
  Color(0xFFFF69B4), // 粉
  Color(0xFF9C27B0), // 紫
  Color(0xFF1565C0), // 深蓝
  Color(0xFF4CAF50), // 绿
  Color(0xFFF44336), // 红
  Color(0xFF000000), // 黑
];

String colorToHex(Color c) {
  final int r = (c.r * 255).round();
  final int g = (c.g * 255).round();
  final int b = (c.b * 255).round();
  return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
}
