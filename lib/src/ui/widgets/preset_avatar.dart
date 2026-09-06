import 'package:flutter/material.dart';

class PresetAvatar extends StatelessWidget {
  final String id;
  final double size;
  const PresetAvatar({super.key, required this.id, required this.size});

  static const _palettes = {
    'a': [Color(0xFF1E88E5), Color(0xFF4FC3F7)],
    'b': [Color(0xFF8E24AA), Color(0xFFE040FB)],
    'c': [Color(0xFF43A047), Color(0xFF76FF03)],
    'd': [Color(0xFFFB8C00), Color(0xFFFFD54F)],
    'e': [Color(0xFFE53935), Color(0xFFFF8A80)],
    'f': [Color(0xFF00897B), Color(0xFF4DB6AC)],
  };

  @override
  Widget build(BuildContext context) {
    final p = _palettes[id] ?? _palettes['a']!;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: p[0],
      child: Icon(Icons.auto_awesome, size: size * 0.45, color: p[1]),
    );
  }
}
