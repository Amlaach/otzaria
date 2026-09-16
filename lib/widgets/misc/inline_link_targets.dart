import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

/// רישום קישורי `<a>` שבתוך הטקסט לפי ה-recognizer שלהם.
///
/// [RenderParagraph] מכניס לנתיב הפגיעה את ה-[TextSpan] שנלחץ, ולכן די במיפוי
/// recognizer→url כדי לדעת איזה קישור נמצא תחת הסמן — גם בלחיצה ימנית, שאינה
/// מגיעה ל-onTap של הקישור.
final _urlByRecognizer = Expando<String>('inlineLinkUrl');

/// רושם [recognizer] של קישור, ומחבר לחיצת גלגל לפתיחתו ברקע.
void registerInlineLinkRecognizer(
  TapGestureRecognizer recognizer,
  String url, {
  void Function(String url)? onMiddleClick,
}) {
  _urlByRecognizer[recognizer] = url;
  if (onMiddleClick != null) {
    recognizer.onTertiaryTapUp = (_) => onMiddleClick(url);
  }
}

TapDownDetails? _lastLinkTapDown;

/// מתעד את מיקום ההקשה ואת סוג ההתקן שלה ב-[recognizer], כי onTapUrl מקבל
/// רק את ה-url. onTapDown קודם תמיד ל-onTap של אותה מחווה.
void trackLinkTapDown(TapGestureRecognizer recognizer) {
  recognizer.onTapDown = (details) => _lastLinkTapDown = details;
}

/// מיקום ההקשה על הקישור הנוכחי כשהגיעה ממגע — שאין בו ריחוף — אחרת null.
Offset? touchLinkTapPosition() {
  final details = _lastLinkTapDown;
  if (details?.kind != PointerDeviceKind.touch) return null;
  return details!.globalPosition;
}

/// ה-url של הקישור שאליו שייך [target] מנתיב הפגיעה, או null כשאינו קישור.
String? inlineLinkUrlOf(HitTestTarget target) {
  if (target is! TextSpan) return null;
  final recognizer = target.recognizer;
  return recognizer == null ? null : _urlByRecognizer[recognizer];
}

/// הקישור שבתוך הטקסט בנקודה [globalPosition], או null כשאין שם קישור.
String? inlineLinkUrlAt(Offset globalPosition, {int viewId = 0}) {
  final result = HitTestResult();
  GestureBinding.instance.hitTestInView(result, globalPosition, viewId);
  for (final entry in result.path) {
    final url = inlineLinkUrlOf(entry.target);
    if (url != null) return url;
  }
  return null;
}
