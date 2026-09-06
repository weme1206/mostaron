import 'dart:convert';
import 'package:file_picker/file_picker.dart';

class ExportService {
  /// 导出全部数据为 JSON 文件（含角色与聊天记录）
  static Future<bool> exportToFile(Map<String, dynamic> data, String suggestedName) async {
    try {
      final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出全部数据',
        fileName: suggestedName,
        type: FileType.any,
        bytes: bytes,
      );
      return path != null && path.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 从 JSON 文件导入全部数据
  static Future<Map<String, dynamic>?> importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (result == null || result.files.isEmpty) return null;
      final f = result.files.first;
      final bytes = f.bytes;
      if (bytes == null) {
        final raw = await f.xFile.readAsBytes();
        return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      }
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
