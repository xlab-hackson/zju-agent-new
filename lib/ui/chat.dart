import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../application/services.dart';
import '../domain/models.dart';
import 'avatar.dart';
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
  Offset? minimizedPosition;
  Size? windowSize;
  bool minimized = false;

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
  Widget build(BuildContext context) {
    const launcherSize = 64.0;
    final viewport = MediaQuery.sizeOf(context);
    final maxMinimizedLeft = math.max(0.0, viewport.width - launcherSize);
    final maxMinimizedTop = math.max(0.0, viewport.height - launcherSize);
    final defaultMinimizedPosition = Offset(
      (viewport.width - launcherSize - 24)
          .clamp(0.0, maxMinimizedLeft)
          .toDouble(),
      (viewport.height - launcherSize - 24)
          .clamp(0.0, maxMinimizedTop)
          .toDouble(),
    );
    return Stack(
      children: [
        Offstage(
          offstage: minimized,
          child: SafeArea(
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
                                onMinimize: () => setState(() => minimized = true),
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
          ),
        ),
        if (minimized)
          _MinimizedChatLauncher(
            launcherSize: launcherSize,
            defaultPosition: defaultMinimizedPosition,
            position: minimizedPosition,
            maxLeft: maxMinimizedLeft,
            maxTop: maxMinimizedTop,
            onPositionChanged: (next) => minimizedPosition = next,
            onTap: () => setState(() => minimized = false),
          ),
      ],
    );
  }
}

class _MinimizedChatLauncher extends StatefulWidget {
  const _MinimizedChatLauncher({
    required this.launcherSize,
    required this.defaultPosition,
    required this.position,
    required this.maxLeft,
    required this.maxTop,
    required this.onPositionChanged,
    required this.onTap,
  });

  final double launcherSize;
  final Offset defaultPosition;
  final Offset? position;
  final double maxLeft;
  final double maxTop;
  final ValueChanged<Offset> onPositionChanged;
  final VoidCallback onTap;

  @override
  State<_MinimizedChatLauncher> createState() => _MinimizedChatLauncherState();
}

class _MinimizedChatLauncherState extends State<_MinimizedChatLauncher> {
  late Offset currentPosition;

  @override
  void initState() {
    super.initState();
    currentPosition = clampPosition(widget.position ?? widget.defaultPosition);
  }

  @override
  void didUpdateWidget(covariant _MinimizedChatLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = clampPosition(currentPosition);
    if (next != currentPosition) {
      currentPosition = next;
      widget.onPositionChanged(next);
    }
  }

  Offset clampPosition(Offset value) => Offset(
    value.dx.clamp(0.0, widget.maxLeft).toDouble(),
    value.dy.clamp(0.0, widget.maxTop).toDouble(),
  );

