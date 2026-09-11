import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import '../data/database.dart';
import 'campus.dart';
import 'files.dart';
import 'knowledge.dart';
import 'llm.dart';

const _fallbackPrompts = <String, dynamic>{
  'SYSTEM_PROMPT_TPL':
      '你是浙江大学校园智能助手。请基于工具返回的真实数据回答问题。\n\n当前时间：__DATETIME__。__PERIOD__。',
  'GUIDE_RULES':
      '关于浙大校园常识，优先使用知识库工具；检索不到时请如实说明。\n\n知识库章节目录：\n__GUIDE_OUTLINE__',
  'BRIEF_RULES': '请用简洁中文回答，不要输出表格或代码块。',
};

Future<Json> loadPromptCatalog() async {
  try {
    final prompts = object(
      jsonDecode(await rootBundle.loadString('assets/prompts.json')),
    );
    if (text(prompts, 'SYSTEM_PROMPT_TPL').trim().isEmpty ||
        text(prompts, 'GUIDE_RULES').trim().isEmpty) {
      throw const FormatException('提示词缺少必要字段');
    }
    return prompts;
  } catch (_) {
    // A packaged desktop build can briefly miss a newly updated asset during
    // hot restart. Keep chat usable with a minimal local prompt in that case.
    return _fallbackPrompts;
  }
}

class AgentService {
  AgentService(this.campus, this.files, this.guide, {ModelClient? model})
    : model = model ?? ModelClient();
  final CampusService campus;
  final FileService files;
  final GuideIndex guide;
  final ModelClient model;
  AgentDatabase get db => campus.db;
  final Map<String, CancelToken> _active = {};
  void cancel(String id) => _active[id]?.cancel();
  void cancelAll() {
    for (final token in _active.values) {
      token.cancel();
    }
  }

