// The search report card: real searches over a real catalogue, graded.
//
// Not part of `flutter test`; it lives outside test/ and needs a catalogue
// snapshot. Build one with tool/search_eval/build_catalog.ts, then:
//
//   SEARCH_EVAL_DIR=<folder with eval-catalog.json> \
//     flutter test tool/search_eval/search_eval_test.dart
//
// It writes eval-results.json and eval-report.md into the same folder.
//
// What the database does is simulated, not called: each query below mirrors
// one `where(...).limit(n)` in FirestoreSearchRepository._plainSearch, in
// Firestore's default order (document id). The matching and ranking are the
// app's own functions, so what is graded here is what a phone would show.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';

import 'queries.dart';

class EvalDoc {
  EvalDoc(Map<String, dynamic> j)
    : id = j['id'] as String,
      product = Product(
        id: j['id'] as String,
        title: j['title'] as String,
        priceCents: (j['priceCents'] as num).toInt(),
        sellerId: j['sellerId'] as String,
        tags: [for (final t in j['tags'] as List) t as String],
        rating: 0,
        ratingCount: 0,
        type: j['type'] as String,
        description: j['description'] as String,
        cityState: '',
        saveCount: 0,
        commentCount: 0,
        soldCount: 0,
        collectionHandles: [
          for (final c in j['collectionHandles'] as List) c as String,
        ],
      ),
      searchWords = {for (final w in j['searchWords'] as List) w as String},
      titleWords = {for (final w in j['titleWords'] as List) w as String},
      titleLower = j['titleLower'] as String,
      typeSlug = j['typeSlug'] as String;

  final String id;
  final Product product;
  final Set<String> searchWords;
  final Set<String> titleWords;
  final String titleLower;
  final String typeSlug;
}

/// `where(...).limit(n)` in document-id order.
List<EvalDoc> _take(
  List<EvalDoc> docs,
  bool Function(EvalDoc) where,
  int limit,
) => docs.where(where).take(limit).toList();

/// The search as it ships now: see `_plainSearch`, scope `all`, no hashtag.
List<Product> newSearch(List<EvalDoc> docs, String query) {
  final lower = query.trim().toLowerCase();
  final variants = queryVariants(lower).toSet();
  if (variants.isEmpty) return const [];
  final hits = <String, Product>{};
  void add(Iterable<EvalDoc> found) {
    for (final d in found) {
      hits.putIfAbsent(d.id, () => d.product);
    }
  }

  for (final word in nameQueryWords(lower)) {
    final spellings = wordVariants(word).toSet();
    add(_take(docs, (d) => d.titleWords.any(spellings.contains), 300));
  }
  add(_take(docs, (d) => d.searchWords.any(variants.contains), 300));
  if (lower.contains(' ')) {
    final byTitle = [...docs]
      ..sort((a, b) => a.titleLower.compareTo(b.titleLower));
    add(_take(byTitle, (d) => d.titleLower.startsWith(lower), 50));
  }
  final slugs = typeSlugsFor(lower).toSet();
  add(_take(docs, (d) => slugs.contains(d.typeSlug), 50));
  return rankSearchHits(hits.values, lower);
}

