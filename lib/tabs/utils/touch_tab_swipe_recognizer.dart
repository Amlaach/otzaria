import 'package:flutter/gestures.dart';

/// החלקה בין כרטיסיות במסך מגע בדסקטופ.
///
/// שתי אצבעות תמיד מעבירות כרטיסיה. אצבע אחת מעבירה רק כשהתוכן לא
/// גולל לרוחב בעצמו ([singleFingerPansContent]) — אחרת הזירה נשארת לו.
class TouchTabSwipeRecognizer extends HorizontalDragGestureRecognizer {
  TouchTabSwipeRecognizer({
    required this.singleFingerPansContent,
    super.debugOwner,
  }) : super(supportedDevices: const {PointerDeviceKind.touch});

  /// האם אצבע אחת מזיזה כעת את התוכן לרוחב (למשל PDF מוגדל).
  final bool Function() singleFingerPansContent;

  final Set<int> _downPointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _downPointers.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _downPointers.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      ) &&
      (_downPointers.length >= 2 || !singleFingerPansContent());

  @override
  void didStopTrackingLastPointer(int pointer) {
    _downPointers.clear();
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  String get debugDescription => 'touch tab swipe';
}
