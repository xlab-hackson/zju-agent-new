import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../domain/models.dart';

String normalize(String input) => input
    .replaceAll(RegExp(r'<!--[\s\S]*?-->|!\[[^\]]*\]\([^)]*\)'), ' ')
    .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(RegExp(r'[`#*_~|>]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();
Set<String> tokenize(String input) {
  final tokens = <String>{};
  for (final m in RegExp(
    r'[a-z0-9]+|[\u4e00-\u9fff]+',
  ).allMatches(input.toLowerCase())) {
    final run = m[0]!;
    if (RegExp(r'^[a-z0-9]').hasMatch(run)) {
      if (run.length >= 2) tokens.add(run);
      continue;
    }
    if (run.length <= 3) tokens.add(run);
    for (var i = 0; i + 2 <= run.length; i++) {
      tokens.add(run.substring(i, i + 2));
    }
  }
  return tokens;
}

class GuideIndex {
  GuideIndex(this.docs) {
    _build();
  }
  final Map<String, String> docs;
  final List<Json> sections = [];
  final Map<String, int> frequencies = {};
  static Future<GuideIndex> load() async => GuideIndex(
    object(
      jsonDecode(await rootBundle.loadString('assets/knowledge.json')),
    ).map((k, v) => MapEntry(k, '$v')),
  );
  void _build() {
    for (final entry in docs.entries.where(
      (e) => !e.key.endsWith('ATTRIBUTION.md'),
    )) {
      final stack = <(int, String)>[], body = <String>[];
      void flush() {
        final plain = normalize(body.join('\n'));
        if (stack.isNotEmpty && plain.length >= 10) {
          sections.add({
            'doc': entry.key,
            'title': stack.map((e) => e.$2).join(' / '),
            'text': body.join('\n').trim(),
            'plain': plain,
          });
        }
        body.clear();
      }

      for (final line in entry.value.replaceFirst('\ufeff', '').split('\n')) {
        final m = RegExp(r'^(#{1,6})\s+(.+?)\s*$').firstMatch(line);
        if (m == null) {
          body.add(line);
          continue;
        }
        flush();
        while (stack.isNotEmpty && stack.last.$1 >= m[1]!.length) {
          stack.removeLast();
        }
        stack.add((m[1]!.length, m[2]!));
      }
      flush();
    }
    for (final s in sections) {
      for (final t in tokenize('${s['title']} ${s['plain']}')) {
        frequencies[t] = (frequencies[t] ?? 0) + 1;
      }
    }
  }

  List<Json> search(String query, {int limit = 5}) {
    final terms = tokenize(normalize(query)).take(60);
    final scored = <Json>[];
    for (final s in sections) {
      var score = 0.0;
      for (final t in terms) {
        final df = frequencies[t] ?? 0;
        if (df > sections.length * .3) continue;
        final hits = RegExp(
          RegExp.escape(t),
        ).allMatches('${s['plain']}').take(6).length;
        score +=
            (hits + (normalize('${s['title']}').contains(t) ? 6 : 0)) *
            math.log(1 + sections.length / (1 + df));
      }
      if (score > 0) {
        scored.add({
          'doc': s['doc'],
          'title': s['title'],
          'text': _clip('${s['text']}', 1500),
          'score': score,
        });
      }
    }
    scored.sort(
      (a, b) => (b['score'] as double).compareTo(a['score'] as double),
    );
    return scored.take(limit.clamp(1, 20)).toList();
  }

  String read(String doc) {
    if (!docs.containsKey(doc) || doc.endsWith('ATTRIBUTION.md')) {
      throw const AppError('FILE_NOT_FOUND', '未找到知识库文档。');
    }
    return _clip(docs[doc]!, 8000);
  }

  String get outline => docs.keys
      .where((k) => !k.endsWith('ATTRIBUTION.md'))
      .map(
        (k) =>
            '$k: ${RegExp(r"^#\s+(.+)$", multiLine: true).firstMatch(docs[k]!)?[1] ?? k}',
      )
      .join('\n');
  String _clip(String s, int n) =>
      s.length > n ? '${s.substring(0, n)}\n[已截断]' : s;
}
