import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatDelta {
  final String content;
  final String reasoning;
  ChatDelta(this.content, this.reasoning);
}

class ApiClient {
  final http.Client _client = http.Client();

  static String buildEndpoint(String baseUrl) {
    var s = baseUrl.trim();
    if (s.isEmpty) return s;
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('/chat/completions')) return s;
    if (s.endsWith('/v1') || s.endsWith('/v1/')) return '$s/chat/completions';
    return '$s/v1/chat/completions';
  }

  static String buildBase(String baseUrl) {
    var s = baseUrl.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('/v1')) return s;
    if (s.endsWith('/chat/completions')) return s.substring(0, s.length - '/chat/completions'.length);
    return s;
  }

  /// 获取该 key 可用的模型列表
  Future<List<String>> getModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final b = buildBase(baseUrl);
    final uri = Uri.parse('$b/models');
    try {
      final resp = await _client.get(uri, headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      });
      if (resp.statusCode != 200) {
        throw ApiException('HTTP ${resp.statusCode}: ${_short(resp.body)}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = data['data'];
      if (list is List) {
        return list.map((e) => (e as Map<String, dynamic>)['id'].toString()).toList();
      }
      return [];
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('获取模型失败: $e');
    }
  }

  /// 测试连接（拉取模型列表即视为可用）
  Future<List<String>> testConnection({
    required String baseUrl,
    required String apiKey,
  }) async {
    return getModels(baseUrl: baseUrl, apiKey: apiKey);
  }

  /// 流式对话，返回每段新 delta（含内容与思考）
  Stream<ChatDelta> streamChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
    int? maxTokens,
  }) async* {
    final endpoint = buildEndpoint(baseUrl);
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': true,
      'temperature': temperature,
    };
    if (maxTokens != null) body['max_tokens'] = maxTokens;

    try {
      final req = http.Request('POST', Uri.parse(endpoint))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..body = jsonEncode(body);

      final resp = await _client.send(req);
      if (resp.statusCode != 200) {
        final errText = await resp.stream.bytesToString();
        throw ApiException('HTTP ${resp.statusCode}: ${_short(errText)}');
      }

      final lines = resp.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') {
          if (payload == '[DONE]') break;
          continue;
        }
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          final choices = data['choices'];
          if (choices is List && choices.isNotEmpty) {
            final delta = (choices[0] as Map<String, dynamic>)['delta'];
            if (delta is Map<String, dynamic>) {
              final content = delta['content'];
              final reasoning = delta['reasoning_content'];
              if (content is String && content.isNotEmpty) {
                yield ChatDelta(content, '');
              } else if (reasoning is String && reasoning.isNotEmpty) {
                yield ChatDelta('', reasoning);
              }
            }
          }
        } catch (_) {
          // 忽略无法解析的 data 行
        }
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('请求失败: $e');
    }
  }

  /// 非流式完整回答（用于快速生成角色）
  Future<String> completeChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.8,
  }) async {
    final endpoint = buildEndpoint(baseUrl);
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': false,
      'temperature': temperature,
    };
    try {
      final req = http.Request('POST', Uri.parse(endpoint))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..body = jsonEncode(body);
      final resp = await _client.send(req);
      final text = await resp.stream.bytesToString();
      if (resp.statusCode != 200) {
        throw ApiException('HTTP ${resp.statusCode}: ${_short(text)}');
      }
      final data = jsonDecode(text) as Map<String, dynamic>;
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final msg = (choices[0] as Map<String, dynamic>)['message'];
        if (msg is Map<String, dynamic> && msg['content'] is String) {
          return msg['content'] as String;
        }
      }
      return '';
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('请求失败: $e');
    }
  }

  String _short(String s) => s.length > 300 ? '${s.substring(0, 300)}...' : s;
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
