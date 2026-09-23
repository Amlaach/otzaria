import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:test/test.dart';

void main() {
  test('כל TextPainter ב-lib מקבל textDirection', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final parsed = parseString(
        content: entity.readAsStringSync(),
        path: entity.path,
      );
      parsed.unit.accept(
        _TextPainterDirectionVisitor(entity.path, parsed.lineInfo, hits),
      );
    }

    expect(
      hits,
      isEmpty,
      reason:
          'TextPainter חייב לקבל textDirection לפני layout():\n'
          '${hits.join('\n')}',
    );
  });
}

class _TextPainterDirectionVisitor extends RecursiveAstVisitor<void> {
  _TextPainterDirectionVisitor(this.path, this.lineInfo, this.hits);

  final String path;
  final LineInfo lineInfo;
  final List<String> hits;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'TextPainter' &&
        !node.argumentList.arguments.whereType<NamedArgument>().any(
          (argument) => argument.name.lexeme == 'textDirection',
        )) {
      hits.add('$path:${lineInfo.getLocation(node.offset).lineNumber}');
    }
    super.visitInstanceCreationExpression(node);
  }
}
