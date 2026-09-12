import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/services.dart';
import '../../domain/formatters.dart';
import '../../domain/models.dart';
import '../theme.dart';
import 'page_header.dart';

/// Base widget for data pages. Each feature owns its filters and loader.
abstract class CampusDataPage extends StatefulWidget {
  const CampusDataPage({super.key, required this.services});
  final AppServices services;
}

/// Shared loading, cache notifications and page chrome; no feature dispatch.
abstract class CampusPageState<T extends CampusDataPage> extends State<T> {
  late Future<Json> data;
  DateTime now = DateTime.now();
  bool refreshing = false;
  bool _loadingPageData = false;
  StreamSubscription<String>? _cacheSubscription;
  Timer? _pageReloadTimer;
  Timer? _ticker;

  AppServices get s => widget.services;
  String get pageKey;
  String get title;
  String? get subtitle => null;
  String get refreshTooltip => '刷新';
  bool get showRefreshButton => true;
  bool get allowPullRefresh => true;
  bool get usesNetworkCache => true;
  bool get needsSecondTicker => false;
  Future<Json> load({bool refresh = false});
  bool usesCache(String key) => false;
  PageContext buildPageContext({Json? activeCourse, String? courseTab});
  List<Widget> content(Json data, {required bool wide});
  List<Widget> headerExtras(AsyncSnapshot<Json> snapshot) => const [];
  Widget? sidePanel(double width) => null;
  VoidCallback? get openSidePanel => null;
  void initializePage() {}

  void syncPageContext({Json? activeCourse, String? courseTab}) {
    s.updatePageContext(
      buildPageContext(activeCourse: activeCourse, courseTab: courseTab),
    );
  }

  @override
  void initState() {
    super.initState();
    initializePage();
    syncPageContext();
    if (usesNetworkCache) {
      _cacheSubscription = s.campus.cacheChanges.listen(_handleCacheChange);
    }
    data = _loadPageData(
      refresh: usesNetworkCache && s.claimInitialRefresh(pageKey),
    );
    if (usesNetworkCache || needsSecondTicker) {
      _ticker = Timer.periodic(
        needsSecondTicker
            ? const Duration(seconds: 1)
            : const Duration(minutes: 1),
        (_) {
          if (mounted) setState(() => now = DateTime.now());
        },
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _cacheSubscription?.cancel();
    _pageReloadTimer?.cancel();
    super.dispose();
  }

  Future<Json> _loadPageData({bool refresh = false}) async {
    _loadingPageData = true;
    try {
      return await load(refresh: refresh);
    } finally {
      _loadingPageData = false;
    }
  }

  void _handleCacheChange(String key) {
    if (mounted && !_loadingPageData && usesCache(key)) _schedulePageReload();
  }

  void _schedulePageReload() {
    if (_pageReloadTimer != null) return;
    _pageReloadTimer = Timer(const Duration(milliseconds: 120), () {
      _pageReloadTimer = null;
      unawaited(_reloadPageFromCache());
    });
  }

  Future<void> _reloadPageFromCache() async {
    if (!mounted || _loadingPageData) return;
    final previous = data;
    final next = _loadPageData();
    setState(() {
      data = next;
    });
    try {
      await next;
    } catch (_) {
      if (mounted && identical(data, next)) {
        setState(() {
          data = previous;
        });
      }
    }
  }

  Future<void> refresh({bool force = true}) async {
    if (refreshing) return;
    refreshing = true;
    final next = _loadPageData(refresh: force);
    if (mounted) {
      setState(() {
        data = next;
      });
    }
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the page error; refresh controls should settle.
    } finally {
      if (mounted) {
        setState(() => refreshing = false);
      } else {
        refreshing = false;
      }
    }
  }

  Future<void> act(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is AppError ? e.message : '操作失败，请重试。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final panel = wide ? sidePanel(constraints.maxWidth) : null;
      return CustomPaint(
        painter: PaperLines(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _scrollableContent(wide)),
                ?panel,
              ],
            ),
            if (!wide && openSidePanel != null)
              Positioned(
                right: 16,
                bottom: 80,
                child: FloatingActionButton.small(
                  heroTag: 'right-panel-$pageKey',
                  tooltip: '打开辅助面板',
                  onPressed: openSidePanel,
                  backgroundColor: blue,
                  foregroundColor: paperCard,
                  child: const Icon(Icons.tune),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _scrollableContent(bool wide) {
    final scroll = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        wide ? 38 : 16,
        wide ? 32 : 24,
        wide ? 38 : 16,
        100,
      ),
      child: FutureBuilder<Json>(
        future: data,
        builder: (context, snapshot) => buildPageContent(snapshot, wide: wide),
      ),
    );
    if (wide || !allowPullRefresh) return scroll;
    return RefreshIndicator(
      color: blue,
      backgroundColor: paperCard,
      onRefresh: refresh,
      child: scroll,
    );
  }

  Widget buildPageContent(AsyncSnapshot<Json> snapshot, {required bool wide}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHead(
          title: title,
          subtitle: subtitle,
          updatedAt: snapshot.hasData && usesNetworkCache
              ? dataUpdatedLabel(text(snapshot.data!, '_updatedAt'))
              : null,
          trailing: !showRefreshButton
              ? null
              : IconButton(
                  onPressed: refreshing ? null : refresh,
                  tooltip: refreshTooltip,
                  icon: refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: blue,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
        ),
        ...headerExtras(snapshot),
        _asyncBody(snapshot, wide: wide),
        if (usesNetworkCache && s.campus.stale.isNotEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('网络暂不可用，部分内容来自本地缓存。', style: TextStyle(color: gold)),
          ),
      ],
    );
  }

  Widget _asyncBody(AsyncSnapshot<Json> snapshot, {required bool wide}) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Paper(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(54),
            child: CircularProgressIndicator(color: blue),
          ),
        ),
      );
    }
    if (snapshot.hasError) {
      return Paper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off, color: seal),
            const SizedBox(height: 12),
            Text(
              snapshot.error is AppError
                  ? (snapshot.error as AppError).message
                  : '加载失败，请重试。',
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: refresh, child: const Text('重新加载')),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: content(snapshot.data ?? {}, wide: wide),
    );
  }
}
