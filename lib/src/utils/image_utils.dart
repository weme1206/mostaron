import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 读取图片文件的宽高（失败返回 null）。
/// 用 1024 宽度解码：宽高比与原图一致，但不会把 4000×3000 的整张图解码进内存。
Future<(int, int)?> imageSizeOf(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    if (bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1024);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final size = (img.width, img.height);
    img.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

/// 把任意受支持的图片字节转换为 PNG 字节。
/// 转换失败（格式不支持/数据损坏）返回 null。
Future<Uint8List?> convertImageToPng(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  // 本身已是 PNG 直接返回
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return bytes;
  }
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