  Future<void> saveMessage(String conversationId, Json message) async {
    final id = const Uuid().v4();
    await db.put('messages', id, {
      'id': id,
      'conversationId': conversationId,
      ...message,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Json>> history(String id) async {
    final result =
        (await db.list(
          'messages',
        )).where((m) => m['conversationId'] == id).toList()..sort(
          (a, b) => text(a, 'createdAt').compareTo(text(b, 'createdAt')),
        );
    return result;
  }

  Future<void> deleteConversation(String id) async {
    cancel(id);
    await db.transaction(() async {
      for (final message in await history(id)) {
        await db.remove('messages', text(message, 'id'));
      }
      for (final c in await db.list('confirmations')) {
        if (c['conversationId'] == id) {
          await db.remove('confirmations', text(c, 'id'));
        }
      }
      await db.remove('conversations', id);
    });
  }

  List<Json> toolDefinitions({bool readOnly = false}) {
    const descriptions = {
      'zju_get_courses': '查询学期内课程列表',
      'zju_get_assignments': '查询作业及截止时间',
      'zju_get_course_materials': '查询课程资料，返回 upload 文件 ID',
      'zju_get_quizzes': '查询课程在线小测',
      'zju_get_upcoming_schedule': '查询未来48小时真实日程与作业',
      'zju_get_daily_schedule': '按校历查询某天真实日程',
      'zju_get_exams': '查询考试安排',
      'zju_get_timetable': '查询课表，指定 date 时按校历投影',
      'zju_get_notices': '查询学校公开通知',
      'zju_get_grades': '查询成绩、学分与绩点',
      'zju_search_guide': '检索浙大新生指引，回答校园常识前先检索',
      'zju_read_guide': '按 doc 路径阅读指引',
      'zju_download_course_material': '下载单个课程文件，需要用户确认',
      'zju_batch_download': '批量下载1至50个文件，只确认一次',
    };
    final result = <Json>[];
    for (final entry in descriptions.entries) {
      if (readOnly && isDownload(entry.key)) continue;
      final properties = <String, dynamic>{}, required = <String>[];
      void string(String name, {bool needed = false}) {
        properties[name] = {'type': 'string'};
        if (needed) required.add(name);
      }

      if ([
        'zju_get_courses',
        'zju_get_assignments',
        'zju_get_exams',
        'zju_get_timetable',
        'zju_get_grades',
      ].contains(entry.key)) {
        string('semesterId');
      }
      if ([
        'zju_get_assignments',
        'zju_get_course_materials',
        'zju_get_quizzes',
      ].contains(entry.key)) {
        string('courseId', needed: entry.key != 'zju_get_assignments');
      }
      if (['zju_get_daily_schedule', 'zju_get_timetable'].contains(entry.key)) {
        string('date');
      }
      if (entry.key == 'zju_search_guide') {
        string('query', needed: true);
        properties['limit'] = {'type': 'integer', 'minimum': 1, 'maximum': 20};
      }
      if (entry.key == 'zju_read_guide') string('doc', needed: true);
      if (entry.key == 'zju_download_course_material') {
        for (final k in ['courseId', 'fileId', 'fileName']) {
          string(k, needed: true);
        }
        string('courseName');
        properties['officePdf'] = {'type': 'boolean'};
      }
      if (entry.key == 'zju_batch_download') {
        properties['files'] = {
          'type': 'array',
          'minItems': 1,
          'maxItems': 50,
          'items': {
            'type': 'object',
            'properties': {
              'courseId': {'type': 'string'},
              'courseName': {'type': 'string'},
              'fileId': {'type': 'string'},
              'fileName': {'type': 'string'},
              'officePdf': {'type': 'boolean'},
            },
            'required': ['courseId', 'fileId', 'fileName'],
            'additionalProperties': false,
          },
        };
        required.add('files');
      }
      result.add({
        'name': entry.key,
        'description': entry.value,
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': required,
          'additionalProperties': false,
        },
      });
    }
    return result;
  }

  static bool isDownload(String name) =>
      ['zju_download_course_material', 'zju_batch_download'].contains(name);
  void validate(String name, Json input) {
    final definitions = toolDefinitions().where((e) => e['name'] == name);
    if (definitions.isEmpty) throw const AppError('TOOL_NOT_FOUND', '工具不存在。');
    final schema = object(definitions.first['parameters']),
        properties = object(schema['properties']);
    if (input.keys.any((k) => !properties.containsKey(k))) {
      throw const AppError('TOOL_INPUT_INVALID', '工具包含不支持的参数。');
    }
    for (final k in schema['required'] as List) {
      if (input[k] == null || input[k] == '') {
        throw const AppError('TOOL_INPUT_INVALID', '工具缺少必要参数。');
      }
    }
    for (final e in input.entries) {
      final type = object(properties[e.key])['type'];
      if ((type == 'string' && e.value is! String) ||
          (type == 'boolean' && e.value is! bool) ||
          (type == 'integer' && e.value is! int) ||
          (type == 'array' && e.value is! List)) {
        throw const AppError('TOOL_INPUT_INVALID', '工具参数类型不正确。');
      }
    }
    if (name == 'zju_batch_download') {
      final batch = rows(input['files']);
      if (batch.isEmpty || batch.length > 50) {
        throw const AppError('TOOL_INPUT_INVALID', '一次批量下载限1至50个文件。');
      }
      for (final file in batch) {
        validate('zju_download_course_material', file);
      }
    }
  }

  DateTime resolveDate(String date) {
    final today = day(beijing(DateTime.now()));
    if (date.isEmpty || ['today', '今天'].contains(date)) return today;
    if (['tomorrow', '明天'].contains(date)) {
      return today.add(const Duration(days: 1));
    }
    if (['yesterday', '昨天'].contains(date)) {
      return today.subtract(const Duration(days: 1));
    }
    final parsed = DateTime.tryParse('${date}T00:00:00Z');
    if (parsed == null) {
      throw const AppError('TOOL_INPUT_INVALID', '日期格式应为 YYYY-MM-DD。');
    }
    return parsed;
  }

  Future<Object?> execute(String name, Json input) async {
    validate(name, input);
    final semester = text(
      input,
      'semesterId',
      academicSemester(beijing(DateTime.now())),
    );
    switch (name) {
      case 'zju_get_courses':
        return campus.courses(semesterId: semester);
      case 'zju_get_assignments':
        return campus.assignments(
          courseId: input['courseId'] as String?,
          semesterId: semester,
        );
      case 'zju_get_course_materials':
        return campus.materials(text(input, 'courseId'));
      case 'zju_get_quizzes':
        return campus.quizzes(text(input, 'courseId'));
      case 'zju_get_upcoming_schedule':
        return campus.upcoming();
      case 'zju_get_daily_schedule':
        return campus.daily(resolveDate(text(input, 'date')));
      case 'zju_get_exams':
        return campus.exams(semester);
      case 'zju_get_timetable':
        return input['date'] != null
            ? campus.daily(resolveDate(text(input, 'date')))
            : (await campus.timetable(
                semester,
              )).map((e) => e.toJson()).toList();
      case 'zju_get_notices':
        return campus.notices();
      case 'zju_get_grades':
        return campus.grades(semester);
      case 'zju_search_guide':
        return guide.search(
          text(input, 'query'),
          limit: integer(input['limit'], 5),
        );
      case 'zju_read_guide':
        return guide.read(text(input, 'doc'));
      case 'zju_download_course_material':
        return files.download(input);
      case 'zju_batch_download':
        final result = <Json>[];
        for (final file in rows(input['files'])) {
          try {
            result.add({'ok': true, 'data': await files.download(file)});
          } catch (_) {
            result.add({
              'ok': false,
              'fileName': file['fileName'],
              'error': '下载失败',
            });
          }
        }
        return result;
      default:
        throw const AppError('TOOL_NOT_FOUND', '工具不存在。');
    }
  }

  Stream<AgentEvent> chat(
    String message, {
    String? conversationId,
    bool widget = false,
  }) async* {
    final id = conversationId ?? const Uuid().v4();
    if (_active.containsKey(id)) {
      yield const AgentEvent('error', {'code': 'BUSY', 'message': '当前会话正在回答。'});
      return;
    }
    if (!widget &&
        (await db.list(
          'confirmations',
        )).any((c) => c['conversationId'] == id && c['status'] == 'pending')) {
      yield const AgentEvent('error', {
        'code': 'CONFIRMATION_PENDING',
        'message': '请先处理待确认操作。',
      });
      return;
    }
    if (!widget) {
      if (await db.get('conversations', id) == null) {
        await db.put('conversations', id, {
          'id': id,
          'title': message.length > 32 ? message.substring(0, 32) : message,
        });
      }
      await saveMessage(id, {'role': 'user', 'content': message});
    }
    yield AgentEvent('conversation', {'conversationId': id});
    final messages = widget
        ? <Json>[
            {'role': 'user', 'content': message},
          ]
        : await _wireHistory(id);
    yield* _run(id, messages, widget: widget);
  }

  Future<List<Json>> _wireHistory(String id) async => (await history(id))
      .map(
        (m) => {
          'role': m['role'],
          'content': m['content'] ?? '',
          if (m['tool_calls'] != null) 'tool_calls': m['tool_calls'],
          if (m['tool_call_id'] != null) 'tool_call_id': m['tool_call_id'],
          if (m['metadata'] is Map &&
              (m['metadata'] as Map)['toolCalls'] is List)
            'tool_calls': rows((m['metadata'] as Map)['toolCalls'])
                .map(
                  (c) => {
                    'id': c['id'],
                    'type': 'function',
                    'function': {
                      'name': c['name'],
                      'arguments': jsonEncode(c['input']),
                    },
                  },
                )
                .toList(),
          if (m['metadata'] is Map &&
              (m['metadata'] as Map)['toolCallId'] != null)
            'tool_call_id': (m['metadata'] as Map)['toolCallId'],
        },
      )
      .toList();
  Stream<AgentEvent> _run(
    String id,
    List<Json> messages, {
    bool widget = false,
    int round = 0,
  }) async* {
    final token = CancelToken();
    _active[id] = token;
    var stage = '读取模型配置';
    try {
      final settings = await db.get('settings', 'app') ?? {};
      final providerConfig = await campus.session.secrets.read('providers');
      final providers = rows(
        providerConfig?['items'] ?? [],
      ).where((p) => p['enabled'] != false);
      if (providers.isEmpty) {
        throw const AppError('LLM_CONFIG_INVALID', '请先配置模型来源。');
      }
      final provider = providers.first;
      stage = '加载聊天提示词';
      final prompts = await loadPromptCatalog();
      final system =
          '${text(prompts, 'SYSTEM_PROMPT_TPL').replaceAll('__DATETIME__', beijing(DateTime.now()).toIso8601String()).replaceAll('__PERIOD__', academicSemester(beijing(DateTime.now())))}\n${text(prompts, 'GUIDE_RULES').replaceAll('__GUIDE_OUTLINE__', guide.outline)}\n称呼用户：${settings['nickname'] ?? ''}\n用户自述：${settings['personaPrompt'] ?? ''}${widget ? '\n${prompts['BRIEF_RULES']}' : ''}';
      for (var r = round; r < 8; r++) {
        var content = '';
        final calls = <Json>[];
        stage = '接收模型回答';
        await for (final event in model.complete(
          provider,
          [
            {'role': 'system', 'content': system},
            ...messages,
          ],
          toolDefinitions(readOnly: widget),
          token,
        )) {
          if (event.type == 'text') content += text(event.data, 'delta');
          if (event.type == 'tool_call_end') {
            calls.add(object(event.data['toolCall']));
          }
          yield event;
        }
        final assistant = <String, dynamic>{
          'role': 'assistant',
          'content': content,
          if (calls.isNotEmpty)
            'tool_calls': calls
                .map(
                  (c) => {
                    'id': c['id'],
                    'type': 'function',
                    'function': {
                      'name': c['name'],
                      'arguments': jsonEncode(c['input']),
                    },
                  },
                )
                .toList(),
        };
        messages.add(assistant);
        stage = '保存聊天记录';
        if (!widget) await saveMessage(id, assistant);
        if (calls.isEmpty) {
          yield AgentEvent('done', {'conversationId': id, 'paused': false});
          return;
        }
        for (var index = 0; index < calls.length; index++) {
          stage = '处理工具调用';
          final call = calls[index],
              name = text(call, 'name'),
              input = object(call['input']);
          validate(name, input);
          if (isDownload(name)) {
            if (widget) throw const AppError('TOOL_FORBIDDEN', '快捷问答只允许查询。');
            final confirmation = const Uuid().v4();
            await db.put('confirmations', confirmation, {
              'id': confirmation,
              'conversationId': id,
              'calls': calls.sublist(index),
              'round': r + 1,
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
              'status': 'pending',
            });
            yield AgentEvent('confirmation_required', {
              'confirmationId': confirmation,
              'conversationId': id,
              'toolName': name,
              'summary': '下载课程资料',
              'inputPreview': input,
            });
            yield AgentEvent('done', {'conversationId': id, 'paused': true});
            return;
          }
          final result = await _toolResult(call);
          final message = {
            'role': 'tool',
            'tool_call_id': call['id'],
            'content': jsonEncode(result),
          };
          messages.add(message);
          if (!widget) await saveMessage(id, message);
          yield AgentEvent('tool_result', {
            'toolCallId': call['id'],
            'result': result,
            'ok': result['ok'],
          });
        }
      }
      throw const AppError('AGENT_MAX_ROUNDS', '已达到本次工具调用轮数上限，请继续提问。');
    } on AppError catch (e) {
      yield AgentEvent('error', {'code': e.code, 'message': e.message});
    } catch (e) {
      yield AgentEvent('error', {
        'code': 'AGENT_ERROR',
        // Exception payloads may include request headers, keys or chat text.
        'message': '$stage失败（${e.runtimeType}），请重试。',
      });
    } finally {
      _active.remove(id);
    }
  }

  Future<Json> _toolResult(Json call) async {
    try {
      return {
        'ok': true,
        'data': await execute(text(call, 'name'), object(call['input'])),
      };
    } on AppError catch (e) {
      return {
        'ok': false,
        'error': {'code': e.code, 'message': e.message},
      };
    } catch (_) {
      return {
        'ok': false,
        'error': {'code': 'TOOL_FAILED', 'message': '工具执行失败。'},
      };
    }
  }

  Stream<AgentEvent> confirm(
    String id,
    String confirmationId,
    bool approved,
  ) async* {
    Json? pending;
    await db.transaction(() async {
      final value = await db.get('confirmations', confirmationId);
      if (value == null ||
          value['conversationId'] != id ||
          value['status'] != 'pending') {
        return;
      }
      pending = value;
      await db.put('confirmations', confirmationId, {
        ...value,
        'status': 'consumed',
      });
    });
    if (pending == null) {
      yield const AgentEvent('error', {
        'code': 'CONFIRMATION_INVALID',
        'message': '确认已处理或不属于此会话。',
      });
      return;
    }
    final expired = DateTime.parse(
      text(pending!, 'expiresAt'),
    ).isBefore(DateTime.now());
    final calls = rows(pending!['calls']);
    // All remaining download calls share the explicit confirmation preview.
    for (final call in calls) {
      final allowed = approved && !expired;
      final result = isDownload(text(call, 'name')) && !allowed
          ? <String, dynamic>{
              'ok': false,
              'error': {
                'code': expired ? 'CONFIRMATION_EXPIRED' : 'USER_REJECTED',
                'message': expired ? '确认已过期' : '用户拒绝',
              },
            }
          : await _toolResult(call);
      await saveMessage(id, {
        'role': 'tool',
        'tool_call_id': call['id'],
        'content': jsonEncode(result),
      });
      final auditId = const Uuid().v4();
      await db.put('audit', auditId, {
        'id': auditId,
        'action': call['name'],
        'confirmed': allowed,
        'result': result['ok'] == true ? 'ok' : 'failed',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      yield AgentEvent('tool_result', {
        'toolCallId': call['id'],
        'result': result,
        'ok': result['ok'],
      });
    }
    yield* _run(id, await _wireHistory(id), round: integer(pending!['round']));
  }
}
