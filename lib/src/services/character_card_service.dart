import 'dart:convert';
import 'dart:typed_data';
import '../models/models.dart';

/// SillyTavern 角色卡解析/导出（V1/V2，PNG/WebP/JSON）。
/// 参考 chara_card_v2 spec 与 lenML/char-card-reader 的做法。
class CharacterCardService {
  // ---------------- 解析 ----------------

  /// 从文件字节解析角色卡。返回 null 表示不识别。
  static ParsedCard? parseBytes(Uint8List bytes) {
    if (bytes.length < 8) return null;
    // JSON 文件（以 { 开头）
    if (bytes[0] == 0x7B) {
      try {
        final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        return _fromJson(map);
      } catch (_) {
        return null;
      }
    }
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      final data = _parsePngChara(bytes);
      if (data == null) return null;
      try {
        final map = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
        return _fromJson(map);
      } catch (_) {
        return null;
      }
    }
    // WebP (RIFF....WEBP)
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      final data = _parseWebpChara(bytes);
      if (data == null) return null;
      try {
        final map = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
        return _fromJson(map);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 从 PNG 里找 tEXt / iTXt 块的 "chara"（或 "ccv3"）关键字，返回其 base64 解码的 JSON 字节。
  static Uint8List? _parsePngChara(Uint8List bytes) {
    var offset = 8;
    while (offset + 8 <= bytes.length) {
      final len = _beUint32(bytes, offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      final dataStart = offset + 8;
      final dataEnd = dataStart + len;
      if (dataEnd + 4 > bytes.length) break;
      if (type == 'tEXt' || type == 'iTXt' || type == 'zTXt') {
        final chunk = bytes.sublist(dataStart, dataEnd);
        final found = _extractKeyword(chunk);
        if (found != null) {
          return found;
        }
      }
      offset = dataEnd + 4; // skip CRC
    }
    return null;
  }

  static Uint8List? _extractKeyword(Uint8List chunk) {
    // 关键字以 \0 结尾
    int nullIdx = -1;
    for (int i = 0; i < chunk.length; i++) {
      if (chunk[i] == 0) {
        nullIdx = i;
        break;
      }
    }
    if (nullIdx <= 0) return null;
    final keyword = ascii.decode(chunk.sublist(0, nullIdx), allowInvalid: true);
    if (keyword != 'chara' && keyword != 'ccv3') return null;
    // 值从 nullIdx+1 开始（tEXt），zTXt 可能压缩；这里按最普遍的无压缩 tEXt 处理
    try {
      final b64 = utf8.decode(chunk.sublist(nullIdx + 1), allowMalformed: true).trim();
      if (b64.isEmpty) return null;
      // 可能是直接 JSON（某些卡没 base64）
      if (b64.startsWith('{')) return utf8.encode(b64);
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _parseWebpChara(Uint8List bytes) {
    var offset = 12; // 跳过 RIFF 头 + WEBP
    while (offset + 8 <= bytes.length) {
      final tag = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = _leUint32(bytes, offset + 4);
      final dataStart = offset + 8;
      final dataEnd = dataStart + size;
      if (dataEnd > bytes.length) break;
      // EXIF 块里含 tEXt 结构
      if (tag == 'EXIF') {
        final exif = bytes.sublist(dataStart, dataEnd);
        final found = _extractKeyword(exif);
        if (found != null) return found;
      }
      offset = dataEnd + (size % 2); // word-aligned
    }
    return null;
  }

  static int _beUint32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  static int _leUint32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static ParsedCard? _fromJson(Map<String, dynamic> map) {
    // V2: 有 spec/data 包裹
    if (map['spec'] == 'chara_card_v2' || map['data'] is Map<String, dynamic>) {
      final data = map['data'] as Map<String, dynamic>;
      return _parseCardData(data);
    }
    // V1/V3 直接字段
    return _parseCardData(map);
  }

  static ParsedCard _parseCardData(Map<String, dynamic> d) {
    final card = ParsedCard(
      name: _s(d['name']),
      description: _s(d['description']),
      personality: _s(d['personality']),
      scenario: _s(d['scenario']),
      firstName: _s(d['first_mes']),
      exampleDialogue: _s(d['mes_example']),
      creatorNotes: _s(d['creator_notes']),
      systemPrompt: _s(d['system_prompt']),
      postHistoryInstructions: _s(d['post_history_instructions']),
      creator: _s(d['creator']),
      characterVersion: _s(d['character_version']),
      tags: _list(d['tags']),
    );
    final ag = d['alternate_greetings'];
    if (ag is List) {
      card.alternateGreetings = ag.map((e) => _s(e)).where((e) => e.isNotEmpty).toList();
    }
    final ext = d['extensions'];
    if (ext is Map) card.extensions = Map<String, dynamic>.from(ext);
    final book = d['character_book'];
    if (book is Map) {
      final entries = book['entries'];
      if (entries is List) {
        for (final e in entries) {
          if (e is Map) {
            final keys = _list(e['keys']);
            final content = _s(e['content']);
            if (content.isNotEmpty) {
              card.worldbook.add(WorldbookEntry(
                id: DateTime.now().microsecondsSinceEpoch.toString() +
                    card.worldbook.length.toString(),
                name: _s(e['name']).isEmpty ? (keys.isNotEmpty ? keys.first : '世界书条目') : _s(e['name']),
                keywords: keys,
                content: content,
                enabled: e['enabled'] != false,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              ));
            }
          }
        }
      }
    }
    return card;
  }

  static String _s(dynamic v) => v is String ? v : (v?.toString() ?? '');
  static List<String> _list(dynamic v) {
    if (v is List) return v.map((e) => _s(e)).where((e) => e.isNotEmpty).toList();
    return [];
  }

  /// 把角色（含扩展字段、世界书）导出为 V2 JSON 字符串。
  static String toV2Json(Character c, {List<WorldbookEntry> worldbook = const []}) {
    final data = <String, dynamic>{
      'name': c.name,
      'description': c.persona,
      'personality': c.personality,
      'scenario': c.scenario,
      'first_mes': c.greeting,
      'mes_example': c.exampleDialogue,
      'creator_notes': c.creatorNotes,
      'system_prompt': c.systemPrompt,
      'post_history_instructions': c.postHistoryInstructions,
      'alternate_greetings': c.alternateGreetings,
      'tags': c.tags,
      'creator': c.creator,
      'character_version': c.characterVersion,
      'extensions': c.extensions.isEmpty ? <String, dynamic>{} : c.extensions,
    };
    if (worldbook.isNotEmpty) {
      data['character_book'] = {
        'entries': worldbook
            .map((e) => {
                  'keys': e.keywords,
                  'content': e.content,
                  'enabled': e.enabled,
                  'insertion_order': 100,
                })
            .toList(),
      };
    }
    return const JsonEncoder.withIndent('  ').convert({'spec': 'chara_card_v2', 'spec_version': '2.0', 'data': data});
  }

  /// 把 V2 JSON 嵌入一张 PNG 图片的 tEXt 块（关键字 chara，base64）。
  /// 返回带角色卡数据的新 PNG 字节；若输入不是合法 PNG 或失败则返回 null。
  static Uint8List? toPng(Uint8List pngBytes, String jsonStr) {
    if (pngBytes.length < 8) return null;
    // 校验 PNG 签名
    if (!(pngBytes[0] == 0x89 && pngBytes[1] == 0x50 && pngBytes[2] == 0x4E && pngBytes[3] == 0x47)) {
      return null;
    }
    final b64 = base64Encode(utf8.encode(jsonStr));
    final keyword = ascii.encode('chara');
    final text = ascii.encode(b64);
    final chunkData = <int>[...keyword, 0, ...text];
    final type = ascii.encode('tEXt');

    final out = BytesBuilder();
    out.add(pngBytes.sublist(0, 8)); // 签名
    var offset = 8;
    Uint8List? iend;
    while (offset + 8 <= pngBytes.length) {
      final len = _beUint32(pngBytes, offset);
      final chunkType = String.fromCharCodes(pngBytes.sublist(offset + 4, offset + 8));
      final dataStart = offset + 8;
      final dataEnd = dataStart + len;
      if (dataEnd + 4 > pngBytes.length) break;
      if (chunkType == 'IEND') {
        iend = pngBytes.sublist(offset, dataEnd + 4);
        break;
      }
      out.add(pngBytes.sublist(offset, dataEnd + 4));
      offset = dataEnd + 4;
    }
    if (iend == null) return null;
    out.add(_chunk(type, chunkData));
    out.add(iend);
    return out.takeBytes();
  }

  static Uint8List _chunk(List<int> type, List<int> data) {
    final b = BytesBuilder();
    b.add(_be32(data.length));
    b.add(type);
    b.add(data);
    b.add(_be32(crc32([...type, ...data])));
    return b.takeBytes();
  }

  static List<int> _be32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  static int crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// 从角色构建一份可导入回自己应用的字段（复用解析映射）。
  static Character toCharacter(ParsedCard p, String id) => Character(
        id: id,
        name: p.name,
        persona: p.description,
        personality: p.personality,
        scenario: p.scenario,
        greeting: p.firstName,
        exampleDialogue: p.exampleDialogue,
        creatorNotes: p.creatorNotes,
        systemPrompt: p.systemPrompt,
        postHistoryInstructions: p.postHistoryInstructions,
        alternateGreetings: p.alternateGreetings,
        tags: p.tags,
        creator: p.creator,
        characterVersion: p.characterVersion,
        extensions: p.extensions,
        lastActivity: DateTime.now().millisecondsSinceEpoch,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
}

class ParsedCard {
  String name;
  String description;
  String personality;
  String scenario;
  String firstName;
  String exampleDialogue;
  String creatorNotes;
  String systemPrompt;
  String postHistoryInstructions;
  String creator;
  String characterVersion;
  List<String> tags;
  List<String> alternateGreetings = [];
  Map<String, dynamic> extensions = {};
  List<WorldbookEntry> worldbook = [];

  ParsedCard({
    this.name = '',
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstName = '',
    this.exampleDialogue = '',
    this.creatorNotes = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.creator = '',
    this.characterVersion = '',
    this.tags = const [],
  });
}
