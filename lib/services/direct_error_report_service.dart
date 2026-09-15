import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/data/repository/hive_list_repository.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/services/offline_report_script_builder.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

export 'package:otzaria/services/offline_report_script_builder.dart'
    show OfflineSendScript, OfflineSendScriptTarget;

enum DirectReportDeliveryStatus {
  sent,
  queued,
  failed,
}

class DirectReportDeliveryResult {
  final DirectReportDeliveryStatus status;
  final String message;

  /// השרת קלט את הדיווח אך לא שלח מייל, כי תוכן זהה כבר נשלח בעבר.
  final bool isDuplicate;

  /// אתר ישן קלט הצעת תיקון כטקסט חופשי בלבד (חסר `correction_supported`).
  final bool correctionNotSupported;

  /// 409: השרת מחזיק תוכן אחר תחת אותו `report_id`.
  final bool isIdConflict;

  const DirectReportDeliveryResult._({
    required this.status,
    required this.message,
    this.isDuplicate = false,
    this.correctionNotSupported = false,
    this.isIdConflict = false,
  });

  factory DirectReportDeliveryResult.sent(
    String message, {
    bool isDuplicate = false,
    bool correctionNotSupported = false,
  }) {
    return DirectReportDeliveryResult._(
      status: DirectReportDeliveryStatus.sent,
      message: message,
      isDuplicate: isDuplicate,
      correctionNotSupported: correctionNotSupported,
    );
  }

  factory DirectReportDeliveryResult.queued(String message) {
    return DirectReportDeliveryResult._(
      status: DirectReportDeliveryStatus.queued,
      message: message,
    );
  }

  factory DirectReportDeliveryResult.failed(
    String message, {
    bool isIdConflict = false,
  }) {
    return DirectReportDeliveryResult._(
      status: DirectReportDeliveryStatus.failed,
      message: message,
      isIdConflict: isIdConflict,
    );
  }

  bool get isSent => status == DirectReportDeliveryStatus.sent;

  bool get isQueued => status == DirectReportDeliveryStatus.queued;
}

class DirectErrorReportService {
  static const String _endpoint = 'https://otzaria.org/api/reportingerrors';
  static const String queueBoxName = 'error_reports_queue';
  static const String pendingReportsKey = 'pending_reports';
  static const String sentReportsKey = 'sent_reports';
  static const int maxSentReportsToKeep = 100;
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _flushInterval = Duration(minutes: 5);
  static const int _maxQueuedFlushPerRun = 20;
  static const String _otzariaDirectReportTarget = 'אוצריא';
  static const String _sefariaDirectReportTarget = 'ספריא';

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
  final HiveListRepository<DirectErrorReport> _queueRepository;
  final HiveListRepository<DirectErrorReport> _sentRepository;
  final SentReportsCounter _sentCounter;

  DirectErrorReportService({
    http.Client? client,
    HiveListRepository<DirectErrorReport>? queueRepository,
    HiveListRepository<DirectErrorReport>? sentRepository,
    SentReportsCounter? sentCounter,
  }) : _client = client ?? http.Client(),
       _sentCounter = sentCounter ?? SentReportsCounter(boxName: queueBoxName),
       _queueRepository =
           queueRepository ??
           HiveListRepository<DirectErrorReport>(
             boxName: queueBoxName,
             key: pendingReportsKey,
             fromJson: DirectErrorReport.fromJson,
             toJson: (report) => report.toJson(),
           ),
       _sentRepository =
           sentRepository ??
           HiveListRepository<DirectErrorReport>(
             boxName: queueBoxName,
             key: sentReportsKey,
             fromJson: DirectErrorReport.fromJson,
             toJson: (report) => report.toJson(),
           );

  /// לקריאה לפני onWindowClose במופע הארוך-טווח (של `startAutomaticFlush`):
  /// ב-Windows admin install ניקוי socket handles ביציאה תוקע לכמה שניות.
  Future<void> closeHttpClient() async {
    _client.close();
  }

  String get senderEmail =>
      (Settings.getValue<String>(
                SettingsRepository.keyErrorReportSenderEmail,
              ) ??
              '')
          .trim();

