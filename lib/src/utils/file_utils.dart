import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 把选择的图片持久化为 App 内固定名的单份文件，并删除 FilePicker 临时复制。
/// 返回固定路径；若源无效则返回原路径。
Future<String> persistPickedImage(String srcPath, String fixedName) async {
  if (srcPath.isEmpty) return srcPath;
  final dir = await getApplicationDocumentsDirectory();
  final dest = '${dir.path}/$fixedName';
  try {
    final src = File(srcPath);
    if (src.existsSync()) {
      await src.copy(dest);
      try {
        src.deleteSync();
      } catch (_) {}
      return dest;
    }
  } catch (_) {}
  return srcPath;
}
