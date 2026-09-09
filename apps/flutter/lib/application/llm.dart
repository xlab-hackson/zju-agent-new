import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/models.dart';

Uri modelEndpoint(String base, String protocol) {
  final uri = Uri.parse(base);
  if (uri.scheme != 'https' &&
      !(uri.scheme == 'http' &&
          ['localhost', '127.0.0.1', '::1'].contains(uri.host))) {
    throw const AppError('LLM_CONFIG_INVALID', '模型地址需要 HTTPS，本机模型可以使用 HTTP。');
  }
  if (uri.userInfo.isNotEmpty || uri.host.isEmpty) {
    throw const AppError('LLM_CONFIG_INVALID', '模型地址不正确。');
  }
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (!RegExp(r'/v\d+(?:[a-z0-9.-]*)?(?:/|$)').hasMatch(path)) path += '/v1';
  return uri.replace(
    path: '$path/${protocol == 'anthropic' ? 'messages' : 'chat/completions'}',
  );
}

Stream<String> sseData(Stream<List<int>> bytes) async* {
  final buffer = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (buffer.isNotEmpty) {
        yield buffer.join('\n');
        buffer.clear();
      }
    } else if (line.startsWith('data:')) {
      buffer.add(line.substring(5).replaceFirst(RegExp(r'^ '), ''));
    }
  }
  if (buffer.isNotEmpty) yield buffer.join('\n');
}

class ModelClient {
  ModelClient({Dio? client})
    : dio =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 90),
            ),
          );
  final Dio dio;
  Stream<AgentEvent> complete(
    Json provider,
    List<Json> messages,
    List<Json> tools,
    CancelToken token,
  ) async* {
    final protocol = text(provider, 'protocol', 'openai'),
        anthropic = protocol == 'anthropic';
    final endpoint = modelEndpoint(text(provider, 'baseUrl'), protocol);
    final apiKey = text(provider, 'apiKey');
    if (apiKey.isEmpty || text(provider, 'model').isEmpty) {
      throw const AppError('LLM_CONFIG_INVALID', '请配置模型名称和 API Key。');
    }
    final body = <String, dynamic>{
      'model': provider['model'],
      'stream': true,
      'messages': anthropic ? _anthropicMessages(messages) : messages,
      if (tools.isNotEmpty)
        'tools': anthropic
            ? tools
                  .map(
                    (t) => {
                      'name': t['name'],
                      'description': t['description'],
                      'input_schema': t['parameters'],
                    },
                  )
                  .toList()
            : tools.map((t) => {'type': 'function', 'function': t}).toList(),
      if (anthropic) 'max_tokens': 4096,
      if (anthropic)
        'system': messages
            .where((m) => m['role'] == 'system')
            .map((m) => m['content'])
            .join('\n'),
    };
    try {
      final response = await dio.postUri<ResponseBody>(
        endpoint,
        data: body,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          headers: {
            if (anthropic)
              'x-api-key': apiKey
            else
              'Authorization': 'Bearer $apiKey',
            if (anthropic) 'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
        ),
      );
      if (response.data == null) {
        throw const AppError('LLM_STREAM_ERROR', '模型没有返回响应。');
      }
      final calls = <int, Json>{};
      var finished = false;
      await for (final raw in sseData(response.data!.stream)) {
        if (raw == '[DONE]') {
          finished = true;
          break;
        }
        final event = object(jsonDecode(raw));
        if (event['error'] != null || event['type'] == 'error') {
          throw const AppError('LLM_STREAM_ERROR', '模型服务返回错误，请检查配置和额度。');
        }
        if (anthropic) {
          final index = integer(event['index']);
          if (event['type'] == 'content_block_start') {
            final block = object(event['content_block']);
            if (block['type'] == 'tool_use') {
              calls[index] = {
                'id': block['id'],
                'name': block['name'],
                'arguments': '',
              };
            }
          }
          if (event['type'] == 'content_block_delta') {
            final delta = object(event['delta']);
            if (delta['type'] == 'text_delta') {
              yield AgentEvent('text', {'delta': delta['text']});
            }
            if (delta['type'] == 'input_json_delta' && calls[index] != null) {
              calls[index]!['arguments'] =
                  '${calls[index]!['arguments']}${delta['partial_json'] ?? ''}';
            }
          }
          if (event['type'] == 'message_stop') finished = true;
        } else {
          for (final choice in rows(event['choices'] ?? [])) {
            final delta = object(choice['delta'] ?? {});
            if (delta['content'] is String) {
              yield AgentEvent('text', {'delta': delta['content']});
            }
            for (final part in rows(delta['tool_calls'] ?? [])) {
              final index = integer(part['index']),
                  function = object(part['function'] ?? {});
              final call = calls.putIfAbsent(
                index,
                () => {'id': '', 'name': '', 'arguments': ''},
              );
              if (part['id'] != null) call['id'] = part['id'];
              call['name'] = '${call['name']}${function['name'] ?? ''}';
              call['arguments'] =
                  '${call['arguments']}${function['arguments'] ?? ''}';
            }
            if (choice['finish_reason'] != null) finished = true;
          }
        }
      }
      if (!finished) throw const AppError('LLM_STREAM_ERROR', '模型响应中断，请重试。');
      for (final c in calls.values) {
        final input = object(
          jsonDecode(
            text(c, 'arguments').isEmpty ? '{}' : text(c, 'arguments'),
          ),
        );
        yield AgentEvent('tool_call_end', {
          'toolCall': {'id': c['id'], 'name': c['name'], 'input': input},
        });
      }
      yield const AgentEvent('message_end', {'finishReason': 'stop'});
    } on DioException catch (e) {
      throw AppError(
        e.type == DioExceptionType.cancel ? 'CANCELLED' : 'LLM_REQUEST_FAILED',
        e.type == DioExceptionType.cancel ? '已停止回答。' : '模型请求失败，请检查网络、地址和密钥。',
      );
    } on FormatException {
      throw const AppError('LLM_STREAM_ERROR', '模型返回的流式数据或工具参数无效。');
    }
  }

  List<Json> _anthropicMessages(List<Json> messages) {
    final result = <Json>[];
    for (final m in messages.where((m) => m['role'] != 'system')) {
      if (m['role'] == 'tool') {
        result.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': m['tool_call_id'],
              'content': m['content'],
            },
          ],
        });
      } else if (m['role'] == 'assistant') {
        result.add({
          'role': 'assistant',
          'content': [
            if (text(m, 'content').isNotEmpty)
              {'type': 'text', 'text': m['content']},
            for (final c in rows(m['tool_calls'] ?? []))
              {
                'type': 'tool_use',
                'id': c['id'],
                'name': object(c['function'])['name'],
                'input': jsonDecode(text(object(c['function']), 'arguments')),
              },
          ],
        });
      } else {
        result.add({'role': 'user', 'content': m['content']});
      }
    }
    return result;
  }
}