  bool get queueWhenOfflineEnabled =>
      Settings.getValue<bool>(
        SettingsRepository.keyQueueErrorReportsWhenOffline,
      ) ??
      true;

  bool get _isOfflineMode =>
      Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

  Future<void> saveSenderEmail(String email) async {
    await Settings.setValue(
      SettingsRepository.keyErrorReportSenderEmail,
      email.trim(),
    );
  }

  Future<void> clearSenderEmail() async {
    await Settings.setValue(SettingsRepository.keyErrorReportSenderEmail, '');
  }

  Future<void> setQueueWhenOfflineEnabled(bool value) async {
    await Settings.setValue(
      SettingsRepository.keyQueueErrorReportsWhenOffline,
      value,
    );
  }

  Future<int> getPendingReportsCount() async {
    final reports = await _queueRepository.load();
    return reports.length;
  }

  Future<List<DirectErrorReport>> getPendingReports() async {
    return _queueRepository.load();
  }

  Future<List<DirectErrorReport>> getSentReports() async {
    return _sentRepository.load();
  }

  Future<void> deleteSentReport(String reportId) async {
    final reports = await _sentRepository.load();
    reports.removeWhere((report) => report.id == reportId);
    await _sentRepository.overwrite(reports);
  }

  /// כל הדיווחים שנשלחו אי-פעם — לא רק אלה שנשארו בהיסטוריה.
  Future<int> getSentReportsTotal() async {
    final total = await _sentCounter.read();
    final kept = _sentReportsCount(await _sentRepository.load());
    return total > kept ? total : kept;
  }

  Future<void> clearSentReports() async {
    await _sentRepository.clear();
    await _sentCounter.reset();
  }

  /// מעדכן דיווח בתור. תוכן ששונה מקבל `report_id` חדש: ייתכן שהגרסה הקודמת
  /// כבר נקלטה בשרת, ואותו מזהה עם תוכן אחר נדחה שם ב-409.
  Future<void> updatePendingReport(DirectErrorReport report) async {
    final reports = await _queueRepository.load();
    final index = reports.indexWhere((item) => item.id == report.id);
    if (index == -1) {
      return;
    }

    final previousDigest = _digestOrNull(reports[index]);
    final contentChanged =
        previousDigest == null || previousDigest != _digestOrNull(report);
    reports[index] = contentChanged
        ? report.withId(DirectErrorReport.generateId(report.id))
        : report;
    await _queueRepository.overwrite(reports);
  }

  /// 409 = התוכן הזה לא נקלט; שליחתו מחדש היא הגשה חדשה, ולכן במזהה חדש (§2.3).
  /// ידני — כדי שלא יישלח שוב אוטומטית (409 הוא כשל קבוע, §2.4).
  static DirectErrorReport _withNewIdAfterConflict(DirectErrorReport report) =>
      report
          .withId(DirectErrorReport.generateId(report.id))
          .copyWith(queueType: DirectErrorReportQueueType.manual);

  /// null לדיווח שאינו ניתן לסריאליזציה קנונית (surrogate בודד).
  static String? _digestOrNull(DirectErrorReport report) {
    try {
      return report.contentDigest;
    } on ArgumentError {
      return null;
    }
  }

  Future<void> deletePendingReport(String reportId) async {
    final reports = await _queueRepository.load();
    reports.removeWhere((report) => report.id == reportId);
    await _queueRepository.overwrite(reports);
  }

  /// מסמן דיווח מהתור כנשלח ידנית: מעביר אותו להיסטוריית הנשלחים
  /// ומסיר אותו מהתור, מבלי לפנות לשרת.
  Future<void> markPendingReportAsSent(DirectErrorReport report) async {
    await _saveSentReport(report);
    await deletePendingReport(report.id);
  }

  Future<void> queueReport(
    DirectErrorReport report, {
    DirectErrorReportQueueType queueType = DirectErrorReportQueueType.manual,
  }) async {
    await _enqueueIfNeeded(report, queueType: queueType);
  }

