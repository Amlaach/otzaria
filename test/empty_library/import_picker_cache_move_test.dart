import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

/// issue #1360 — באנדרואיד file_picker מעתיק את הקובץ שנבחר למטמון האפליקציה,
/// והייבוא העתיק אותו משם שוב אל הספרייה: פי שניים זמן ונפח, והעותק נשאר
/// במכשיר. עותק מהמטמון מועבר (rename) ולא מועתק.
void main() {
  group('עותק file_picker במטמון (issue #1360)', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('otzaria-1360-');
      EmptyLibraryBloc.filePickerCacheDirOverride = temp.path;
    });

    tearDown(() async {
      EmptyLibraryBloc.filePickerCacheDirOverride = null;
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test(
      'isFilePickerCacheFile מזהה רק קבצים תחת <cache>/file_picker',
      () async {
        final inCache = File(
          path.join(temp.path, 'file_picker', '1700000000', 'seforim.db'),
        );
        final elsewhere = File(path.join(temp.path, 'Download', 'seforim.db'));
        expect(await EmptyLibraryBloc.isFilePickerCacheFile(inCache), isTrue);
        expect(
          await EmptyLibraryBloc.isFilePickerCacheFile(elsewhere),
          isFalse,
        );
      },
    );

    test('moveFileWithProgress מעביר את הקובץ ומסיים ב-1.0', () async {
      final source = File(path.join(temp.path, 'src.bin'));
      await source.writeAsBytes(List<int>.generate(1024, (i) => i % 251));
      final dest = path.join(temp.path, 'dst.bin');
      final progress = <double>[];

      await EmptyLibraryBloc.moveFileWithProgress(
        source,
        dest,
        onProgress: progress.add,
      );

      expect(await source.exists(), isFalse);
      expect(await File(dest).length(), 1024);
      expect(progress.last, 1.0);
    });

    test('ייבוא מעותק המטמון מעביר את seforim.db ולא משאיר עותק', () async {
      final cacheCopyDir = Directory(
        path.join(temp.path, 'file_picker', '1700000000'),
      );
      await cacheCopyDir.create(recursive: true);
      final cacheDb = File(
        path.join(cacheCopyDir.path, DatabaseConstants.databaseFileName),
      );
      await cacheDb.writeAsBytes(List<int>.filled(4096, 7));
      final targetDir = Directory(path.join(temp.path, 'library'));

      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
      final bloc = EmptyLibraryBloc();
      addTearDown(bloc.close);
      final selected = bloc.stream
          .where((s) => s is EmptyLibraryDirectorySelected)
          .first;

      bloc.add(
        ImportLibraryFolderRequested(
          sourceFolder: cacheCopyDir.path,
          targetPath: targetDir.path,
        ),
      );
      await selected.timeout(const Duration(seconds: 20));

      final targetDb = File(
        path.join(targetDir.path, DatabaseConstants.databaseFileName),
      );
      expect(await targetDb.length(), 4096);
      expect(
        await cacheDb.exists(),
        isFalse,
        reason: 'העותק במטמון אמור להיות מועבר, לא מועתק',
      );
    });
  });
}
