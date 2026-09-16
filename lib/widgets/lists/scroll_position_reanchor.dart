import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// הפריט הראשון שתחילתו בתוך התצוגה. רק הוא ניתן לביטוי כעוגן, כי
/// `alignment` של `jumpTo` מגיע ל-`Viewport.anchor` שחייב להיות בתחום [0,1].
ItemPosition? reanchorTargetPosition(Iterable<ItemPosition> positions) {
  ItemPosition? best;
  for (final position in positions) {
    if (position.itemLeadingEdge < 0 || position.itemLeadingEdge > 1) continue;
    if (best == null || position.itemLeadingEdge < best.itemLeadingEdge) {
      best = position;
    }
  }
  return best;
}

/// מעגן מחדש `ScrollablePositionedList` על הפריט שבראש התצוגה בכל פעם
/// שהגלילה נחה.
///
/// החבילה שומרת מיקום כ"פריט עוגן + היסט בפיקסלים", והעוגן מתעדכן רק בקפיצה
/// תכנותית. בלי העיגון הזה שינוי רוחב (חלונית שנפתחת, שינוי גודל החלון) שופך
/// את הטקסט מחדש, וההיסט הישן נוחת במקום אחר לגמרי.
class ScrollPositionReanchor extends StatefulWidget {
  const ScrollPositionReanchor({
    super.key,
    required this.scrollController,
    required this.positionsListener,
    required this.child,
    this.enabled = true,
  });

  /// מבדיל בין "הגלילה נחה" לבין אנימציית גלילה שעדיין רצה — עיגון מחדש
  /// באמצע אנימציה היה מבטל אותה.
  static const idleDelay = Duration(milliseconds: 350);

  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;
  final bool enabled;
  final Widget child;

  @override
  State<ScrollPositionReanchor> createState() => _ScrollPositionReanchorState();
}

class _ScrollPositionReanchorState extends State<ScrollPositionReanchor> {
  Timer? _idleTimer;
  int? _lastIndex;
  double? _lastAlignment;

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        if (!widget.enabled) return false;
        _idleTimer?.cancel();
        _idleTimer = Timer(ScrollPositionReanchor.idleDelay, _reanchor);
        return false;
      },
      child: widget.child,
    );
  }

  void _reanchor() {
    if (!mounted || !widget.scrollController.isAttached) return;
    final anchor = reanchorTargetPosition(
      widget.positionsListener.itemPositions.value,
    );
    if (anchor == null) return;
    if (anchor.index == _lastIndex &&
        anchor.itemLeadingEdge == _lastAlignment) {
      return;
    }
    _lastIndex = anchor.index;
    _lastAlignment = anchor.itemLeadingEdge;
    widget.scrollController.jumpTo(
      index: anchor.index,
      alignment: anchor.itemLeadingEdge,
    );
  }
}