  Future<void> clearPendingReports() async {
    await _queueRepository.clear();
  }

  Future<DirectReportDeliveryResult> submitPendingReport(
    DirectErrorReport report,
  ) async {
    final result = await submitReport(report);
    if (result.isSent) {
      await deletePendingReport(report.id);
    } else if (result.isIdConflict) {
      final reports = await _queueRepository.load();
      final index = reports.indexWhere((item) => item.id == report.id);
      if (index != -1) {
        reports[index] = _withNewIdAfterConflict(reports[index]);
        await _queueRepository.overwrite(reports);
      }
      return DirectReportDeliveryResult.failed(
        ReportMessages.pendingReportIdConflict,
        isIdConflict: true,
      );
    }
    return result;
  }

  /// סקריפט שליחה קריא (ללא Base64) של הדיווחים השמורים למחשב המחובר; התוצאה
  /// מוצגת בחלון מערכת כדי להימנע מג'יבריש עברית בקונסול.
  OfflineSendScript buildOfflineSendScript(
    List<DirectErrorReport> reports, {
    required OfflineSendScriptTarget target,
  }) {
    // דיווח פסול היה נדחה בשרת ממילא; הוא נשאר בתור לעריכה ולא מפיל את הייצוא.
    final sendable = reports.where((r) => _digestOrNull(r) != null).toList();
    return buildOfflineReportScript(
      target: target,
      endpoint: _endpoint,
      payloads: sendable.map((report) => report.toApiPayload()).toList(),
      ids: sendable.map((report) => report.id).toList(),
      idField: 'report_id',
      baseFileName: 'otzaria_send_saved_reports',
    );
  }

  Future<DirectReportDeliveryResult> submitReport(
    DirectErrorReport report,
  ) async {
    final directReportTargetLabel = _resolveDirectReportTargetLabel(report);

    if (_isOfflineMode) {
      if (!queueWhenOfflineEnabled) {
        return DirectReportDeliveryResult.failed(
          ReportMessages.offlineQueueDisabled,
        );
      }

      await _enqueueIfNeeded(
        report,
        queueType: DirectErrorReportQueueType.automaticRetry,
      );
      return DirectReportDeliveryResult.queued(
        ReportMessages.queuedOffline(directReportTargetLabel),
      );
    }

    final attemptResult = await _trySend(report);
    if (attemptResult.isSuccess) {
      final sentRecord = _sentRecord(report, attemptResult);
      await _saveSentReport(sentRecord);
      unawaited(flushPendingReports(onlyAutomaticRetry: true));
      if (sentRecord.serverAcceptedCorrection == false) {
        return DirectReportDeliveryResult.sent(
          ReportMessages.correctionNotSupportedByServer(
            directReportTargetLabel,
          ),
          isDuplicate: attemptResult.isDuplicate,
          correctionNotSupported: true,
        );
      }
      if (attemptResult.isDuplicate) {
        return DirectReportDeliveryResult.sent(
          ReportMessages.duplicateReport(directReportTargetLabel),
          isDuplicate: true,
        );
      }
      if (_isSefariaReport(report)) {
        return DirectReportDeliveryResult.sent(ReportMessages.sentToSefaria);
      }

      return DirectReportDeliveryResult.sent(ReportMessages.sentToOtzaria);
    }

    if (attemptResult.isPermanentFailure) {
      return DirectReportDeliveryResult.failed(
        attemptResult.message,
        isIdConflict: attemptResult.isIdConflict,
      );
    }

    await _enqueueIfNeeded(
      report,
      queueType: DirectErrorReportQueueType.automaticRetry,
    );
    return DirectReportDeliveryResult.queued(
      ReportMessages.queuedAfterFailure(directReportTargetLabel),
    );
  }

  bool _isSefariaReport(DirectErrorReport report) {
    // הכלה ולא התאמה מדויקת: זהה לניתוב המייל בשרת (getEmailRecipients).
    return report.sourceFolder.trim().toLowerCase().contains('sefaria');
  }

  String _resolveDirectReportTargetLabel(DirectErrorReport report) {
    return _isSefariaReport(report)
        ? _sefariaDirectReportTarget
        : _otzariaDirectReportTarget;
  }

