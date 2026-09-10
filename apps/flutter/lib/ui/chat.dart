import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../application/services.dart';
import '../domain/models.dart';
import 'theme.dart';

Future<void> openChat(
  BuildContext context,
  AppServices services, {
  String? prompt,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completion = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FloatingChatOverlay(
      services: services,
      prompt: prompt,
      onClose: () {
        if (entry.mounted) entry.remove();
        if (!completion.isCompleted) completion.complete();
      },
    ),
  );
  overlay.insert(entry);
  return completion.future;
}

class _FloatingChatOverlay extends StatefulWidget {
  const _FloatingChatOverlay({
    required this.services,
    required this.onClose,
    this.prompt,
  });
  final AppServices services;
  final String? prompt;
  final VoidCallback onClose;

  @override
  State<_FloatingChatOverlay> createState() => _FloatingChatOverlayState();
}

enum _ResizeEdge {
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _FloatingChatOverlayState extends State<_FloatingChatOverlay> {
  Offset? position;
  Size? windowSize;

  void resizeWindow(
    DragUpdateDetails details,
    _ResizeEdge edge, {
    required BoxConstraints constraints,
    required double minWidth,
    required double minHeight,
    required double width,
    required double height,
    required double left,
    required double top,
  }) {
    final currentSize = windowSize ?? Size(width, height);
    final currentLeft = position?.dx ?? left;
    final currentTop = position?.dy ?? top;
    var nextLeft = currentLeft;
    var nextTop = currentTop;
    var nextRight = currentLeft + currentSize.width;
    var nextBottom = currentTop + currentSize.height;

    if (edge == _ResizeEdge.left ||
        edge == _ResizeEdge.topLeft ||
        edge == _ResizeEdge.bottomLeft) {
      nextLeft = (currentLeft + details.delta.dx)
          .clamp(0.0, nextRight - minWidth)
          .toDouble();
    }
    if (edge == _ResizeEdge.right ||
        edge == _ResizeEdge.topRight ||
        edge == _ResizeEdge.bottomRight) {
      nextRight = (nextRight + details.delta.dx)
          .clamp(currentLeft + minWidth, constraints.maxWidth)
          .toDouble();
    }
    if (edge == _ResizeEdge.top ||
        edge == _ResizeEdge.topLeft ||
        edge == _ResizeEdge.topRight) {
      nextTop = (currentTop + details.delta.dy)
          .clamp(0.0, nextBottom - minHeight)
          .toDouble();
    }
    if (edge == _ResizeEdge.bottom ||
        edge == _ResizeEdge.bottomLeft ||
        edge == _ResizeEdge.bottomRight) {
      nextBottom = (nextBottom + details.delta.dy)
          .clamp(currentTop + minHeight, constraints.maxHeight)
          .toDouble();
    }

    final nextWidth = nextRight - nextLeft;
    final nextHeight = nextBottom - nextTop;
    setState(() {
      windowSize = Size(nextWidth, nextHeight);
      position = Offset(nextLeft, nextTop);
    });
  }

  Widget resizeZone({
    required _ResizeEdge edge,
    required double left,
    required double top,
    required double width,
    required double height,
    required MouseCursor cursor,
    required ValueChanged<DragUpdateDetails> onResize,
  }) => Positioned(
    left: left,
    top: top,
    width: width,
    height: height,
    child: MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onResize,
        child: const SizedBox.expand(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    minimum: const EdgeInsets.all(16),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 800;
        final minWidth = math.min(320.0, constraints.maxWidth);
        final minHeight = math.min(420.0, constraints.maxHeight);
        final initialWidth = math.min(520.0, constraints.maxWidth);
        final initialHeight = math.min(
          720.0,
          math.max(minHeight, constraints.maxHeight * (narrow ? .82 : .78)),
        );
        final width = (windowSize?.width ?? initialWidth)
            .clamp(minWidth, constraints.maxWidth)
            .toDouble();
        final height = (windowSize?.height ?? initialHeight)
            .clamp(minHeight, constraints.maxHeight)
            .toDouble();
        final maxLeft = math.max(0.0, constraints.maxWidth - width);
        final maxTop = math.max(0.0, constraints.maxHeight - height);
        final left = (position?.dx ?? maxLeft).clamp(0.0, maxLeft).toDouble();
        final top = (position?.dy ?? maxTop).clamp(0.0, maxTop).toDouble();

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: SizedBox(
                width: width,
                height: height,
                child: Material(
                  color: paperCard,
                  elevation: 16,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: BorderSide(
                      color: gold.withValues(alpha: .55),
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ChatPane(
                        services: widget.services,
                        prompt: widget.prompt,
                        onClose: widget.onClose,
                        onHeaderDrag: (details) {
                          final current = position ?? Offset(maxLeft, maxTop);
                          setState(() {
                            position = Offset(
                              (current.dx + details.delta.dx)
                                  .clamp(0.0, maxLeft)
                                  .toDouble(),
                              (current.dy + details.delta.dy)
                                  .clamp(0.0, maxTop)
                                  .toDouble(),
                            );
                          });
                        },
                      ),
                      resizeZone(
                        edge: _ResizeEdge.left,
                        left: 0,
                        top: 16,
                        width: 12,
                        height: math.max(1, height - 32),
                        cursor: SystemMouseCursors.resizeLeftRight,
                        onResize: (details) => resizeWindow(
                          details,
                          _ResizeEdge.left,
                          constraints: constraints,
                          minWidth: minWidth,
                          minHeight: minHeight,
                          width: width,
                          height: height,
                          left: left,
                          top: top,
                        ),
                      ),
                      resizeZone(
                        edge: _ResizeEdge.right,
                        left: width - 12,
                        top: 16,
                        width: 12,
                        height: math.max(1, height - 32),
                        cursor: SystemMouseCursors.resizeLeftRight,
                        onResize: (details) => resizeWindow(
                          details,
                          _ResizeEdge.right,
                          constraints: constraints,
                          minWidth: minWidth,
                          minHeight: minHeight,
                          width: width,
                          height: height,
                          left: left,
                          top: top,
                        ),
                      ),
                      resizeZone(
                        edge: _ResizeEdge.top,
                        left: 16,
                        top: 0,
                        width: math.max(1, width - 32),
                        height: 12,
                        cursor: SystemMouseCursors.resizeUpDown,
                        onResize: (details) => resizeWindow(
                          details,
                          _ResizeEdge.top,
                          constraints: constraints,
                          minWidth: minWidth,
                          minHeight: minHeight,
                          width: width,
                          height: height,
                          left: left,
                          top: top,
                        ),
                      ),
                      resizeZone(
                        edge: _ResizeEdge.bottom,
                        left: 16,
                        top: height - 12,
                        width: math.max(1, width - 32),
                        height: 12,
                        cursor: SystemMouseCursors.resizeUpDown,
                        onResize: (details) => resizeWindow(
                          details,
                          _ResizeEdge.bottom,
                          constraints: constraints,
                          minWidth: minWidth,
                          minHeight: minHeight,
                          width: width,
                          height: height,
                          left: left,
                          top: top,
                        ),
                      ),
                      resizeZone(
                        edge: _ResizeEdge.topLeft,
                        left: 0,
                        top: 0,
                        width: 16,
                        height: 16,
                        cursor: SystemMouseCursors.resizeUpLeftDownRight,
                        onResize: (details) => resizeWindow(
                          details,
                          _ResizeEdge.topLeft,
                          constraints: constraints,
                          minWidth: minWidth,
                          minHeight: minHeight,
                          width: width,
                          height: height,
                          left: left,
                          top: top,
                        ),
                      ),
                      resizeZone(
                        edge: _ResizeEdge.topRight,
                        left: width - 16,
                        top: 0,
                        width: 16,
                        height: 16,
                        cursor: SystemMouseCursors.resizeUpRightDownLeft,
                        onResize: (details) => resizeWindow(
                          details,
                          _ResizeEdge.topRight,
                          constraints: constraints,
                          minWidth: minWidth,
                          minHeight: minHeight,
                          width: width,
                          height: height,
                          left: left,
                          top: top,
                        ),
                      ),
                      resizeZone(
                        edge: _ResizeEdge.bottomLeft,
                        left: 0,
                        top: height - 16,
                        width: 16,
                        height: 16,
                        cursor: SystemMouseCursors.resizeUpRightDownLeft,
                        onResize: (details) => resizeWindow(
                          details,
                          _ResizeEdge.bottomLeft,
                          constraints: constraints,
                          minWidth: minWidth,
                          minHeight: minHeight,
                          width: width,
                          height: height,
                          left: left,
                          top: top,
                        ),
                      ),
                      resizeZone(
                        edge: _ResizeEdge.bottomRight,
                        left: width - 16,
                        top: height - 16,
                        width: 16,
                        height: 16,
                        cursor: SystemMouseCursors.resizeUpLeftDownRight,
                        onResize: (details) => resizeWindow(
                          details,
                          _ResizeEdge.bottomRight,
                          constraints: constraints,
                          minWidth: minWidth,
                          minHeight: minHeight,
                          width: width,
                          height: height,
                          left: left,
                          top: top,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

const _quickPrompts = [
  ('今天有什么课？', '今天有什么课？请列出上课时间和地点。'),
  ('最近有什么作业要交？', '最近有什么作业要交？请按截止时间排序。'),
  ('查一下这学期的考试安排', '查一下这学期的考试安排和考场地点。'),
  ('总结本学期的所有课程', '总结一下我本学期的所有课程和学分情况。'),
];

class ChatPane extends StatefulWidget {
  const ChatPane({
    super.key,
    required this.services,
    this.prompt,
    this.onHeaderDrag,
    this.onClose,
  });
  final AppServices services;
  final String? prompt;
  final ValueChanged<DragUpdateDetails>? onHeaderDrag;
  final VoidCallback? onClose;
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

  void insertNewline() {
    final value = input.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start.clamp(0, value.text.length);
    final end = selection.end.clamp(start, value.text.length);
    input.value = value.copyWith(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  KeyEventResult handleInputKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      final keyboard = HardwareKeyboard.instance;
      if (keyboard.isControlPressed || keyboard.isMetaPressed) {
        insertNewline();
      } else {
        unawaited(send());
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

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
  Widget build(BuildContext context) {
    final header = Padding(
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
            onPressed: widget.onClose ?? () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
    return Column(
      children: [
        widget.onHeaderDrag == null
            ? header
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: widget.onHeaderDrag,
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: header,
                ),
              ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (messages.isEmpty && !busy) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 35),
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
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in _quickPrompts)
                      ActionChip(
                        label: Text(item.$1),
                        avatar: const Icon(Icons.arrow_upward, size: 14),
                        onPressed: busy
                            ? null
                            : () {
                                input.text = item.$2;
                                input.selection = TextSelection.collapsed(
                                  offset: input.text.length,
                                );
                                unawaited(send());
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              for (final m in messages.where((m) {
                final role = m['role'];
                return (role == 'user' || role == 'assistant') &&
                    text(m, 'content').trim().isNotEmpty;
              }))
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
              if (response.trim().isNotEmpty)
                Paper(child: MarkdownBody(data: response)),
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
                child: Focus(
                  onKeyEvent: handleInputKey,
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => unawaited(send()),
                    decoration: const InputDecoration(
                      hintText: 'Enter 发送，Ctrl+Enter 换行',
                    ),
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
}
