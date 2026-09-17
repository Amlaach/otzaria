import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/models/crash_signature.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';

AppReport _report({
  AppReportTrigger trigger = AppReportTrigger.manual,
  String email = 'a@b.com',
  String description = 'תיאור',
  Map<String, dynamic>? diagnostics,
  String? errorLog,
}) => AppReport(
  reportId: AppReport.generateReportId(),
  type: AppReportType.crash,
  trigger: trigger,
  title: 'קריסה בפתיחת ספר',
  description: description,
  stepsToReproduce: 'צעד 1',
  reporterEmail: email,
  appVersion: '0.9.98',
  platform: 'windows',
  osVersion: 'Windows 11',
  arch: 'x64',
  signature: const CrashSignature(
    exceptionType: 'StateError',
    frames: ['A.b (package:otzaria/a.dart)'],
  ),
  sentryEventId: 'abc',
  createdAt: DateTime.utc(2026, 9, 17, 10),
  diagnostics: diagnostics,
  errorLog: errorLog,
);

void main() {
  test('toJson/fromJson שומר את כל השדות, כולל שדות התוצאה', () {
    final original =
        _report(
          diagnostics: {
            'a': 1,
            'b': ['x'],
          },
          errorLog: 'log',
        ).copyWith(
          issueNumber: 12,
          issueUrl: 'https://github.com/Otzaria/otzaria/issues/12',
          merged: true,
          issuePending: true,
          duplicate: true,
          sentAt: DateTime.utc(2026, 9, 17, 11),
        );
    final restored = AppReport.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), original.toJson());
    expect(restored.trigger, AppReportTrigger.manual);
    expect(restored.signature, original.signature);
  });

  test('toApiPayload בפורמט החוזה', () {
    final payload = _report(
      trigger: AppReportTrigger.autoCrash,
      email: '',
      diagnostics: {'x': 1},
      errorLog: 'log',
    ).toApiPayload();
    expect(payload['schema'], 1);
    expect(payload['trigger'], 'auto_crash');
    expect(payload['type'], 'crash');
    expect(payload.containsKey('reporterEmail'), isFalse);
    expect(payload['createdAt'], '2026-09-17T10:00:00.000Z');
    expect(payload['attachments'], {
      'diagnostics': {'x': 1},
      'errorLog': 'log',
    });
    expect(payload.containsKey('issueNumber'), isFalse);
  });

  test('validate: מייל ותיאור חובה רק בדיווח ידני', () {
    expect(_report().validate(), isNull);
    expect(_report(email: '').validate(), 'reporterEmail');
    expect(_report(description: ' ').validate(), 'description');
    expect(
      _report(
        trigger: AppReportTrigger.crashPrompt,
        email: '',
        description: '',
      ).validate(),
      isNull,
    );
    expect(
      _report(trigger: AppReportTrigger.autoCrash, email: 'bad').validate(),
      'reporterEmail',
    );
  });

  test('גוף גדול מדי: הלוג מקוצר מההתחלה והגוף נכנס בגבול', () {
    // לוכסן הפוך מוכפל ב-JSON, ולכן לוג בגבולו + אבחון בגבולו חורגים מהגוף.
    final bigLog = '${r'\' * 300000}NEWEST';
    final bigDiagnostics = {'blob': 'x' * 290000};
    final payload = _report(
      diagnostics: bigDiagnostics,
      errorLog: bigLog,
    ).toApiPayload();
    final size = utf8.encode(jsonEncode(payload)).length;
    expect(size, lessThanOrEqualTo(AppReport.maxBodyBytes));
    final log = (payload['attachments'] as Map)['errorLog'] as String;
    expect(log.endsWith('NEWEST'), isTrue);
    expect(
      utf8.encode(log).length,
      lessThanOrEqualTo(AppReport.maxErrorLogBytes),
    );
  });

  test('אבחון מעל 300KB מוחלף בסימון', () {
    final payload = _report(diagnostics: {'blob': 'x' * 310000}).toApiPayload();
    expect(
      (payload['attachments'] as Map)['diagnostics'],
      containsPair('truncated', true),
    );
  });

  test('withoutAttachments ו-redactedWith', () {
    final redactor = AppReportRedactor(
      environment: const {
        'USERPROFILE': r'C:\Users\Moshe',
        'USERNAME': 'Moshe',
      },
    );
    final report = _report(
      description: r'נכשל ב-C:\Users\Moshe\x, כתבו ל-z@z.com',
      diagnostics: {'p': r'C:\Users\Moshe'},
      errorLog: 'Moshe',
    );
    final redacted = report.redactedWith(redactor);
    expect(redacted.description, r'נכשל ב-%USERPROFILE%\x, כתבו ל-<email>');
    expect(redacted.diagnostics, {'p': '%USERPROFILE%'});
    expect(redacted.errorLog, '<user>');
    expect(redacted.reporterEmail, 'a@b.com');

    final stripped = report.withoutAttachments();
    expect(stripped.diagnostics, isNull);
    expect(stripped.errorLog, isNull);
  });

  test('keepTailBytes אינו חותך באמצע תו', () {
    final tail = AppReport.keepTailBytes('אבגד', 5);
    expect(tail, 'גד');
  });
  test('פריים שהוארך בהסתרה נחתך לגבול השרת (אחרת 422 ודחייה סופית)', () {
    final redactor = AppReportRedactor(environment: const {'USERNAME': 'abc'});
    final report = AppReport(
      reportId: AppReport.generateReportId(),
      type: AppReportType.crash,
      trigger: AppReportTrigger.autoCrash,
      title: 'StateError',
      appVersion: '0.9.98',
      platform: 'windows',
      createdAt: DateTime.utc(2026, 9, 17, 10),
      signature: CrashSignature(
        exceptionType: 'StateError',
        frames: ['${'x' * 295} abc', 'b', 'c', 'd'],
      ),
    ).redactedWith(redactor);
    expect(report.signature!.frames.first.length, greaterThan(300));

    final frames =
        (report.toApiPayload()['signature'] as Map)['frames'] as List;
    expect(frames, hasLength(3));
    expect(frames.every((f) => (f as String).length <= 300), isTrue);
  });
}
