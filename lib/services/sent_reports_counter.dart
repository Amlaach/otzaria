import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/shared_hive_store.dart';

/// מונה כל הדיווחים שנשלחו, בנפרד מההיסטוריה שנחתכת למספר קבוע של רשומות.
///
/// הספירה היא תצוגה בלבד: כשל בה נרשם ביומן ואינו מכשיל את שמירת הדיווח.
class SentReportsCounter {
  SentReportsCounter({required this.boxName, this.key = defaultKey})
    : _memory = null;

  /// מונה בזיכרון, לבדיקות שאין בהן Hive.
  @visibleForTesting
  SentReportsCounter.inMemory([int initial = 0])
    : boxName = '',
      key = defaultKey,
      _memory = _MemoryValue(initial);

  static const String defaultKey = 'sent_reports_total';

  final String boxName;
  final String key;
  final _MemoryValue? _memory;

  /// הערך השמור, או 0 כשאין ערך או שהקריאה נכשלה.
  Future<int> read() async {
    final memory = _memory;
    if (memory != null) return memory.value;
    try {
      final value = (await SharedHiveStore.instance.read(boxName, key)).value;
      return value is int ? value : 0;
    } catch (e) {
      debugPrint('SentReportsCounter.read($boxName) failed: $e');
      return 0;
    }
  }

  /// מקדם את המונה. [floor] הוא גודל ההיסטוריה לפני ההוספה: מתקין שעוד לא
  /// היה לו מונה מתחיל ממנו ולא מאפס.
  Future<void> increment({required int floor}) async {
    final current = await read();
    await _write((current > floor ? current : floor) + 1);
  }

  Future<void> reset() => _write(0);

  Future<void> _write(int value) async {
    final memory = _memory;
    if (memory != null) {
      memory.value = value;
      return;
    }
    try {
      await SharedHiveStore.instance.write(boxName, key, value);
    } catch (e) {
      debugPrint('SentReportsCounter.write($boxName) failed: $e');
    }
  }
}

class _MemoryValue {
  _MemoryValue(this.value);
  int value;
}
