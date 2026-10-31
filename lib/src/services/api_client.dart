import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatDelta {
  final String content;
  final String reasoning;
  ChatDelta(this.content, this.reasoning);
}

/// 非流式完整结果：正文 + 思考。
/// 思考型模型会把正文放 content、思考放 reasoning_content，两者都必须保留，
/// 否则界面上就"看不到思考"了。
class ChatResult {
  final String content;
  final String reasoning;
  const ChatResult(this.content, this.reasoning);
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
    // 以版本号结尾就直接拼（/v1、/v4 等）。
    // 智谱的 baseUrl 是 https://open.bigmodel.cn/api/paas/v4，
    // 原来只认 /v1，会拼成 /v4/v1/chat/completions 直接 404。
    if (RegExp(r'/v\d+$').hasMatch(s)) return '$s/chat/completions';
    return '$s/v1/chat/completions';
  }

  static String buildBase(String baseUrl) {
    var s = baseUrl.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (RegExp(r'/v\d+$').hasMatch(s)) return s;
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
      // 加超时：弱网/服务端不响应时"测试连接"不会永远转圈
      final resp = await _client
          .get(uri, headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          })
          .timeout(const Duration(seconds: 20));
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
    required List<Map<String, dynamic>> messages,
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

      final resp = await _client.send(req).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw ApiException('请求超时（60 秒无响应）'),
      );
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
              // 兼容两种字段名：DeepSeek 官方用 reasoning_content，
              // 部分网关/OpenRouter 风格用 reasoning
              final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
              // 同一个分片可能同时带思考与正文（群聊回复短时服务端常把整段合并成一个分片）。
              // 原来写成 if/else if，会直接丢掉思考，导致"有正文没思考"。
              // 两段都要保留，且思考先于正文，保证拼接顺序正确。
              if (reasoning is String && reasoning.isNotEmpty) {
                yield ChatDelta('', reasoning);
              }
              if (content is String && content.isNotEmpty) {
                yield ChatDelta(content, '');
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

  /// 非流式完整回答（用于快速生成角色等只取正文的场景）
  Future<String> completeChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.8,
    int? maxTokens,
  }) async {
    final r = await completeChatFull(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    return r.content;
  }

  /// 非流式完整回答：正文与思考一起返回（思考型模型的 reasoning_content 不再丢弃）
  Future<ChatResult> completeChatFull({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.8,
    int? maxTokens,
  }) async {
    final endpoint = buildEndpoint(baseUrl);
    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'stream': false,
      'temperature': temperature,
    };
    if (maxTokens != null) body['max_tokens'] = maxTokens;
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
        if (msg is Map<String, dynamic>) {
          final c = msg['content'];
          final r = msg['reasoning_content'] ?? msg['reasoning'];
          final content = c is String ? c : '';
          final reasoning = r is String ? r : '';
          if (content.trim().isNotEmpty) return ChatResult(content, reasoning);
          // deepseek-flash 是思考型模型：token 被思考吃光时 content 为空，
          // 这时把 reasoning_content 里最后一段当正文兜底
          if (reasoning.trim().isNotEmpty) {
            final lines = reasoning
                .trim()
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .toList();
            final tail = lines.length > 6 ? lines.sublist(lines.length - 6) : lines;
            return ChatResult(tail.join('\n').trim(), reasoning);
          }
        }
      }
      return const ChatResult('', '');
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
