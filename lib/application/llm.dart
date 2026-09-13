import 'dart:convert';

import 'package:dio/dio.dart';
import '../domain/models.dart';

Uri _modelServiceBase(String base) {
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
  return uri.replace(path: path);
}

Uri modelEndpoint(String base, String protocol) {
  final uri = _modelServiceBase(base);
  return uri.replace(
    path:
        '${uri.path}/${protocol == 'anthropic' ? 'messages' : 'chat/completions'}',
  );
}

Uri modelListEndpoint(String base) {
  final uri = _modelServiceBase(base);
  return uri.replace(path: '${uri.path}/models');
}

Stream<String> sseData(Stream<List<int>> bytes) async* {
  final buffer = <String>[];
  await for (final line
      // Dio returns Stream<Uint8List>. Widen the stream's runtime type before
      // transform, not just its static type, to avoid a transformer TypeError.
      in bytes
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
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

  Map<String, String> _authHeaders(String apiKey, String protocol) => {
    if (protocol == 'anthropic')
      'x-api-key': apiKey
    else
      'Authorization': 'Bearer $apiKey',
    if (protocol == 'anthropic') 'anthropic-version': '2023-06-01',
    'Content-Type': 'application/json',
  };

  Future<List<String>> listModels(Json provider) async {
    final protocol = text(provider, 'protocol', 'openai');
    if (protocol == 'anthropic') {
      throw const AppError(
        'LLM_MODELS_UNAVAILABLE',
        '当前协议没有统一的模型列表接口，请手动填写模型名称。',
      );
    }
    final apiKey = text(provider, 'apiKey').trim();
    if (apiKey.isEmpty) {
      throw const AppError('LLM_CONFIG_INVALID', '请先填写 API Key。');
    }
    try {
      final response = await dio.getUri<dynamic>(
        modelListEndpoint(text(provider, 'baseUrl')),
        options: Options(headers: _authHeaders(apiKey, protocol)),
      );
      final status = response.statusCode ?? 500;
      if (status < 200 || status >= 300) {
        throw AppError('LLM_REQUEST_FAILED', '模型服务返回 HTTP $status，请检查配置。');
      }
      final payload = response.data;
      final raw = payload is Map
          ? (payload['data'] ?? payload['models'])
          : payload;
      if (raw is! List) {
        throw const AppError('LLM_MODELS_INVALID', '模型服务返回的数据格式无法识别。');
      }
      final models =
          raw
              .map((item) {
                if (item is String) return item.trim();
                if (item is Map) {
                  final id = item['id'] ?? item['name'];
                  return id is String ? id.trim() : '';
                }
                return '';
              })
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (models.isEmpty) {
        throw const AppError('LLM_MODELS_EMPTY', 'API 地址没有返回可用模型。');
      }
      return models;
    } on DioException catch (e) {
      throw _requestError(e);
    }
  }

  /// Sends the smallest non-streaming request needed to verify that the
  /// configured endpoint, API key, and model can work together.
  Future<void> checkAvailability(Json provider) async {
    final protocol = text(provider, 'protocol', 'openai');
    final endpoint = modelEndpoint(text(provider, 'baseUrl'), protocol);
    final apiKey = text(provider, 'apiKey');
    final model = text(provider, 'model').trim();
    if (apiKey.isEmpty || model.isEmpty) {
      throw const AppError('LLM_CONFIG_INVALID', '请先填写模型名称和 API Key。');
    }
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 1,
      'messages': const [
        {'role': 'user', 'content': 'ping'},
      ],
    };
    try {
      final response = await dio.postUri<dynamic>(
        endpoint,
        data: body,
        options: Options(headers: _authHeaders(apiKey, protocol)),
      );
      final status = response.statusCode ?? 500;
      if (status < 200 || status >= 300) {
        throw AppError('LLM_REQUEST_FAILED', '模型服务返回 HTTP $status，请检查配置。');
      }
    } on DioException catch (e) {
      throw _requestError(e);
    }
  }

  AppError _requestError(DioException error) {
    final status = error.response?.statusCode;
    return AppError('LLM_REQUEST_FAILED', switch (status) {
      401 => '模型服务拒绝认证（HTTP 401），请检查 API Key。',
      403 => '模型服务拒绝访问（HTTP 403），请检查账号和模型权限。',
      404 => '模型接口不存在（HTTP 404），请检查 API 地址和模型名称。',
      429 => '模型请求受限（HTTP 429），请检查额度或稍后重试。',
      final int code => '模型服务返回 HTTP $code，请检查配置。',
      _ => '模型连接失败，请检查网络和 API 地址。',
    });
  }

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
      final status = e.response?.statusCode;
      final message = switch (e.type) {
        DioExceptionType.cancel => '已停止回答。',
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => '模型响应超时，请稍后重试。',
        _ => switch (status) {
          401 => '模型服务拒绝认证（HTTP 401），请检查 API Key。',
          403 => '模型服务拒绝访问（HTTP 403），请检查账号和模型权限。',
          404 => '模型接口不存在（HTTP 404），请检查 API 地址和模型名称。',
          429 => '模型请求受限（HTTP 429），请检查额度或稍后重试。',
          final int code => '模型服务返回 HTTP $code，请检查模型配置或稍后重试。',
          _ => '模型连接失败，请检查网络和 API 地址。',
        },
      };
      throw AppError(
        e.type == DioExceptionType.cancel ? 'CANCELLED' : 'LLM_REQUEST_FAILED',
        message,
        retryable:
            e.type != DioExceptionType.cancel &&
            (status == null || status == 429 || status >= 500),
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
