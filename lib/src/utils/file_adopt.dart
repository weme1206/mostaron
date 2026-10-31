import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把"选择器"返回的临时文件搬进应用私有目录，并删掉原副本。
///
/// file_picker 在 Android 上会把选中的文件复制到
/// `/storage/emulated/0/Android/data/<包名>/cache/...`，
/// 而 MIUI/HyperOS 等相册会索引该目录，导致相册/文件管理器里多出一张。
/// 复制到私有目录后删除源副本，就不会再出现在相册里。
Future<String> adoptPickedFile(String srcPath) async {
  try {
    final src = File(srcPath);
    if (!src.existsSync()) return srcPath;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'picked'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final name = p.basename(srcPath);
    final ext = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    final target = p.join(dir.path, '${base}_${DateTime.now().microsecondsSinceEpoch}$ext');
    await src.copy(target);
    // 只删除"可能被相册索引"的源副本（缓存/外部存储），不动相册原图
    try {
      final sp = srcPath.toLowerCase();
      final removable = sp.contains('/cache/') ||
          sp.contains('/android/data/') ||
          sp.contains('\\cache\\') ||
          sp.contains('\\android\\data\\');
      if (removable) await src.delete();
    } catch (_) {}
    return target;
  } catch (_) {
    return srcPath;
  }
}
