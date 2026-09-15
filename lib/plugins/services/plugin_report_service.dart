import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/data/repository/hive_list_repository.dart';
import 'package:otzaria/plugins/models/plugin_report_record.dart';
import 'package:otzaria/services/offline_report_script_builder.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// תוצאת מסירה של דיווח תוסף: נשלח עכשיו או נשמר בתור לשליחה מאוחרת.
enum PluginReportDeliveryStatus { sent, queued }

/// שליחת דיווח משתמש על תוסף לאתר אוצריא, שמאתר את מפתח התוסף ומעביר לו.
///
/// באותו דפוס של דיווחי הטעויות בספרים: כשל זמני או מצב לא-מקוון שומרים
/// את הדיווח בתור Hive ייעודי עם ניסיון חוזר אוטומטי; דחייה קבועה של
/// השרת (400/422) נזרקת לתוסף ואינה נכנסת לתור.
class PluginReportService {
  PluginReportService({
    http.Client? client,
    HiveListRepository<PluginReportRecord>? queueRepository,
    HiveListRepository<PluginReportRecord>? sentRepository,
    SentReportsCounter? sentCounter,
  }) : _client = client ?? _shared,
       _queueRepository =
           queueRepository ?? _defaultRepository(pendingReportsKey),
       _sentRepository = sentRepository ?? _defaultRepository(sentReportsKey),
       _sentCounter = sentCounter ?? SentReportsCounter(boxName: queueBoxName);

  static final Uri endpoint = Uri.parse(
    'https://otzaria.org/api/plugin-reports',
  );

  static const String queueBoxName = 'plugin_reports_queue';
  static const String pendingReportsKey = 'pending_reports';
  static const String sentReportsKey = 'sent_reports';
  static const int maxSentReportsToKeep = 100;
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _flushInterval = Duration(minutes: 5);
  static const int _maxQueuedFlushPerRun = 20;

  /// סוגי הדיווח המוכרים לשרת; ערך לא מוכר מתורגם ל-'other'.
  static const Set<String> reportTypes = {'bug', 'crash', 'content', 'other'};

  /// אורך מרבי לשדה הפירוט; טקסט ארוך יותר נחתך לפני השליחה.
  static const int maxDetailsLength = 5000;

  static Timer? _flushTimer;
  static bool _isFlushing = false;
  static Completer<void>? _flushInFlight;

