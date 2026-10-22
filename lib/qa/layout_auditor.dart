// Geometry checks for the QA harness. Walks the *visible* render tree and
// reports the defect classes from the pre-launch review: text squeezed into a
// narrow column, words broken mid-word, truncated text, text running past the
// screen edge, and Row/Column overflow. Works in any build mode; source
// locations need a debug build (widget creation tracking).

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'widget_index.g.dart';

class QaIssue {
  QaIssue({
    required this.kind,
    required this.severity,
    required this.message,
    required this.rect,
    this.text,
    this.location,
    this.widget,
  });

  final String kind;
  final String severity;
  final String message;
  final Rect rect;
  final String? text;
  final String? location;
  final String? widget;

  String get signature =>
      '$kind|$text|${rect.left.round()},${rect.top.round()},${rect.width.round()},${rect.height.round()}';

  Map<String, Object?> toJson() => {
    'kind': kind,
    'severity': severity,
    'message': message,
    'text': text,
    'location': location,
    'widget': widget,
    'rect': qaRectJson(rect),
  };
}

Map<String, double> qaRectJson(Rect r) => {
  'x': _round1(r.left),
  'y': _round1(r.top),
  'w': _round1(r.width),
  'h': _round1(r.height),
};

double _round1(double v) => (v * 10).roundToDouble() / 10;

final _wordChar = RegExp(r"[\p{L}\p{N}'’]", unicode: true);

Size qaScreenSize() {
  final views = WidgetsBinding.instance.renderViews;
  return views.isEmpty ? Size.zero : views.first.size;
}