  Future<int> flushPendingReports({
    bool onlyAutomaticRetry = false,
  }) async {
    if (_isOfflineMode || _isFlushing) {
      return 0;
    }

    _isFlushing = true;
    final inFlight = _flushInFlight = Completer<void>();
    try {
      final pendingReports = await _queueRepository.load();
      if (pendingReports.isEmpty) {
        return 0;
      }

      final reportsToAttempt = onlyAutomaticRetry
          ? pendingReports
                .where(
                  (report) =>
                      report.queueType ==
                      DirectErrorReportQueueType.automaticRetry,
                )
                .take(_maxQueuedFlushPerRun)
                .toList()
          : pendingReports.take(_maxQueuedFlushPerRun).toList();

      if (reportsToAttempt.isEmpty) {
        return 0;
      }

      final remainingReports = List<DirectErrorReport>.from(pendingReports);
      var sentCount = 0;

      for (final report in reportsToAttempt) {
        final attemptResult = await _trySend(report);

        if (attemptResult.isSuccess) {
          remainingReports.removeWhere((item) => item.id == report.id);
          await _saveSentReport(_sentRecord(report, attemptResult));
          sentCount++;
          continue;
        }

        if (attemptResult.isIdConflict) {
          final index = remainingReports.indexWhere((r) => r.id == report.id);
          remainingReports[index] = _withNewIdAfterConflict(report);
          continue;
        }

        if (attemptResult.isPermanentFailure) {
          // לא חוזר לתור (§2.4), אבל נשמר בהיסטוריה כנדחה — אחרת ההצעה אובדת בשקט.
          remainingReports.removeWhere((item) => item.id == report.id);
          await _saveSentReport(
            report.copyWith(rejectionReason: attemptResult.message),
            countAsSent: false,
          );
          continue;
        }

        break;
      }

      await _queueRepository.overwrite(remainingReports);
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

    unawaited(flushPendingReports(onlyAutomaticRetry: true));
    _flushTimer = Timer.periodic(_flushInterval, (_) {
      unawaited(flushPendingReports(onlyAutomaticRetry: true));
    });
  }

  static bool isValidSenderEmail(String email) {
    final normalized = email.trim();
    if (normalized.isEmpty) {
      return false;
    }

    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized);
  }

  Future<void> _enqueueIfNeeded(
    DirectErrorReport report, {
    required DirectErrorReportQueueType queueType,
  }) async {
    final pendingReports = await _queueRepository.load();
    final alreadyQueued = pendingReports.any((item) => item.id == report.id);
    if (alreadyQueued) {
      return;
    }

    pendingReports.add(report.copyWith(queueType: queueType));
    await _queueRepository.overwrite(pendingReports);
  }

  Future<void> _saveSentReport(
    DirectErrorReport report, {
    bool countAsSent = true,
  }) async {
    final sentReports = await _sentRepository.load();
    final kept = _sentReportsCount(sentReports);
    final isNew = sentReports.every((item) => item.id != report.id);
    sentReports.removeWhere((item) => item.id == report.id);
    sentReports.insert(0, report);
    if (sentReports.length > maxSentReportsToKeep) {
      sentReports.removeRange(maxSentReportsToKeep, sentReports.length);
    }
    await _sentRepository.overwrite(sentReports);
    if (countAsSent && isNew) await _sentCounter.increment(floor: kept);
  }

  static int _sentReportsCount(List<DirectErrorReport> reports) =>
      reports.where((report) => report.rejectionReason == null).length;

  /// הרשומה להיסטוריית הנשלחים: הצעת תיקון מסומנת אם השרת תמך בה.
  DirectErrorReport _sentRecord(
    DirectErrorReport report,
    _SendAttemptResult attemptResult,
  ) {
    if (!report.isTextCorrection) return report;
    return report.copyWith(
      serverAcceptedCorrection: attemptResult.correctionSupported,
    );
  }