  @override
  Widget build(BuildContext context) => Positioned(
    left: currentPosition.dx,
    top: currentPosition.dy,
    child: GestureDetector(
      onTap: widget.onTap,
      onPanUpdate: (details) {
        final next = clampPosition(currentPosition + details.delta);
        if (next == currentPosition) return;
        setState(() => currentPosition = next);
        widget.onPositionChanged(next);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Container(
          width: widget.launcherSize,
          height: widget.launcherSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: seal,
            borderRadius: BorderRadius.circular(7),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4d0e1c38),
                offset: Offset(3, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: const Text(
            '问学\n⌘K',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: paperCard,
              fontSize: 16,
              height: 1.1,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ),
  );
}

const _chatHeader = Color(0xff0e1c38);

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
    this.onMinimize,
  });
  final AppServices services;
  final String? prompt;
  final ValueChanged<DragUpdateDetails>? onHeaderDrag;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final input = TextEditingController();
  final scrollController = ScrollController();
  String? conversationId;
  String avatarDataUrl = '';
  List<Json> messages = [];
  List<Json> conversations = [];
  List<Json> pending = [];
  List<Json> liveTools = [];
  String response = '', error = '';
  bool busy = false, showConversations = false;
  int requestVersion = 0;

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
    unawaited(loadInitial());
  }

  @override
  void dispose() {
    input.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> loadInitial() async {
    final version = requestVersion;
    final nextConversations = await widget.services.db.list('conversations');
    final settings = await widget.services.db.get('settings', 'app') ?? {};
    if (!mounted || version != requestVersion) return;
    final firstId = conversationId == null && nextConversations.isNotEmpty
        ? text(nextConversations.first, 'id')
        : null;
    setState(() {
      conversations = nextConversations;
      avatarDataUrl = text(settings, 'avatarDataUrl');
      if (firstId != null) conversationId = firstId;
    });
    if (firstId != null) await reload();
  }

  Future<void> loadConversations() async {
    final next = await widget.services.db.list('conversations');
    if (!mounted) return;
    setState(() => conversations = next);
  }

  Future<void> reload() async {
    if (conversationId == null) return;
    try {
      final id = conversationId!;
      final history = await widget.services.agent.history(id);
      final confirmations = (await widget.services.db.list('confirmations'))
          .where(
            (c) => c['conversationId'] == id && c['status'] == 'pending',
          )
          .toList();
      if (mounted && conversationId == id) {
        setState(() {
          messages = history;
          pending = confirmations;
        });
        scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => error = '会话加载失败，请重试。');
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void startNewConversation() {
    requestVersion++;
    if (conversationId != null && busy) {
      widget.services.agent.cancel(conversationId!);
    }
    input.clear();
    setState(() {
      conversationId = null;
      messages = [];
      pending = [];
      liveTools = [];
      response = '';
      error = '';
      busy = false;
      showConversations = false;
    });
    scrollToBottom();
  }

  Future<void> selectConversation(String id) async {
    if (busy) return;
    setState(() {
      conversationId = id;
      showConversations = false;
      error = '';
      response = '';
      liveTools = [];
    });
    await reload();
  }

  Future<void> deleteConversation(String id) async {
    if (conversationId == id) startNewConversation();
    await widget.services.agent.deleteConversation(id);
    await loadConversations();
  }

  Future<void> consume(Stream<AgentEvent> events) async {
    final version = ++requestVersion;
    setState(() {
      busy = true;
      error = '';
      response = '';
      liveTools = [];
    });
    try {
      await for (final event in events) {
        if (!mounted || version != requestVersion) return;
        setState(() {
          if (event.type == 'conversation') {
            conversationId = text(event.data, 'conversationId');
          }
          if (event.type == 'text') response += text(event.data, 'delta');
          if (event.type == 'error') error = text(event.data, 'message');
          if (event.type == 'tool_call_end') {
            final call = object(event.data['toolCall']);
            liveTools = [
              ...liveTools,
              {'id': text(call, 'id'), 'name': text(call, 'name')},
            ];
          }
          if (event.type == 'tool_result') {
            final id = text(event.data, 'toolCallId');
            liveTools = liveTools
                .map(
                  (tool) => text(tool, 'id') == id
                      ? {...tool, 'status': event.data['ok'] == true ? 'done' : 'failed'}
                      : tool,
                )
                .toList();
          }
        });
        scrollToBottom();
      }
    } catch (_) {
      if (mounted && version == requestVersion) {
        setState(() => error = '请求未完成，请重试。');
      }
    } finally {
      if (mounted && version == requestVersion) {
        await reload();
        await loadConversations();
        setState(() {
          busy = false;
          response = '';
          liveTools = [];
        });
        scrollToBottom();
      }
    }
  }

  Future<void> send() async {
    if (busy || input.text.trim().isEmpty) return;
    final message = input.text.trim();
    input.clear();
    setState(() => messages.add({'role': 'user', 'content': message}));
    await consume(
      widget.services.agent.chat(
        message,
        conversationId: conversationId,
        pageContext: widget.services.currentPageContext,
      ),
    );
  }

  String conversationTitle() {
    for (final conversation in conversations) {
      if (text(conversation, 'id') == conversationId) {
        return text(conversation, 'title', '新对话');
      }
    }
    return '新对话';
  }

  String toolLabel(String name) {
    const labels = {
      'zju_get_courses': '查询课程',
      'zju_get_assignments': '查询作业',
      'zju_get_course_materials': '查询课件',
      'zju_get_quizzes': '查询小测',
      'zju_get_exams': '查询考试',
      'zju_get_timetable': '查询课表',
      'zju_get_upcoming_schedule': '查询日程流',
      'zju_get_daily_schedule': '查询当日日程',
      'zju_get_grades': '查询成绩',
      'zju_get_notices': '查询通知公告',
      'zju_download_course_material': '下载课件',
    };
    return labels[name] ?? name;
  }

  String toolName(Json call) {
    final function = call['function'];
    if (function is Map) return '${function['name'] ?? ''}';
    return text(call, 'name');
  }

  TextStyle get bodyStyle => const TextStyle(
    color: ink,
    fontSize: 14,
    height: 1.65,
    fontFamily: 'NotoSerifSC',
  );

  Widget markdown(String value) => MarkdownBody(
    data: value,
    selectable: true,
    styleSheet: MarkdownStyleSheet(p: bodyStyle),
  );

  Widget bubble(
    String content, {
    required bool user,
    required double maxWidth,
  }) {
    final bubbleMaxWidth = user && avatarDataUrl.isNotEmpty
        ? math.max(120.0, maxWidth - 48)
        : maxWidth;
    final child = Container(
      constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: user ? blue : paperCard,
        border: user ? null : Border.all(color: ink.withValues(alpha: .14)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(5),
          topRight: const Radius.circular(5),
          bottomLeft: Radius.circular(user ? 5 : 2),
          bottomRight: Radius.circular(user ? 2 : 5),
        ),
        boxShadow: [
          BoxShadow(
            color: seal.withValues(alpha: .95),
            offset: const Offset(3, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: user
          ? Text(
              content,
              style: const TextStyle(
                color: paperCard,
                fontSize: 14,
                height: 1.55,
              ),
            )
          : markdown(content),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!user) child,
          if (user) ...[
            child,
            if (avatarDataUrl.isNotEmpty) ...[
              const SizedBox(width: 8),
              UserAvatar(dataUrl: avatarDataUrl, radius: 18),
            ],
          ],
        ],
      ),
    );
  }

  Widget toolStep(Json tool) {
    final status = text(tool, 'status', 'running');
    final icon = status == 'done'
        ? const Icon(Icons.check, size: 14, color: Color(0xff2f7d32))
        : status == 'failed'
        ? const Icon(Icons.close, size: 14, color: seal)
        : const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: ink),
          );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: paperCard,
        border: Border.all(color: ink.withValues(alpha: .14)),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: seal.withValues(alpha: .9),
            offset: const Offset(2, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Text(
            toolLabel(text(tool, 'name')),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget historyMessage(Json message, double maxWidth) {
    final role = text(message, 'role');
    if (role == 'tool' || role == 'system') return const SizedBox.shrink();
    final content = text(message, 'content').trim();
    final calls = message['tool_calls'];
    if (role == 'assistant' && content.isEmpty && calls is List) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final raw in calls)
              if (raw is Map)
                Container(
                  margin: const EdgeInsets.only(bottom: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: paper.withValues(alpha: .6),
                    border: Border.all(color: ink.withValues(alpha: .1)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, size: 13, color: Color(0xff2f7d32)),
                      const SizedBox(width: 6),
                      Text(
                        toolLabel(toolName(object(raw))),
                        style: const TextStyle(fontSize: 12, color: ink),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      );
    }
    if (content.isEmpty) return const SizedBox.shrink();
    return bubble(content, user: role == 'user', maxWidth: maxWidth);
  }

  Widget welcome(double maxWidth) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 8),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: blue.withValues(alpha: .05),
            border: Border.all(color: blue, width: 2),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: seal.withValues(alpha: .9),
                offset: const Offset(3, 4),
                blurRadius: 0,
              ),
            ],
          ),
          child: const Text(
            '求索',
            style: TextStyle(color: blue, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '浙大校园智能助手',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        const SizedBox(height: 4),
        const Text(
          '我是你的专属 AI 助教，可以随时为你查询课表、作业、考场或下载课件。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Color(0x9922304e), height: 1.6),
        ),
        const SizedBox(height: 16),
        for (final item in _quickPrompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SizedBox(
              width: maxWidth,
              child: OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        input.text = item.$2;
                        input.selection = TextSelection.collapsed(offset: input.text.length);
                        unawaited(send());
                      },
                icon: const Icon(Icons.arrow_upward, size: 14),
                label: Align(alignment: Alignment.centerLeft, child: Text(item.$1)),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: ink,
                  backgroundColor: paperCard,
                  side: BorderSide(color: ink.withValues(alpha: .14)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget conversationMenu(double maxWidth) {
    final width = math.min(336.0, math.max(220.0, maxWidth - 48));
    return Material(
      color: paperCard,
      elevation: 8,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: paperCard,
          border: Border.all(color: ink.withValues(alpha: .16)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: startNewConversation,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add, size: 18, color: blue),
                    SizedBox(width: 8),
                    Text(
                      '开启新对话',
                      style: TextStyle(color: blue, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            if (conversations.isNotEmpty) const SizedBox(height: 5),
            if (conversations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('暂无历史会话', style: TextStyle(fontSize: 12, color: Color(0x9922304e))),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 190),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final conversation in conversations)
                      InkWell(
                        onTap: () => selectConversation(text(conversation, 'id')),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: text(conversation, 'id') == conversationId
                                ? gold.withValues(alpha: .2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  text(conversation, 'title', '新对话'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: text(conversation, 'id') == conversationId
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => deleteConversation(text(conversation, 'id')),
                                tooltip: '删除会话',
                                icon: const Icon(Icons.delete_outline, size: 16),
                                color: ink.withValues(alpha: .55),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(width: 24, height: 24),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget header() => Container(
    height: 54,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: const BoxDecoration(
      color: _chatHeader,
      border: Border(bottom: BorderSide(color: Color(0x4db08d3e))),
    ),
    child: Row(
      children: [
        Icon(Icons.drag_indicator, size: 20, color: paperCard.withValues(alpha: .45)),
        const SizedBox(width: 8),
        const Icon(Icons.edit_outlined, size: 18, color: gold),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () => setState(() => showConversations = !showConversations),
            borderRadius: BorderRadius.circular(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    conversationTitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: paperCard,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  showConversations ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 18,
                  color: paperCard.withValues(alpha: .65),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: startNewConversation,
          tooltip: '开启新对话',
          icon: const Icon(Icons.add, size: 22),
          color: paperCard.withValues(alpha: .72),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        ),
        IconButton(
          onPressed: () {
            if (busy) {
              widget.services.agent.cancel(conversationId ?? '');
            }
            (widget.onMinimize ?? widget.onClose ?? () => Navigator.pop(context))();
          },
          tooltip: busy ? '停止并最小化' : '最小化',
          icon: Icon(busy ? Icons.stop : Icons.remove, size: 22),
          color: paperCard.withValues(alpha: .72),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        ),
        IconButton(
          onPressed: widget.onClose ?? () => Navigator.pop(context),
          tooltip: '关闭浮窗',
          icon: const Icon(Icons.close, size: 22),
          color: paperCard.withValues(alpha: .72),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        ),
      ],
    ),
  );

  Widget composer() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: paperCard,
      border: Border(top: BorderSide(color: ink.withValues(alpha: .15))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Focus(
            onKeyEvent: handleInputKey,
            child: TextField(
              controller: input,
              enabled: !busy,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => unawaited(send()),
              decoration: InputDecoration(
                hintText: '问问 AI 助手（如：明天有什么课）…',
                hintStyle: TextStyle(color: ink.withValues(alpha: .45), fontSize: 14),
                filled: true,
                fillColor: paper,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: ink.withValues(alpha: .2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: ink.withValues(alpha: .2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: blue),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: busy
                ? () => widget.services.agent.cancel(conversationId ?? '')
                : send,
            style: FilledButton.styleFrom(
              backgroundColor: blue,
              foregroundColor: paperCard,
              padding: const EdgeInsets.symmetric(horizontal: 17),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              shadowColor: seal,
              elevation: 0,
            ),
            child: Text(
              busy ? '…' : '发送',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    ),
  );

  Widget confirmationBar() {
    final confirmation = pending.first;
    final calls = rows(confirmation['calls']);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: .1),
        border: Border(top: BorderSide(color: gold.withValues(alpha: .5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 16, color: gold),
              const SizedBox(width: 6),
              const Text('执行确认：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Text(
                calls.isEmpty ? '下载课件' : toolLabel(text(calls.first, 'name')),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: gold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '下载课程资料',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: ink.withValues(alpha: .7)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () => consume(
                            widget.services.agent.confirm(
                              conversationId!,
                              text(confirmation, 'id'),
                              true,
                            ),
                          ),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xff2f7d32)),
                  child: Text(busy ? '执行中…' : '同意'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => consume(
                            widget.services.agent.confirm(
                              conversationId!,
                              text(confirmation, 'id'),
                              false,
                            ),
                          ),
                  child: const Text('拒绝'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.max(180.0, constraints.maxWidth * .88);
        final body = ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
          children: [
            if (messages.isEmpty && !busy) welcome(maxWidth),
            for (final message in messages) historyMessage(message, maxWidth),
            if (liveTools.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final tool in liveTools) toolStep(tool)],
                ),
              ),
            if (busy && response.trim().isEmpty && liveTools.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 6,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: blue, shape: BoxShape.circle),
                      ),
                    ),
                    SizedBox(width: 7),
                    Text('思考中…', style: TextStyle(fontSize: 12, color: Color(0x9922304e))),
                  ],
                ),
              ),
            if (response.trim().isNotEmpty) bubble(response, user: false, maxWidth: maxWidth),
            if (error.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: seal.withValues(alpha: .1),
                  border: Border.all(color: seal.withValues(alpha: .4)),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(error, style: const TextStyle(fontSize: 12, color: seal)),
              ),
          ],
        );
        final content = Column(
          children: [
            widget.onHeaderDrag == null
                ? header()
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: widget.onHeaderDrag,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: header(),
                    ),
                  ),
            Expanded(child: Container(color: paper.withValues(alpha: .68), child: body)),
            if (pending.isNotEmpty) confirmationBar() else composer(),
          ],
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            if (showConversations)
              Positioned(left: 64, top: 49, child: conversationMenu(constraints.maxWidth)),
          ],
        );
      },
    );
  }
}