Rect qaGlobalRect(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

/// Visits render objects that are actually on screen: skips offstage routes,
/// hidden IndexedStack tabs, Offstage widgets and fully transparent subtrees.
void qaVisitVisible(RenderObject node, void Function(RenderObject) visitor) {
  if (node is RenderOffstage && node.offstage) return;
  if (node is RenderSliverOffstage && node.offstage) return;
  if (node is RenderOpacity && node.opacity == 0) return;
  if (node is RenderAnimatedOpacity && node.opacity.value == 0) return;
  visitor(node);
  if (node is RenderIndexedStack ||
      node.runtimeType.toString() == '_RenderTheater') {
    node.visitChildrenForSemantics((c) => qaVisitVisible(c, visitor));
  } else {
    node.visitChildren((c) => qaVisitVisible(c, visitor));
  }
}

List<QaIssue> qaRunAudit() {
  final views = WidgetsBinding.instance.renderViews;
  if (views.isEmpty) return const [];
  final screen = Offset.zero & views.first.size;
  final issues = <QaIssue>[];
  qaVisitVisible(views.first, (node) {
    if (node is! RenderBox || !node.hasSize || !node.attached) return;
    final Rect rect;
    try {
      rect = qaGlobalRect(node);
    } catch (_) {
      return;
    }
    if (!rect.overlaps(screen) || rect.isEmpty) return;
    if (node is RenderParagraph) {
      issues.addAll(qaCheckParagraph(node, rect, screen));
    } else if (node is RenderFlex) {
      final issue = _checkFlex(node, rect);
      if (issue != null) issues.add(issue);
    }
  });
  const order = {'P0': 0, 'P1': 1, 'P2': 2};
  issues.sort((a, b) {
    final s = (order[a.severity] ?? 9).compareTo(order[b.severity] ?? 9);
    return s != 0 ? s : a.rect.top.compareTo(b.rect.top);
  });
  return issues;
}

List<QaIssue> qaCheckParagraph(RenderParagraph p, Rect rect, Rect screen) {
  final plain = p.text.toPlainText(includeSemanticsLabels: false).trim();
  if (plain.length < 2) return const [];
  final snippet = plain.length > 90 ? '${plain.substring(0, 87)}…' : plain;
  final issues = <QaIssue>[];
  QaIssue make(String kind, String severity, String message) {
    final loc = qaLocationFor(p);
    return QaIssue(
      kind: kind,
      severity: severity,
      message: message,
      rect: rect,
      text: snippet,
      location: loc?.location,
      widget: loc?.widget,
    );
  }

  final lines = _lineRanges(p);
  if (lines != null && lines.length >= 3) {
    final counts =
        lines
            .map(
              (r) => p.text
                  .toPlainText(includeSemanticsLabels: false)
                  .substring(r.start, r.end)
                  .replaceAll(RegExp(r'\s'), '')
                  .length,
            )
            .toList()
          ..sort();
    final median = counts[counts.length ~/ 2];
    if (median <= 3) {
      issues.add(
        make(
          'squeezed',
          'P0',
          'Text squeezed into a ${rect.width.toStringAsFixed(0)}px-wide column: '
              '${lines.length} lines, ~$median characters per line',
        ),
      );
    }
  }

  if (lines != null && issues.isEmpty) {
    final full = p.text.toPlainText(includeSemanticsLabels: false);
    final broken = <String>[];
    for (var i = 0; i < lines.length - 1; i++) {
      final end = lines[i].end;
      if (end <= 0 || end >= full.length) continue;
      if (_wordChar.hasMatch(full[end - 1]) && _wordChar.hasMatch(full[end])) {
        var s = end - 1, e = end;
        while (s > 0 && _wordChar.hasMatch(full[s - 1])) {
          s--;
        }
        while (e < full.length && _wordChar.hasMatch(full[e])) {
          e++;
        }
        broken.add('${full.substring(s, end)}|${full.substring(end, e)}');
      }
    }
    if (broken.isNotEmpty) {
      issues.add(
        make(
          'mid-word',
          'P1',
          'Word broken across lines: ${broken.take(3).join(', ')}',
        ),
      );
    }
  }

  if (p.didExceedMaxLines) {
    issues.add(
      make(
        'truncated',
        'P1',
        'Text cut off at maxLines ${p.maxLines ?? '-'}'
            '${p.overflow == TextOverflow.ellipsis ? ' with "…"' : ''}',
      ),
    );
  }

  if ((rect.right > screen.right + 0.5 || rect.left < screen.left - 0.5) &&
      !_insideHorizontalScroll(p)) {
    issues.add(
      make(
        'offscreen',
        'P1',
        'Text extends past the screen edge '
            '(${rect.left.toStringAsFixed(0)}–${rect.right.toStringAsFixed(0)} of ${screen.width.toStringAsFixed(0)}px)',
      ),
    );
  }
  return issues;
}

/// Re-lays out the paragraph's text exactly as RenderParagraph does and
/// returns each line's text range. Null when the text has inline widgets.
List<TextRange>? _lineRanges(RenderParagraph p) {
  var hasPlaceholder = false;
  p.text.visitChildren((span) {
    if (span is PlaceholderSpan) hasPlaceholder = true;
    return !hasPlaceholder;
  });
  if (hasPlaceholder) return null;
  final painter = TextPainter(
    text: p.text,
    textAlign: p.textAlign,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
    ellipsis: p.overflow == TextOverflow.ellipsis ? '…' : null,
    locale: p.locale,
    strutStyle: p.strutStyle,
    textWidthBasis: p.textWidthBasis,
    textHeightBehavior: p.textHeightBehavior,
  );
  try {
    final widthMatters = p.softWrap || p.overflow == TextOverflow.ellipsis;
    final maxWidth = widthMatters ? p.constraints.maxWidth : double.infinity;
    painter.layout(maxWidth: maxWidth);
    final ranges = <TextRange>[];
    for (final line in painter.computeLineMetrics()) {
      final probe = painter.getPositionForOffset(
        Offset(line.left + line.width / 2, line.baseline - line.ascent / 2),
      );
      final range = painter.getLineBoundary(probe);
      if (range.isValid && !range.isCollapsed) ranges.add(range);
    }
    return ranges;
  } catch (_) {
    return null;
  } finally {
    painter.dispose();
  }
}

bool _insideHorizontalScroll(RenderObject node) {
  RenderObject? p = node.parent;
  while (p != null) {
    if (p is RenderViewportBase && p.axis == Axis.horizontal) return true;
    // SingleChildScrollView's viewport is private; read its direction dynamically.
    if (p is RenderAbstractViewport && p is! RenderViewportBase) {
      try {
        final direction = (p as dynamic).axisDirection as AxisDirection;
        if (axisDirectionToAxis(direction) == Axis.horizontal) return true;
      } catch (_) {}
    }
    p = p.parent;
  }
  return false;
}

QaIssue? _checkFlex(RenderFlex flex, Rect rect) {
  final horizontal = flex.direction == Axis.horizontal;
  var total = 0.0;
  var count = 0;
  flex.visitChildren((c) {
    if (c is RenderBox && c.hasSize) {
      total += horizontal ? c.size.width : c.size.height;
      count++;
    }
  });
  total += flex.spacing * math.max(0, count - 1);
  final available = horizontal ? flex.size.width : flex.size.height;
  final over = total - available;
  if (over <= 1.0) return null;
  final loc = qaLocationFor(flex);
  return QaIssue(
    kind: 'overflow',
    severity: over >= 8 ? 'P0' : 'P1',
    message:
        '${horizontal ? 'Row' : 'Column'} overflows by ${over.toStringAsFixed(1)}px '
        '(children ${total.toStringAsFixed(0)}px in ${available.toStringAsFixed(0)}px)',
    rect: rect,
    location: loc?.location,
    widget: loc?.widget,
  );
}

class QaLocation {
  const QaLocation(this.location, this.widget);
  final String location;
  final String widget;
}

/// Nearest project (lib/) widget that created [node], as "lib/file.dart:line:col".
/// Needs widget creation tracking (debug builds); null otherwise.
QaLocation? qaLocationFor(RenderObject node) {
  final creator = node.debugCreator;
  if (creator is! DebugCreator) return null;
  return qaLocationForElement(creator.element);
}

/// Exact creation site when widget creation tracking is on (flutter run);
/// otherwise the nearest project widget class from [qaWidgetIndex].
QaLocation? qaLocationForElement(Element start) {
  final service = WidgetInspectorService.instance;
  if (!service.isWidgetCreationTracked()) return _indexLocation(start);
  const group = 'eh-qa-audit';
  QaLocation? found;
  bool check(Element e) {
    if (!debugIsLocalCreationLocation(e)) return true;
    try {
      service.selection.currentElement = e;
      final json = jsonDecode(service.getSelectedSummaryWidget(null, group));
      final loc = json is Map ? json['creationLocation'] : null;
      if (loc is Map && loc['file'] is String) {
        final file = loc['file'] as String;
        if (!file.contains('/.pub-cache/') && !file.contains('pub.dev/')) {
          found = QaLocation(
            '${qaShortPath(file)}:${loc['line']}:${loc['column']}',
            (json['description'] ?? e.widget.runtimeType.toString()).toString(),
          );
          return false;
        }
      }
    } catch (_) {}
    return true;
  }

  if (check(start)) start.visitAncestorElements(check);
  // Release the inspector references this lookup created.
  // ignore: invalid_use_of_protected_member
  service.disposeGroup(group);
  return found ?? _indexLocation(start);
}

/// Walks up from [start] to the nearest widgets declared in lib/ and returns
/// the first one's declaration, plus a short chain of project widgets.
QaLocation? _indexLocation(Element start) {
  String? decl;
  final chain = <String>[];
  bool check(Element e) {
    final name = qaTypeName(e.widget);
    final where = qaWidgetIndex[name];
    if (where != null && (chain.isEmpty || chain.last != name)) {
      decl ??= where;
      chain.add(name);
      if (chain.length >= 3) return false;
    }
    return true;
  }

  if (check(start)) start.visitAncestorElements(check);
  if (decl == null) return null;
  return QaLocation(decl!, 'in class ${chain.join(' ← ')}');
}

/// Project widgets named in a Flutter error's creator chain
/// ("Row ← Padding ← _CareToolCard ← …"), with their declarations.
List<String> qaProjectWidgetsInChain(String text) {
  final out = <String>[];
  for (final match in RegExp(r'[A-Za-z_]\w*').allMatches(text)) {
    final name = match.group(0)!;
    final where = qaWidgetIndex[name];
    if (where != null && !out.any((s) => s.startsWith('$name '))) {
      out.add('$name ($where)');
      if (out.length >= 4) break;
    }
  }
  return out;
}

String qaTypeName(Object o) {
  final name = o.runtimeType.toString();
  final generic = name.indexOf('<');
  return generic < 0 ? name : name.substring(0, generic);
}

String qaShortPath(String file) {
  final i = file.lastIndexOf('/lib/');
  return i >= 0 ? file.substring(i + 1) : file;
}

/// Details for the inspector panel about the element at [globalPosition].
Map<String, Object?>? qaInspectAt(RenderBox appRoot, Offset globalPosition) {
  final result = BoxHitTestResult();
  appRoot.hitTest(result, position: appRoot.globalToLocal(globalPosition));
  RenderParagraph? paragraph;
  RenderBox? box;
  for (final entry in result.path) {
    final target = entry.target;
    if (target is RenderParagraph && paragraph == null) paragraph = target;
    if (target is RenderBox && box == null) box = target;
  }
  final RenderBox? chosen = paragraph ?? box;
  if (chosen == null || !chosen.hasSize) return null;

  final rect = qaGlobalRect(chosen);
  final loc = qaLocationFor(chosen);
  final ancestors = <Map<String, Object?>>[];
  RenderObject? p = chosen.parent;
  while (p != null && ancestors.length < 8) {
    if (p is RenderBox && p.hasSize) {
      ancestors.add({
        'type': _shortType(p),
        'size':
            '${p.size.width.toStringAsFixed(1)}×${p.size.height.toStringAsFixed(1)}',
        'constraints': _describeConstraints(p.constraints),
        'location': qaLocationFor(p)?.location,
      });
    }
    p = p.parent;
  }

  final info = <String, Object?>{
    'type': _shortType(chosen),
    'rect': qaRectJson(rect),
    'constraints': _describeConstraints(chosen.constraints),
    'location': loc?.location,
    'widget': loc?.widget,
    'ancestors': ancestors,
  };
  if (chosen is RenderParagraph) {
    final style = chosen.text.style;
    final base = style?.fontSize ?? 14;
    info['text'] = chosen.text.toPlainText(includeSemanticsLabels: false);
    info['fontSize'] =
        '${base.toStringAsFixed(1)} → ${chosen.textScaler.scale(base).toStringAsFixed(1)}px rendered';
    info['fontWeight'] = style?.fontWeight?.toString();
    info['fontFamily'] = style?.fontFamily;
    info['lines'] = _lineRanges(chosen)?.length;
    info['maxLines'] = chosen.maxLines;
    info['truncated'] = chosen.didExceedMaxLines;
    info['issues'] = qaCheckParagraph(
      chosen,
      rect,
      Offset.zero & qaScreenSize(),
    ).map((i) => i.message).toList();
  }
  return info;
}

String _shortType(RenderObject o) => o.runtimeType.toString();

String _describeConstraints(Constraints c) {
  if (c is! BoxConstraints) return c.toString();
  String range(double min, double max) {
    final hi = max.isFinite ? max.toStringAsFixed(1) : '∞';
    return min == max ? hi : '${min.toStringAsFixed(1)}–$hi';
  }

  return 'w ${range(c.minWidth, c.maxWidth)}, h ${range(c.minHeight, c.maxHeight)}';
}
