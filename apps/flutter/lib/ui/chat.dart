import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../application/services.dart';
import '../domain/models.dart';
import 'theme.dart';

Future<void> openChat(
  BuildContext context,
  AppServices services, {
  String? prompt,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: paper,
  constraints: const BoxConstraints(maxWidth: 900),
  builder: (context) => FractionallySizedBox(
    heightFactor: .92,
    child: ChatPane(services: services, prompt: prompt),
  ),
);

class ChatPane extends StatefulWidget {
  const ChatPane({super.key, required this.services, this.prompt});
  final AppServices services;
  final String? prompt;
  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final input = TextEditingController();
  String? conversationId;
  List<Json> messages = [];
  List<Json> pending = [];
  String response = '', error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    input.text = widget.prompt ?? '';
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    if (conversationId == null) return;
    final history = await widget.services.agent.history(conversationId!);
    final confirmations = (await widget.services.db.list('confirmations'))
        .where(
          (c) =>
              c['conversationId'] == conversationId && c['status'] == 'pending',
        )
        .toList();
    if (mounted) {
      setState(() {
        messages = history;
        pending = confirmations;
      });
    }
  }

  Future<void> consume(Stream<AgentEvent> events) async {
    setState(() {
      busy = true;
      error = '';
      response = '';
    });
    try {
      await for (final event in events) {
        if (!mounted) return;
        setState(() {
          if (event.type == 'conversation') {
            conversationId = text(event.data, 'conversationId');
          }
          if (event.type == 'text') response += text(event.data, 'delta');
          if (event.type == 'error') error = text(event.data, 'message');
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '请求未完成，请重试。');
    } finally {
      if (mounted) {
        await reload();
        setState(() {
          busy = false;
          response = '';
        });
      }
    }
  }

  Future<void> send() async {
    if (busy || input.text.trim().isEmpty) return;
    final message = input.text.trim();
    input.clear();
    setState(() => messages.add({'role': 'user', 'content': message}));
    await consume(
      widget.services.agent.chat(message, conversationId: conversationId),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: gold),
            const SizedBox(width: 10),
            const Text(
              '求是 · 问学',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              tooltip: '历史会话',
              onPressed: busy
                  ? null
                  : () async {
                      final conversations = await widget.services.db.list(
                        'conversations',
                      );
                      if (!context.mounted) return;
                      final selected = await showDialog<String>(
                        context: context,
                        builder: (ctx) => SimpleDialog(
                          title: const Text('历史会话'),
                          children: [
                            for (final c in conversations)
                              ListTile(
                                title: Text(text(c, 'title')),
                                onTap: () => Navigator.pop(ctx, text(c, 'id')),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    await widget.services.agent
                                        .deleteConversation(text(c, 'id'));
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                ),
                              ),
                            if (conversations.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('暂无会话'),
                              ),
                          ],
                        ),
                      );
                      if (selected != null) {
                        conversationId = selected;
                        await reload();
                      }
                    },
              icon: const Icon(Icons.history),
            ),
            IconButton(
              tooltip: '新对话',
              onPressed: busy
                  ? null
                  : () => setState(() {
                      conversationId = null;
                      messages = [];
                      pending = [];
                      error = '';
                    }),
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (messages.isEmpty && !busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 45),
                child: Column(
                  children: [
                    Icon(Icons.menu_book, size: 42, color: blue),
                    SizedBox(height: 16),
                    Text(
                      '课程、作业、考试与校园生活\n有疑问，随时问学。',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            for (final m in messages.where(
              (m) => m['role'] == 'user' || m['role'] == 'assistant',
            ))
              Paper(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['role'] == 'user' ? '我' : '求是书院',
                      style: const TextStyle(
                        color: gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    MarkdownBody(data: text(m, 'content'), selectable: true),
                  ],
                ),
              ),
            if (response.isNotEmpty) Paper(child: MarkdownBody(data: response)),
            if (busy) const LinearProgressIndicator(),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error, style: const TextStyle(color: seal)),
              ),
            for (final c in pending)
              Paper(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '下载操作需要确认',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final call in rows(c['calls']))
                      Text(
                        '${call['name']}\n${const JsonEncoder.withIndent('  ').convert(call['input'])}',
                      ),
                    const Text('确认有效期为 5 分钟。'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => consume(
                                  widget.services.agent.confirm(
                                    conversationId!,
                                    text(c, 'id'),
                                    true,
                                  ),
                                ),
                          child: const Text('确认下载'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => consume(
                                  widget.services.agent.confirm(
                                    conversationId!,
                                    text(c, 'id'),
                                    false,
                                  ),
                                ),
                          child: const Text('拒绝'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          10,
          14,
          14 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 5,
                onSubmitted: (_) => send(),
                decoration: const InputDecoration(
                  hintText: '问问接下来的课程、作业或校园生活…',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: busy
                  ? () => widget.services.agent.cancel(conversationId ?? '')
                  : send,
              icon: Icon(busy ? Icons.stop : Icons.arrow_upward),
            ),
          ],
        ),
      ),
    ],
  );
}
