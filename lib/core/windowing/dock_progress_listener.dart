import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/dock_progress.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';

/// מזין את חיווי ההתקדמות שעל אייקון ה-Dock ממצב האינדוקס.
///
/// מחוץ למק מחזיר את [child] כפי שהוא, בלי מנוי מיותר על ה-bloc.
class DockProgressListener extends StatelessWidget {
  const DockProgressListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DockProgress.isSupported) return child;
    return BlocListener<IndexingBloc, IndexingState>(
      listener: (context, state) => unawaited(_apply(state)),
      child: child,
    );
  }

  Future<void> _apply(IndexingState state) {
    if (state is! IndexingInProgress) return DockProgress.hide();
    final total = state.totalBooks ?? 0;
    final processed = state.booksProcessed ?? 0;
    // לסריקה ולאיחוד האינדקס אין התקדמות מדידה — שם החיווי בלתי-מוגדר.
    final measurable = total > 0 && !state.isScanning && !state.isFinalizing;
    return DockProgress.show(value: measurable ? processed / total : null);
  }
}
