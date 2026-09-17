import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/library_browser.dart';

Category _category(String title, {Category? parent}) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [],
    parent: parent,
  );
  parent?.subCategories.add(category);
  return category;
}

void main() {
  group('categoryParentPath', () {
    test('מחזיר את שרשרת האבות בלי קטגוריית השורש', () {
      final library = Library(categories: []);
      final top = _category('הלכה', parent: library);
      final middle = _category('אחרונים', parent: top);
      final leaf = _category('משנה ברורה', parent: middle);

      expect(categoryParentPath(leaf), 'הלכה, אחרונים');
    });

    test('קטגוריה ישירות תחת השורש מחזירה נתיב ריק', () {
      final library = Library(categories: []);
      final top = _category('הלכה', parent: library);

      expect(categoryParentPath(top), '');
    });

    // Library היא ההורה של עצמה; בלי בדיקת הזהות הבדיקות כאן נתקעות לנצח
    // ומרוקנות את הזיכרון (התקיעה בחיפוש בספרייה בתצוגת רשימה, issue #1374).
    test('שורש שהוא ההורה של עצמו אינו מייצר לולאה אינסופית', () {
      final library = Library(categories: []);

      expect(categoryParentPath(library), '');
    });
  });
}