  Future<_SendAttemptResult> _trySend(DirectErrorReport report) async {
    final String body;
    try {
      body = report.apiBody;
    } on ArgumentError catch (e) {
      // טקסט שאינו ניתן לסריאליזציה קנונית (surrogate בודד) — לא ישתפר בניסיון חוזר.
      debugPrint('Direct report payload invalid: $e');
      return _SendAttemptResult.permanentFailure(ReportMessages.sendFailed);
    }

    if (utf8.encode(body).length > DirectErrorReport.maxApiBodyBytes) {
      return _SendAttemptResult.permanentFailure(
        ReportMessages.bodyTooLarge(DirectErrorReport.maxApiBodyBytes ~/ 1024),
      );
    }

    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode == HttpStatus.ok) {
        final decoded = _decodeResponse(response.body);
        return _SendAttemptResult.success(
          isDuplicate: decoded?['duplicate'] == true,
          correctionSupported: decoded?['correction_supported'] == true,
        );
      }

      if (response.statusCode == HttpStatus.conflict) {
        return _SendAttemptResult.permanentFailure(
          ReportMessages.reportIdConflict,
          isIdConflict: true,
        );
      }

      if (_isPermanentHttpFailure(response.statusCode)) {
        return _SendAttemptResult.permanentFailure(
          ReportMessages.serverPermanentFailure(response.statusCode),
        );
      }

      return _SendAttemptResult.transientFailure(
        ReportMessages.serverTransientFailure(response.statusCode),
      );
    } on SocketException catch (e) {
      debugPrint('Direct report network error: $e');
      return _SendAttemptResult.transientFailure(ReportMessages.noInternet);
    } on http.ClientException catch (e) {
      debugPrint('Direct report client error: $e');
      return _SendAttemptResult.transientFailure(ReportMessages.sendFailed);
    } on TimeoutException {
      return _SendAttemptResult.transientFailure(ReportMessages.serverTimeout);
    } catch (e) {
      debugPrint('Direct report unexpected error: $e');
      return _SendAttemptResult.transientFailure(
        ReportMessages.unexpectedSendError,
      );
    }
  }

  /// חוזה §2.4: 400/409/413/422 קבועים; 408/429/5xx וכל השאר זמניים (תור).
  bool _isPermanentHttpFailure(int statusCode) {
    return statusCode == HttpStatus.badRequest ||
        statusCode == HttpStatus.conflict ||
        statusCode == HttpStatus.requestEntityTooLarge ||
        statusCode == 422;
  }

  /// גוף תשובת 200. `duplicate:true` = תוכן זהה כבר נשלח במייל (הדיווח נקלט);
  /// היעדר `correction_supported:true` = אתר ישן שאינו מכיר הצעת תיקון.
  static Map<String, dynamic>? _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

class _SendAttemptResult {
  final bool isSuccess;
  final String message;
  final _SendAttemptFailureType? failureType;
  final bool isDuplicate;
  final bool correctionSupported;
  final bool isIdConflict;

  const _SendAttemptResult._({
    required this.isSuccess,
    required this.message,
    this.failureType,
    this.isDuplicate = false,
    this.correctionSupported = false,
    this.isIdConflict = false,
  });

  const _SendAttemptResult.success({
    bool isDuplicate = false,
    bool correctionSupported = false,
  }) : this._(
         isSuccess: true,
         message: '',
         failureType: null,
         isDuplicate: isDuplicate,
         correctionSupported: correctionSupported,
       );

  bool get isPermanentFailure =>
      !isSuccess && failureType == _SendAttemptFailureType.permanent;

  factory _SendAttemptResult.transientFailure(String message) {
    return _SendAttemptResult._(
      isSuccess: false,
      message: message,
      failureType: _SendAttemptFailureType.transient,
    );
  }

  factory _SendAttemptResult.permanentFailure(
    String message, {
    bool isIdConflict = false,
  }) {
    return _SendAttemptResult._(
      isSuccess: false,
      message: message,
      failureType: _SendAttemptFailureType.permanent,
      isIdConflict: isIdConflict,
    );
  }
}

enum _SendAttemptFailureType {
  transient,
  permanent,
}
