import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Two columns of pins, laid out all at once, as a box.
///
/// **Why this exists rather than `SliverMasonryGrid`.** The package's masonry
/// sliver keeps its leading edge in a pair of stacks (`_previousCrossAxisIndexes`,
/// `_previousMainAxisExtents`) that are only correct if children leave and
/// re-enter in exact reverse order. Ordinary scrolling of a run whose first
/// row has one tall pin and one short one is enough to break that: it pops a
/// column index it no longer has, falls back to column 0 and extent 0, the
/// run grows by a row, and the sliver emits a `scrollOffsetCorrection` to
/// reconcile. On the production web build that showed up as the feed refusing
/// to scroll down at all, and as Custom Art moving out from beside the +6
/// cart and leaving a blank half-width hole (Grace, 2026-09-29, round 3, with
/// screenshots of the run before and after).
///
/// A box has no such cache and cannot emit a correction, because it does not
/// take part in scroll geometry at all. The laziness that is worth having is
/// kept one level up: the runs themselves are built on demand by a
/// `SliverList`. A run is a handful of pins between two full-width items, so
/// laying one out costs nothing worth saving.
///
/// The rule is the one the package used, so the grid looks the same: each
/// child goes into the column that is currently shorter, ties to the left.
class MasonryRun extends MultiChildRenderObjectWidget {
  const MasonryRun({
    super.key,
    required super.children,
    required this.gutter,
    required this.rowGap,
  });

  /// Between the two columns.
  final double gutter;

  /// Between one pin and the next down a column.
  final double rowGap;

  @override
  RenderMasonryRun createRenderObject(BuildContext context) =>
      RenderMasonryRun(gutter: gutter, rowGap: rowGap);

  @override
  void updateRenderObject(BuildContext context, RenderMasonryRun renderObject) {
    renderObject
      ..gutter = gutter
      ..rowGap = rowGap;
  }
}

class RenderMasonryRun extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  RenderMasonryRun({required double gutter, required double rowGap})
    : _gutter = gutter,
      _rowGap = rowGap;

  double _gutter;
  double get gutter => _gutter;
  set gutter(double value) {
    if (_gutter == value) return;
    _gutter = value;
    markNeedsLayout();
  }

  double _rowGap;
  double get rowGap => _rowGap;
  set rowGap(double value) {
    if (_rowGap == value) return;
    _rowGap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _RunParentData();
    }
  }

  /// The height this run comes out at, laying the children out if [place].
  ///
  /// One method for both so a dry layout cannot disagree with the real one:
  /// two copies of the shortest-column rule would be two chances to draw the
  /// grid one way and measure it another.
  double _layoutColumns(double width, {required bool place}) {
    final columnWidth = (width - gutter) / 2;
    final heights = <double>[0, 0];

    var child = firstChild;
    while (child != null) {
      final constraints = BoxConstraints.tightFor(width: columnWidth);
      final Size size;
      if (place) {
        child.layout(constraints, parentUsesSize: true);
        size = child.size;
      } else {
        size = child.getDryLayout(constraints);
      }

      // Ties go left, which is what keeps a one-pin run from starting in the
      // right-hand column.
      final column = heights[1] < heights[0] ? 1 : 0;
      if (place) {
        (child.parentData! as ContainerBoxParentData<RenderBox>).offset =
            Offset(column * (columnWidth + gutter), heights[column]);
      }
      heights[column] += size.height + rowGap;
      child =
          (child.parentData! as ContainerBoxParentData<RenderBox>).nextSibling;
    }

    final tallest = math.max(heights[0], heights[1]);
    // The gap after the last pin in a column is not part of the run.
    return tallest == 0 ? 0 : tallest - rowGap;
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    size = Size(width, _layoutColumns(width, place: true));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => Size(
    constraints.maxWidth,
    _layoutColumns(constraints.maxWidth, place: false),
  );

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _layoutColumns(width, place: false);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _layoutColumns(width, place: false);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _RunParentData extends ContainerBoxParentData<RenderBox> {}
