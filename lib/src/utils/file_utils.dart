import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// 把字节写入 App 文档目录下的唯一文件，返回路径。
Future<String> saveBytesToApp(Uint8List bytes, String ext) async {
  final dir = await getApplicationDocumentsDirectory();
  final name = 'import_${DateTime.now().microsecondsSinceEpoch}.$ext';
  final dest = '${dir.path}/$name';
  try {
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  } catch (_) {
    return '';
  }
}
