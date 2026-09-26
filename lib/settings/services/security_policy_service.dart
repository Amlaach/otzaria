import 'package:flutter/material.dart';
import 'package:otzaria/main.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';

/// סוגי פעולות רגישות המבוקרות על ידי מדיניות האבטחה
enum SecurityActionType {
  fileOpen,
  fileSave,
  directoryPick,
  launchUrl,
  launchProcess,
  installPlugin,
  printDocument,
  modifySettings,
}

/// פעולה רגישה המבוקשת לביצוע
class SecurityAction {
  final SecurityActionType type;
  final String? targetResource;
  final Map<String, dynamic> metadata;

  const SecurityAction({
    required this.type,
    this.targetResource,
    this.metadata = const {},
  });

  static const fileOpen = SecurityAction(type: SecurityActionType.fileOpen);
  static const fileSave = SecurityAction(type: SecurityActionType.fileSave);
  static const directoryPick = SecurityAction(type: SecurityActionType.directoryPick);
  static const installPlugin = SecurityAction(type: SecurityActionType.installPlugin);
  static const printDocument = SecurityAction(type: SecurityActionType.printDocument);
}

/// החלטת מדיניות האבטחה לגבי פעולה
enum SecurityDecision {
  allow,
  denyKiosk,
  denyAuthenticationFailed,
  denyNullContext,
}

/// תצורת אבטחה אימוטבילית של האפליקציה (AP-01)
class AppSecurityConfig {
  final bool isKioskMode;
  final bool isSecondaryWindow;

  const AppSecurityConfig({
    this.isKioskMode = false,
    this.isSecondaryWindow = false,
  });

  static AppSecurityConfig _instance = const AppSecurityConfig();
  static AppSecurityConfig get instance => _instance;

  static void initialize({
    bool isKioskMode = false,
    bool isSecondaryWindow = false,
  }) {
    _instance = AppSecurityConfig(
      isKioskMode: isKioskMode,
      isSecondaryWindow: isSecondaryWindow,
    );
  }
}

/// ממשק מדיניות האבטחה המרכזית של האפליקציה
abstract interface class ISecurityPolicyService {
  bool get isKioskMode;
  bool isActionBlockedInKiosk(SecurityAction action);
  Future<SecurityDecision> evaluate(SecurityAction action, {BuildContext? context});
}

/// מימוש ברירת המחדל של מדיניות האבטחה
class DefaultSecurityPolicyService implements ISecurityPolicyService {
  const DefaultSecurityPolicyService();

  @override
  bool get isKioskMode => AppSecurityConfig.instance.isKioskMode;

  @override
  bool isActionBlockedInKiosk(SecurityAction action) {
    switch (action.type) {
      case SecurityActionType.fileOpen:
      case SecurityActionType.fileSave:
      case SecurityActionType.directoryPick:
      case SecurityActionType.installPlugin:
        return true;
      case SecurityActionType.launchProcess:
        return true;
      case SecurityActionType.launchUrl:
        return true;
      case SecurityActionType.printDocument:
        // הדפסת PDF מערכתית חסומה בקיוסק, הדפסה פיזית ישירה מותרת
        return action.metadata['useSystemDialog'] == true;
      case SecurityActionType.modifySettings:
        return false;
    }
  }

  @override
  Future<SecurityDecision> evaluate(
    SecurityAction action, {
    BuildContext? context,
  }) async {
    if (isKioskMode && isActionBlockedInKiosk(action)) {
      return SecurityDecision.denyKiosk;
    }

    final effectiveContext = context ?? navigatorKey.currentContext;
    if (effectiveContext == null || !effectiveContext.mounted) {
      return SecurityDecision.denyNullContext;
    }

    if (shouldRequireSaferModePassword(effectiveContext)) {
      final verified = await verifySaferModePassword(effectiveContext);
      if (!verified) {
        return SecurityDecision.denyAuthenticationFailed;
      }
    }

    return SecurityDecision.allow;
  }
}

/// שער אבטחה מרכזי (Security Gate) לביצוע פעולות מבוקרות
class SecurityGate {
  final ISecurityPolicyService policy;
  final void Function(String message)? onFeedback;

  const SecurityGate({
    this.policy = const DefaultSecurityPolicyService(),
    this.onFeedback,
  });

  Future<T?> executeGuarded<T>({
    required SecurityAction action,
    required Future<T?> Function() operation,
    BuildContext? context,
  }) async {
    final decision = await policy.evaluate(action, context: context);
    switch (decision) {
      case SecurityDecision.allow:
        return await operation();
      case SecurityDecision.denyKiosk:
        onFeedback?.call(
          action.type == SecurityActionType.fileSave
              ? 'שמירת קבצים למערכת ההפעלה חסומה בעמדה זו'
              : 'פעולה זו חסומה במצב קיוסק',
        );
        return null;
      case SecurityDecision.denyNullContext:
      case SecurityDecision.denyAuthenticationFailed:
        return null;
    }
  }
}
