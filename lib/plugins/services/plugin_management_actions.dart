import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/settings/services/safer_file_picker.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/widgets/ui_snack.dart';

/// פעולות מנוהלות של התקנה וטעינת תוספים, המבטיחות חסימה במצב קיוסק ואימות במצב סייפר
/// ומאחדות את המימוש בין ToolsLauncherPanel ו-PluginSidePanel.
class PluginManagementActions {
  const PluginManagementActions._();

  /// מתקין תוסף מקובץ .otzplugin
  static Future<void> installPlugin(BuildContext context) async {
    if (isKioskMode) {
      UiSnack.show('התקנת תוספים חסומה במצב קיוסק');
      return;
    }

    final result = await SaferFilePicker.pickFile(
      context: context,
      type: FileType.custom,
      allowedExtensions: ['otzplugin'],
    );
    final path = result?.path;
    if (path != null && context.mounted) {
      context.read<PluginSystemBloc>().add(InstallPluginRequested(path));
    }
  }

  /// טוען תוסף פיתוח מקומי מתיקייה
  static Future<void> loadDevPlugin(BuildContext context) async {
    if (isKioskMode) {
      UiSnack.show('טעינת תוספי פיתוח חסומה במצב קיוסק');
      return;
    }

    final rootPath = await SaferFilePicker.getDirectoryPath(
      context: context,
    );
    if (rootPath != null && context.mounted) {
      context.read<PluginSystemBloc>().add(
        LoadDevelopmentPluginRequested(rootPath),
      );
    }
  }

  /// טוען תוסף מכתובת localhost
  static Future<void> loadLocalhostPlugin(BuildContext context) async {
    if (isKioskMode) {
      UiSnack.show('טעינת תוספי localhost חסומה במצב קיוסק');
      return;
    }

    final verified = await verifySaferModePassword(context);
    if (!verified || !context.mounted) return;

    final bloc = context.read<PluginSystemBloc>();
    final url = await showInputDialog(
      context: context,
      title: 'טעינת תוסף מ-localhost',
      labelText: 'Base URL',
      hintText: 'http://localhost:3000',
      initialValue: 'http://localhost:3000',
      cancelText: 'ביטול',
      confirmText: 'טען',
    );
    if (url != null && url.isNotEmpty) {
      bloc.add(LoadLocalhostPluginRequested(url));
    }
  }
}
