import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/models.dart';
import 'preset_avatar.dart';

Widget buildCharacterAvatar(BuildContext context, Character c, double size) {
  final avatar = c.avatar;
  if (avatar.startsWith('asset:')) {
    return PresetAvatar(id: avatar.substring(6), size: size);
  }
  if (avatar.isEmpty) {
    return CircleAvatar(
      radius: size / 2,
      child: Text(c.name.isEmpty ? '?' : c.name.substring(0, 1), style: TextStyle(fontSize: size * 0.4)),
    );
  }
  return CircleAvatar(radius: size / 2, backgroundImage: FileImage(File(avatar)));
}

Widget buildGroupAvatar(BuildContext context, ChatGroup g, double size) {
  final avatar = g.avatar;
  if (avatar.startsWith('asset:')) {
    return PresetAvatar(id: avatar.substring(6), size: size);
  }
  if (avatar.isEmpty) {
    return CircleAvatar(
      radius: size / 2,
      child: Text(g.name.isEmpty ? '群' : g.name.substring(0, 1), style: TextStyle(fontSize: size * 0.4)),
    );
  }
  return CircleAvatar(radius: size / 2, backgroundImage: FileImage(File(avatar)));
}

Widget buildUserAvatar(BuildContext context, AppSettings s, double size) {
  final avatar = s.userAvatar;
  if (avatar.startsWith('asset:')) {
    return PresetAvatar(id: avatar.substring(6), size: size);
  }
  if (avatar.isEmpty) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(s.personaName.isEmpty ? '你' : s.personaName.substring(0, 1),
          style: TextStyle(fontSize: size * 0.4, color: Theme.of(context).colorScheme.onPrimaryContainer)),
    );
  }
  return CircleAvatar(radius: size / 2, backgroundImage: FileImage(File(avatar)));
}
