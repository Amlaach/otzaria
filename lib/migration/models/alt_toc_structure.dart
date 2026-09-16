import 'package:equatable/equatable.dart';

class AltTocStructure extends Equatable {
  final int id;
  final int bookId;
  final String key;
  final String? title;
  final String? heTitle;

  /// המבנה נקרא מ-user_books.db — מזהיו במרחב אחר מזה של הספרייה הרשמית.
  final bool isUserBook;

  const AltTocStructure({
    required this.id,
    required this.bookId,
    required this.key,
    this.title,
    this.heTitle,
    this.isUserBook = false,
  });

  factory AltTocStructure.fromJson(Map<String, dynamic> json) {
    return AltTocStructure(
      id: json['id'] as int,
      bookId: json['bookId'] as int,
      key: json['key'] as String,
      title: json['title'] as String?,
      heTitle: json['heTitle'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookId': bookId,
      'key': key,
      'title': title,
      'heTitle': heTitle,
    };
  }

  @override
  List<Object?> get props => [id, bookId, key, title, heTitle, isUserBook];
}
