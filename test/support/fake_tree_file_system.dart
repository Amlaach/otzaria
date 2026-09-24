import 'dart:io';

import 'package:otzaria/update/differential/tree_fs.dart';
import 'package:path/path.dart' as p;

/// מערכת קבצים לבדיקות עדכון העץ: הקבצים והתיקיות אמיתיים, ה-symlinks
/// וההרשאות בזיכרון — כך שהבדיקות רצות גם ב-Windows, שבו symlink יחסי
/// עם `/` אינו נפתח.
class FakeTreeFileSystem implements TreeFileSystem {
  /// נתיב מוחלט ← יעד.
  final Map<String, String> links = {};

  /// נתיב מוחלט ← ביטי הרשאה. קובץ שאינו כאן נחשב 0644.
  final Map<String, int> modes = {};

  static const int defaultMode = 0x1A4;

  String _key(String path) => p.normalize(p.absolute(path));

  /// קישור בנתיב יחסי ל-[root], לזריעת עץ התחלתי.
  void seedLink(Directory root, String relative, String target) {
    final path = p.join(root.path, relative);
    Directory(p.dirname(path)).createSync(recursive: true);
    links[_key(path)] = target;
  }

  void seedMode(Directory root, String relative, int mode) {
    modes[_key(p.join(root.path, relative))] = mode;
  }

  @override
  bool get tracksModes => true;

  @override
  Future<void> copyTree(String from, String to) async {
    final source = _key(from);
    final target = _key(to);
    await Directory(target).create(recursive: true);
    for (final entity in Directory(source).listSync(recursive: true)) {
      final destination = p.join(target, p.relative(entity.path, from: source));
      if (entity is Directory) {
        Directory(destination).createSync(recursive: true);
      } else if (entity is File) {
        Directory(p.dirname(destination)).createSync(recursive: true);
        entity.copySync(destination);
      }
    }
    for (final entry in {...links}.entries) {
      if (p.isWithin(source, entry.key)) {
        links[p.join(target, p.relative(entry.key, from: source))] =
            entry.value;
      }
    }
    for (final entry in {...modes}.entries) {
      if (p.isWithin(source, entry.key)) {
        modes[p.join(target, p.relative(entry.key, from: source))] =
            entry.value;
      }
    }
  }

  @override
  Future<TreeListing> list(String root) async {
    final base = _key(root);
    final files = <String, int?>{};
    for (final entity in Directory(base).listSync(recursive: true)) {
      if (entity is! File) continue;
      final key = _key(entity.path);
      files[p.relative(key, from: base).replaceAll(r'\', '/')] =
          modes[key] ?? defaultMode;
    }
    return TreeListing(
      files: files,
      links: {
        for (final entry in links.entries)
          if (p.isWithin(base, entry.key))
            p.relative(entry.key, from: base).replaceAll(r'\', '/'):
                entry.value,
      },
    );
  }

  @override
  Future<bool> isLink(String path) async => links.containsKey(_key(path));

  @override
  Future<void> createLink(String path, String target) async {
    final key = _key(path);
    if (links.containsKey(key) ||
        FileSystemEntity.typeSync(key) != FileSystemEntityType.notFound) {
      throw FileSystemException('already exists', path);
    }
    Directory(p.dirname(key)).createSync(recursive: true);
    links[key] = target;
  }

  @override
  Future<void> deleteLink(String path) async {
    if (links.remove(_key(path)) == null) {
      throw FileSystemException('not a link', path);
    }
  }

  @override
  Future<void> setModes(Map<String, int> modes) async {
    modes.forEach((path, mode) => this.modes[_key(path)] = mode);
  }

  @override
  Future<bool> isEmptyDirectory(String path) async {
    final key = _key(path);
    final dir = Directory(key);
    if (!dir.existsSync() || dir.listSync().isNotEmpty) return false;
    return !links.keys.any((link) => p.dirname(link) == key);
  }
}
