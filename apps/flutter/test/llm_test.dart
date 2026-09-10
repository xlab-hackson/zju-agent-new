import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/application/llm.dart';
import 'package:zju_campus_agent/domain/models.dart';

class StreamAdapter implements HttpClientAdapter {
  StreamAdapter(this.payload, {this.status = 200, this.check});
  final String payload;
  final int status;
  final void Function(RequestOptions)? check;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    check?.call(options);
    // Dio's real native transport returns Uint8List, not List<int> chunks.
    return ResponseBody(
      Stream<Uint8List>.fromIterable(
        utf8.encode(payload).map((b) => Uint8List.fromList([b])),
      ),
      status,
      headers: {
        'content-type': ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const testProvider = {
  'baseUrl': 'https://model.example/v1',
  'model': 'test-model',
  'apiKey': 'test-key',
  'protocol': 'openai',
};
String sse(Object event) => 'data: ${jsonEncode(event)}\n\n';
ModelClient streaming(
  String payload, {
  int status = 200,
  void Function(RequestOptions)? check,
}) => ModelClient(
  client: Dio()
    ..httpClientAdapter = StreamAdapter(payload, status: status, check: check),
);
const request = [
  {'role': 'user', 'content': '你好'},
];

void main() {
  test('Dio native Uint8List chunks decode a complete Chinese reply', () async {
    final client = ModelClient(
      client: Dio()
        ..httpClientAdapter = StreamAdapter(
          'data: {"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}\r\n\r\n'
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
        ),
    );
    final events = await client
        .complete(
          testProvider,
          [
            {'role': 'user', 'content': '你好'},
          ],
          [],
          CancelToken(),
        )
        .toList();
    expect(
      events.where((e) => e.type == 'text').map((e) => e.data['delta']).join(),
      '你好',
    );
    expect(events.last.type, 'message_end');
  });
  test(
    'OpenAI tool name and JSON arguments accumulate across native chunks',
    () async {
      final client = streaming(
        [
          sse({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_1',
                      'function': {
                        'name': 'zju_search_',
                        'arguments': '{"query":"',
                      },
                    },
                  ],
                },
              },
            ],
          }),
          sse({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'name': 'guide', 'arguments': '选课"}'},
                    },
                  ],
                },
                'finish_reason': 'tool_calls',
              },
            ],
          }),
          'data: [DONE]\n\n',
        ].join(),
      );
      final events = await client
          .complete(testProvider, request, [], CancelToken())
          .toList();
      expect(events.first.data['toolCall'], {
        'id': 'call_1',
        'name': 'zju_search_guide',
        'input': {'query': '选课'},
      });
      expect(events.last.type, 'message_end');
    },
  );
  test('Anthropic native text and tool blocks reach message_stop', () async {
    final client = streaming(
      [
        sse({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': '正在查询'},
        }),
        sse({
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'tool_1',
            'name': 'zju_search_guide',
            'input': {},
          },
        }),
        sse({
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"query":"'},
        }),
        sse({
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '选课"}'},
        }),
        sse({'type': 'message_stop'}),
      ].join(),
      check: (options) {
        expect(options.uri.path, '/v1/messages');
        expect(options.headers['x-api-key'], 'test-key');
        expect(options.headers.containsKey('Authorization'), isFalse);
      },
    );
    final events = await client
        .complete(
          {...testProvider, 'protocol': 'anthropic'},
          request,
          [],
          CancelToken(),
        )
        .toList();
    expect(events.first.data['delta'], '正在查询');
    expect(events[1].data['toolCall'], {
      'id': 'tool_1',
      'name': 'zju_search_guide',
      'input': {'query': '选课'},
    });
    expect(events.last.type, 'message_end');
  });
  test(
    'an interrupted response is not reported as a complete answer',
    () async {
      final client = streaming(
        sse({
          'choices': [
            {
              'delta': {'content': '未完成'},
            },
          ],
        }),
      );
      await expectLater(
        client.complete(testProvider, request, [], CancelToken()).toList(),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', 'LLM_STREAM_ERROR'),
        ),
      );
    },
  );
  test(
    'HTTP authentication errors are actionable and never expose response secrets',
    () async {
      final client = streaming('{"error":"secret-key"}', status: 401);
      await expectLater(
        client.complete(testProvider, request, [], CancelToken()).toList(),
        throwsA(
          isA<AppError>()
              .having((e) => e.message, 'HTTP status', contains('401'))
              .having(
                (e) => e.message,
                'redaction',
                isNot(contains('secret-key')),
              ),
        ),
      );
    },
  );
}