/// The search before 2026-09-30, reproduced for the comparison: substring
/// matching, the description counting as much as the name, exact type.
List<Product> oldSearch(List<EvalDoc> docs, String query) {
  final lower = query.trim().toLowerCase();
  final variants = queryVariants(lower).toSet();
  if (variants.isEmpty) return const [];
  final hits = <String, Product>{};
  for (final d in _take(
    docs,
    (d) => d.searchWords.any(variants.contains),
    300,
  )) {
    hits.putIfAbsent(d.id, () => d.product);
  }
  if (lower.contains(' ')) {
    final byTitle = [...docs]
      ..sort((a, b) => a.titleLower.compareTo(b.titleLower));
    for (final d in _take(byTitle, (d) => d.titleLower.startsWith(lower), 50)) {
      hits.putIfAbsent(d.id, () => d.product);
    }
  }
  final slug = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  for (final d in _take(docs, (d) => d.typeSlug == slug, 50)) {
    hits.putIfAbsent(d.id, () => d.product);
  }
  int loose(Product p) {
    final text = '${p.title} ${p.type} ${p.description}'.toLowerCase();
    return [
      for (final w in queryWords(lower))
        if (wordVariants(w).any(text.contains)) w,
    ].length;
  }

  return hits.values.toList()..sort((a, b) {
    final by = loose(b) - loose(a);
    return by != 0
        ? by
        : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
}

/// The grader's own idea of relevant, deliberately not the ranker's: the
/// listing's name, type or collection says every word of the query (or one
/// of the query's accepted meanings), in any spelling. The description never
/// counts, because that is exactly the mistake being tested for.
bool relevant(Product p, EvalQuery q) {
  String words(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  final label = words('${p.title} ${p.type} ${p.collectionHandles.join(' ')}');
  for (final meaning in q.meanings) {
    if (meaning.split(' ').every((w) => saysWord(label, w))) return true;
  }
  return false;
}

String grade(double precision) => precision >= 0.9
    ? 'A'
    : precision >= 0.75
    ? 'B'
    : precision >= 0.5
    ? 'C'
    : precision >= 0.25
    ? 'D'
    : 'F';

void main() {
  test('search report card', () {
    final dir = Platform.environment['SEARCH_EVAL_DIR'];
    if (dir == null) {
      markTestSkipped('SEARCH_EVAL_DIR is not set');
      return;
    }
    final raw =
        jsonDecode(File('$dir/eval-catalog.json').readAsStringSync()) as List;
    final docs = [for (final j in raw) EvalDoc(j as Map<String, dynamic>)]
      ..sort((a, b) => a.id.compareTo(b.id));

    final rows = <Map<String, Object?>>[];
    for (final q in evalQueries) {
      final inCatalog = docs.where((d) => relevant(d.product, q)).length;
      Map<String, Object?> run(
        List<Product> Function(List<EvalDoc>, String) search,
      ) {
        final found = search(docs, q.query);
        final top = found.take(10).toList();
        final good = top.where((p) => relevant(p, q)).length;
        // Out of what could have been shown: fewer than ten relevant
        // listings in the whole catalogue is not the search's fault. None at
        // all is not gradeable.
        final possible = inCatalog < 10 ? inCatalog : 10;
        final precision = possible == 0 ? null : good / possible;
        return {
          'count': found.length,
          'relevantInTop10': good,
          'possible': possible,
          'precision': precision,
          'grade': precision == null ? '-' : grade(precision),
          'zeroPriceInTop10': top.where((p) => p.priceCents == 0).length,
          'top': [
            for (final p in top)
              {
                'title': p.title,
                'type': p.type,
                'price': p.priceCents,
                'ok': relevant(p, q),
              },
          ],
        };
      }

      rows.add({
        'query': q.query,
        'group': q.group,
        'relevantInCatalog': inCatalog,
        'before': run(oldSearch),
        'after': run(newSearch),
      });
    }

    File(
      '$dir/eval-results.json',
    ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));

    String avg(String when) {
      final p = [
        for (final r in rows)
          if ((r[when] as Map)['precision'] case final double v) v,
      ];
      return (p.reduce((a, b) => a + b) / p.length * 100).toStringAsFixed(0);
    }

    Map<String, int> grades(String when) {
      final out = {for (final g in 'ABCDF-'.split('')) g: 0};
      for (final r in rows) {
        out[(r[when] as Map)['grade'] as String] =
            out[(r[when] as Map)['grade'] as String]! + 1;
      }
      return out;
    }

    final md = StringBuffer()
      ..writeln('# Search report card')
      ..writeln()
      ..writeln('${rows.length} searches over ${docs.length} products.')
      ..writeln()
      ..writeln('| | Before | After |')
      ..writeln('|---|---|---|')
      ..writeln(
        '| Relevant in the top 10 (average) | ${avg('before')}% | ${avg('after')}% |',
      );
    for (final g in 'ABCDF-'.split('')) {
      md.writeln('| $g | ${grades('before')[g]} | ${grades('after')[g]} |');
    }
    md
      ..writeln()
      ..writeln(
        '| Search | Group | In catalogue | Before | After | Found after |',
      )
      ..writeln('|---|---|---|---|---|---|');
    for (final r in rows) {
      final b = r['before'] as Map;
      final a = r['after'] as Map;
      md.writeln(
        '| ${r['query']} | ${r['group']} | ${r['relevantInCatalog']} | '
        '${b['grade']} (${b['relevantInTop10']}/${b['possible']}) | '
        '${a['grade']} (${a['relevantInTop10']}/${a['possible']}) | ${a['count']} |',
      );
    }
    File('$dir/eval-report.md').writeAsStringSync(md.toString());
    // ignore: avoid_print
    print(md.toString().split('\n').take(12).join('\n'));
  });
}