  /// עוצר את השליחה האוטומטית וממתין לשליחה שבאמצע, כדי שכתיבה חיצונית לתור
  /// (שחזור מגיבוי) לא תדרוס אותה. `startAutomaticFlush` מפעיל מחדש בעלייה.
  static Future<void> suspendAutomaticFlush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flushInFlight?.future;
  }

  final http.Client _client;
  final HiveListRepository<PluginReportRecord> _queueRepository;
  final HiveListRepository<PluginReportRecord> _sentRepository;
  final SentReportsCounter _sentCounter;

  static final http.Client _shared = _createClient();
  static final Random _random = Random.secure();

  static http.Client _createClient() {
    final client = http.Client();
    HttpClientRegistry.register(client.close);
    return client;
  }

  static HiveListRepository<PluginReportRecord> _defaultRepository(
    String key,
  ) {
    return HiveListRepository<PluginReportRecord>(
      boxName: queueBoxName,
      key: key,
      fromJson: PluginReportRecord.fromJson,
      toJson: (record) => record.toJson(),
    );
  }

  /// מזהה דיווח בפורמט UUID v4 — מאפשר לשרת לזהות שליחה כפולה בניסיון חוזר.
  static String generateReportId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String normalizeReportType(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    return reportTypes.contains(value) ? value : 'other';
  }

  bool get _queueWhenOfflineEnabled =>
      Settings.getValue<bool>(
        SettingsRepository.keyQueueErrorReportsWhenOffline,
      ) ??
      true;

  bool get _isOfflineMode =>
      Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

  /// בונה רשומת דיווח מוכנה לשליחה: נרמול סוג, חיתוך פירוט וזיהוי הגרסה.
  Future<PluginReportRecord> buildRecord({
    required String pluginUid,
    required String pluginName,
    required String pluginVersion,
    required String details,
    String? reportType,
    String? reporterEmail,
  }) async {
    final trimmedDetails = details.trim();
    if (trimmedDetails.isEmpty) {
      throw Exception('details required');
    }

    String? appVersion;
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}

    final email = reporterEmail?.trim() ?? '';
    return PluginReportRecord(
      reportId: generateReportId(),
      pluginUid: pluginUid,
      pluginName: pluginName,
      pluginVersion: pluginVersion,
      reportType: normalizeReportType(reportType),
      details: trimmedDetails.length > maxDetailsLength
          ? trimmedDetails.substring(0, maxDetailsLength)
          : trimmedDetails,
      reporterEmail: email.isEmpty ? null : email,
      appVersion: appVersion,
      platform: Platform.operatingSystem,
      createdAt: DateTime.now(),
    );
  }

  /// שולח דיווח או שומר אותו בתור. זורק על דחייה קבועה של השרת,
  /// ועל מצב לא-מקוון כשהתור האוטומטי כבוי בהגדרות.
  Future<PluginReportDeliveryStatus> submitReport(
    PluginReportRecord record,
  ) async {
    if (_isOfflineMode) {
      if (!_queueWhenOfflineEnabled) {
        throw Exception('offline and report queue is disabled');
      }
      await _enqueueIfNeeded(record);
      return PluginReportDeliveryStatus.queued;
    }

    final attemptResult = await _trySend(record);
    if (attemptResult.isSuccess) {
      await _saveSentReport(record);
      unawaited(flushPendingReports());
      return PluginReportDeliveryStatus.sent;
    }

    if (attemptResult.isPermanentFailure) {
      throw Exception(attemptResult.message);
    }

    await _enqueueIfNeeded(record);
    return PluginReportDeliveryStatus.queued;
  }

  /// שולח דיווח שמור מהתור. הרשומה מוסרת מהתור לפני השליחה — אחרת
  /// ה-flush שההצלחה מפעילה עלול לטעון את התור לפניה ולשלוח אותה שוב.
  Future<PluginReportDeliveryStatus> submitPendingReport(
    PluginReportRecord record,
  ) async {
    if (_isOfflineMode && !_queueWhenOfflineEnabled) {
      throw Exception('offline and report queue is disabled');
    }
    await deletePendingReport(record.reportId);
    // כשל זמני מחזיר את הרשומה לתור בתוך submitReport.
    return submitReport(record);
  }

  Future<int> getPendingReportsCount() async {
    final records = await _queueRepository.load();
    return records.length;
  }

  Future<List<PluginReportRecord>> getPendingReports() async {
    return _queueRepository.load();
  }

  Future<List<PluginReportRecord>> getSentReports() async {
    return _sentRepository.load();
  }

  /// כל הדיווחים שנשלחו אי-פעם — לא רק אלה שנשארו בהיסטוריה.
  Future<int> getSentReportsTotal() async {
    final total = await _sentCounter.read();
    final kept = (await _sentRepository.load()).length;
    return total > kept ? total : kept;
  }

  Future<void> deletePendingReport(String reportId) async {
    final records = await _queueRepository.load();
    records.removeWhere((record) => record.reportId == reportId);
    await _queueRepository.overwrite(records);
  }

  /// מעדכן סוג ופירוט של דיווח בתור. שינוי בתוכן מקבל `reportId` חדש: השרת
  /// מסנן מזהה שכבר נקלט, והגרסה המתוקנת הייתה נבלעת כשליחה כפולה.
  Future<void> updatePendingReport(
    String reportId, {
    required String reportType,
    required String details,
  }) async {
    final records = await _queueRepository.load();
    final index = records.indexWhere((record) => record.reportId == reportId);
    if (index == -1) return;

    final current = records[index];
    final type = normalizeReportType(reportType);
    final trimmed = details.trim();
    final text = trimmed.length > maxDetailsLength
        ? trimmed.substring(0, maxDetailsLength)
        : trimmed;
    if (text.isEmpty) {
      throw Exception('details required');
    }
    if (type == current.reportType && text == current.details) return;

    records[index] = current.copyWith(
      reportId: generateReportId(),
      reportType: type,
      details: text,
    );
    await _queueRepository.overwrite(records);
  }

  Future<void> clearPendingReports() async {
    await _queueRepository.clear();
  }

  Future<void> deleteSentReport(String reportId) async {
    final records = await _sentRepository.load();
    records.removeWhere((record) => record.reportId == reportId);
    await _sentRepository.overwrite(records);
  }

  Future<void> clearSentReports() async {
    await _sentRepository.clear();
    await _sentCounter.reset();
  }

  /// מנסה לשלוח את הדיווחים השמורים; עוצר בכשל זמני ראשון, ומסיר מהתור
  /// דיווחים שנדחו סופית. מחזיר את מספר הדיווחים שנשלחו.
  Future<int> flushPendingReports() async {
    if (_isOfflineMode || _isFlushing) {
      return 0;
    }

    _isFlushing = true;
    final inFlight = _flushInFlight = Completer<void>();
    try {
      final pendingRecords = await _queueRepository.load();
      if (pendingRecords.isEmpty) {
        return 0;
      }

      final recordsToAttempt = pendingRecords
          .take(_maxQueuedFlushPerRun)
          .toList();
      final remainingRecords = List<PluginReportRecord>.from(pendingRecords);
      var sentCount = 0;

      for (final record in recordsToAttempt) {
        final attemptResult = await _trySend(record);

        if (attemptResult.isSuccess) {
          remainingRecords.removeWhere(
            (item) => item.reportId == record.reportId,
          );
          await _saveSentReport(record);
          sentCount++;
          continue;
        }

        if (attemptResult.isPermanentFailure) {
          debugPrint(
            'Plugin report permanently failed and was removed from queue: '
            '${record.reportId}',
          );
          remainingRecords.removeWhere(
            (item) => item.reportId == record.reportId,
          );
          continue;
        }

        break;
      }

      await _queueRepository.overwrite(remainingRecords);
      return sentCount;
    } finally {
      _isFlushing = false;
      _flushInFlight = null;
      inFlight.complete();
    }
  }

  Future<void> startAutomaticFlush() async {
    if (_flushTimer != null) {
      return;
    }

    unawaited(flushPendingReports());
    _flushTimer = Timer.periodic(_flushInterval, (_) {
      unawaited(flushPendingReports());
    });
  }

  /// בונה סקריפט שליחה של הדיווחים השמורים למחשב מחובר, לפי מערכת ההפעלה.
  OfflineSendScript buildOfflineSendScript(
    List<PluginReportRecord> records, {
    required OfflineSendScriptTarget target,
  }) {
    return buildOfflineReportScript(
      target: target,
      endpoint: endpoint.toString(),
      payloads: records.map((record) => record.toApiPayload()).toList(),
      ids: records.map((record) => record.reportId).toList(),
      idField: 'reportId',
      baseFileName: 'otzaria_send_plugin_reports',
    );
  }

  Future<void> _enqueueIfNeeded(PluginReportRecord record) async {
    final pendingRecords = await _queueRepository.load();
    final alreadyQueued = pendingRecords.any(
      (item) => item.reportId == record.reportId,
    );
    if (alreadyQueued) {
      return;
    }

    pendingRecords.add(record);
    await _queueRepository.overwrite(pendingRecords);
  }

  Future<void> _saveSentReport(PluginReportRecord record) async {
    final sentRecords = await _sentRepository.load();
    final kept = sentRecords.length;
    final isNew = sentRecords.every(
      (item) => item.reportId != record.reportId,
    );
    sentRecords.removeWhere((item) => item.reportId == record.reportId);
    sentRecords.insert(0, record);
    if (sentRecords.length > maxSentReportsToKeep) {
      sentRecords.removeRange(maxSentReportsToKeep, sentRecords.length);
    }
    await _sentRepository.overwrite(sentRecords);
    if (isNew) await _sentCounter.increment(floor: kept);
  }

  Future<_SendAttemptResult> _trySend(PluginReportRecord record) async {
    try {
      final response = await _client
          .post(
            endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(record.toApiPayload()),
          )
          .timeout(_timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const _SendAttemptResult.success();
      }

      if (response.statusCode == HttpStatus.badRequest ||
          response.statusCode == 422) {
        return _SendAttemptResult.permanentFailure(
          'report rejected: HTTP ${response.statusCode}',
        );
      }

      return _SendAttemptResult.transientFailure(
        'server error: HTTP ${response.statusCode}',
      );
    } on SocketException catch (e) {
      debugPrint('Plugin report network error: $e');
      return const _SendAttemptResult.transientFailure('no internet');
    } on http.ClientException catch (e) {
      debugPrint('Plugin report client error: $e');
      return const _SendAttemptResult.transientFailure('send failed');
    } on TimeoutException {
      return const _SendAttemptResult.transientFailure('server timeout');
    } catch (e) {
      debugPrint('Plugin report unexpected error: $e');
      return const _SendAttemptResult.transientFailure(
        'unexpected send error',
      );
    }
  }
}

class _SendAttemptResult {
  final bool isSuccess;
  final String message;
  final bool isPermanentFailure;

  const _SendAttemptResult._({
    required this.isSuccess,
    required this.message,
    required this.isPermanentFailure,
  });

  const _SendAttemptResult.success()
    : this._(isSuccess: true, message: '', isPermanentFailure: false);

  const _SendAttemptResult.transientFailure(String message)
    : this._(isSuccess: false, message: message, isPermanentFailure: false);

  const _SendAttemptResult.permanentFailure(String message)
    : this._(isSuccess: false, message: message, isPermanentFailure: true);
}
