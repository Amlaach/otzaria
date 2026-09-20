import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/mapped_file.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('mapped_file_test'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('maps a file and reads back the exact bytes', () {
    final random = Random(7);
    final bytes = Uint8List.fromList(
      List.generate(300 * 1024, (_) => random.nextInt(256)),
    );
    final path = p.join(dir.path, 'data.bin');
    File(path).writeAsBytesSync(bytes);

    final copy = MappedFile.use(path, (file) {
      expect(file.length, bytes.length);
      return Uint8List.fromList(file.data.asTypedList(file.length));
    });
    expect(copy, bytes);
  });

  test('the file can be replaced after unmapping (no leaked handle)', () {
    final path = p.join(dir.path, 'swap.bin');
    File(path).writeAsBytesSync([1, 2, 3, 4]);
    MappedFile.use(path, (file) => file.data.asTypedList(file.length).first);
    File(p.join(dir.path, 'new.bin'))
      ..writeAsBytesSync([9])
      ..renameSync(path);
    expect(File(path).readAsBytesSync(), [9]);
  });

  test('unmap is idempotent', () {
    final path = p.join(dir.path, 'once.bin');
    File(path).writeAsBytesSync([1, 2, 3]);
    final mapped = MappedFile.open(path)..unmap();
    mapped.unmap();
  });

  test('rejects a missing or empty file', () {
    expect(
      () => MappedFile.open(p.join(dir.path, 'nope.bin')),
      throwsA(isA<MappedFileException>()),
    );
    final empty = p.join(dir.path, 'empty.bin');
    File(empty).writeAsBytesSync(const []);
    expect(
      () => MappedFile.open(empty),
      throwsA(isA<MappedFileException>()),
    );
  });

  test('unmaps even when the body throws', () {
    final path = p.join(dir.path, 'throw.bin');
    File(path).writeAsBytesSync([1, 2, 3]);
    expect(
      () => MappedFile.use<void>(path, (_) => throw StateError('boom')),
      throwsStateError,
    );
    File(path).deleteSync();
  });
}
