import 'package:flutter/material.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';

/// מחזירה האם כותרת סימנייה תואמת לשאילתת החיפוש, עם נורמליזציה כמו באיתור
/// (הסרת ניקוד וגרשיים) כך שכותרות עבריות יימצאו גם ללא תווים אלו.
bool pdfOutlineTitleMatchesQuery(String title, String rawQuery) {
  final normalizedQuery = normalizeFindText(rawQuery);
  if (normalizedQuery.isEmpty) return true;
  return findNormalizedTextMatches(
    normalizedQuery: normalizedQuery,
    normalizedPrimaryText: normalizeFindText(title),
  );
}

class OutlineView extends StatefulWidget {
  const OutlineView({
    super.key,
    required this.outline,
    required this.controller,
    required this.focusNode,
    this.title,
    this.isPaneOpen = true,
    this.onNavigateToPage,
  });

  final List<PdfOutlineNode>? outline;
  final PdfViewerController controller;
  final FocusNode focusNode;

  /// כותרת ראשית מעל הרשימה (שם הספר).
  final String? title;

  /// האם הפאנל הצדדי פתוח. כשהוא סגור אין לגלול (הגלילה נכשלת ומשבשת
  /// את ה-guard), וברגע הפתיחה יש לגלול למיקום הנוכחי.
  final bool isPaneOpen;
  final Future<void> Function(int pageNumber)? onNavigateToPage;

  @override
  State<OutlineView> createState() => _OutlineViewState();
}

class _OutlineViewState extends State<OutlineView>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController searchController = TextEditingController();

  final ScrollController _tocScrollController = ScrollController();
  final Map<PdfOutlineNode, GlobalKey> _tocItemKeys = {};
  bool _isManuallyScrolling = false;
  int? _lastScrolledPage;
  final Map<PdfOutlineNode, bool> _expanded = {};
  final Map<PdfOutlineNode, ExpansibleController> _controllers = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // ה-listener נורה רק על שינוי ב-controller; אם הוא כבר מוכן בעת
    // פתיחת הפאנל, יש לגלול ראשונית למיקום הנוכחי.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToActiveItem();
    });
  }

  @override
  void didUpdateWidget(covariant OutlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    // מעבר הפאנל מסגור לפתוח: גלילה מחדש למיקום הנוכחי. ה-guard
    // עלול לחסום אחרת אם נשבש ברקע בזמן שהפאנל היה סגור.
    if (!oldWidget.isPaneOpen && widget.isPaneOpen) {
      _lastScrolledPage = null;
      _scrollToActiveItem();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _tocScrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      _scrollToActiveItem();
    }
  }

  void _ensureParentsOpen(
    List<PdfOutlineNode> nodes,
    PdfOutlineNode targetNode,
  ) {
    final path = _findPath(nodes, targetNode);
    if (path.isEmpty) return;

    // מוצא את הרמה של הצומת היעד
    int targetLevel = _getNodeLevel(nodes, targetNode);

    // אם הצומת ברמה 2 ומעלה (שזה רמה 3 ומעלה בספירה רגילה), פתח את כל ההורים
    if (targetLevel >= 2) {
      for (final node in path) {
        if (node.children.isNotEmpty && _expanded[node] != true) {
          _expanded[node] = true;
          _controllers[node]?.expand();
        }
      }
    }
  }

  int _getNodeLevel(
    List<PdfOutlineNode> nodes,
    PdfOutlineNode targetNode, [
    int currentLevel = 0,
  ]) {
    for (final node in nodes) {
      if (node == targetNode) {
        return currentLevel;
      }

      final childLevel = _getNodeLevel(
        node.children,
        targetNode,
        currentLevel + 1,
      );
      if (childLevel != -1) {
        return childLevel;
      }
    }
    return -1;
  }

  List<PdfOutlineNode> _findPath(
    List<PdfOutlineNode> nodes,
    PdfOutlineNode targetNode,
  ) {
    for (final node in nodes) {
      if (node == targetNode) {
        return [node];
      }

      final subPath = _findPath(node.children, targetNode);
      if (subPath.isNotEmpty) {
        return [node, ...subPath];
      }
    }
    return [];
  }

  void _scrollToActiveItem() {
    if (_isManuallyScrolling || !widget.isPaneOpen) return;
    if (!widget.controller.isReady) return;

    final currentPage = widget.controller.pageNumber;
    if (currentPage == _lastScrolledPage) return;

    PdfOutlineNode? activeNode;

    PdfOutlineNode? findClosestNode(List<PdfOutlineNode> nodes, int page) {
      PdfOutlineNode? bestMatch;
      for (final node in nodes) {
        if (node.dest?.pageNumber != null && node.dest!.pageNumber <= page) {
          bestMatch = node;
          final childMatch = findClosestNode(node.children, page);
          if (childMatch != null) {
            bestMatch = childMatch;
          }
        } else {
          break;
        }
      }
      return bestMatch;
    }

    if (widget.outline != null && currentPage != null) {
      activeNode = findClosestNode(widget.outline!, currentPage);
    }

    if (activeNode != null && widget.outline != null) {
      _ensureParentsOpen(widget.outline!, activeNode);
    }

    // קריאה ל-setState כדי לוודא שהפריט הנכון מודגש לפני הגלילה
    if (mounted) {
      setState(() {});
    }

    if (activeNode == null) {
      _lastScrolledPage = currentPage;
      return;
    }

    // נחכה פריים אחד כדי שה-setState יסיים וה-UI יתעדכן
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isManuallyScrolling) return;

      final key = _tocItemKeys[activeNode];
      final itemContext = key?.currentContext;
      if (itemContext == null) return;

      final itemRenderObject = itemContext.findRenderObject();
      if (itemRenderObject is! RenderBox) return;

      // --- התחלה: החישוב הנכון והבדוק ---
      // זהו החישוב מההצעה של ה-AI השני, מותאם לקוד שלנו.

      final scrollableBox =
          _tocScrollController.position.context.storageContext
                  .findRenderObject()
              as RenderBox;

      // המיקום של הפריט ביחס ל-viewport של הגלילה
      final itemOffset = itemRenderObject
          .localToGlobal(Offset.zero, ancestor: scrollableBox)
          .dy;

      // גובה ה-viewport (האזור הנראה)
      final viewportHeight = scrollableBox.size.height;

      // גובה הפריט עצמו
      final itemHeight = itemRenderObject.size.height;

      // מיקום היעד המדויק למירוכז
      final target =
          _tocScrollController.offset +
          itemOffset -
          (viewportHeight / 2) +
          (itemHeight / 2);
      // --- סיום: החישוב הנכון והבדוק ---

      _tocScrollController.animateTo(
        target.clamp(
          0.0,
          _tocScrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

      _lastScrolledPage = currentPage;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final outline = widget.outline;
    if (outline == null || outline.isEmpty) {
      return const Center(
        child: Text('אין תוכן עניינים'),
      );
    }

    final delegate = NavPanelSearchDelegate(
      controller: searchController,
      hintText: 'חיפוש סימניה...',
      focusNode: widget.focusNode,
      onChanged: (value) => setState(() {}),
      onSubmitted: (_) => widget.focusNode.requestFocus(),
      onClear: () => setState(() {}),
    );

    return NavPanelCollapsibleSearch(
      delegate: delegate,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _isManuallyScrolling = true;
          } else if (notification is ScrollEndNotification) {
            _isManuallyScrolling = false;
          }
          return false;
        },
        child: searchController.text.isEmpty
            ? _buildOutlineList(outline)
            : _buildFilteredOutlineList(outline),
      ),
    );
  }

  Widget _buildOutlineList(List<PdfOutlineNode> outline) {
    return NavTreeFocusGroup(
      child: SingleChildScrollView(
        controller: _tocScrollController,
        padding: kNavTreeListPadding,
        child: Column(
          children: [
            NavTreeHeader(
              title: widget.title ?? '',
              trailing: const NavPanelSearchToggle(),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: outline.length,
              itemBuilder: (context, index) => _buildOutlineItem(
                outline[index],
                level: 0,
                isFirstChild: index == 0,
                isGroupStart: index == 0,
                isGroupEnd: index == outline.length - 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredOutlineList(List<PdfOutlineNode>? outline) {
    List<({PdfOutlineNode node, int level})> allNodes = [];
    void getAllNodes(List<PdfOutlineNode>? outline, int level) {
      if (outline == null) return;
      for (var node in outline) {
        allNodes.add((node: node, level: level));
        getAllNodes(node.children, level + 1);
      }
    }

    getAllNodes(widget.outline, 0);

    final filteredNodes = allNodes
        .where(
          (item) => pdfOutlineTitleMatchesQuery(
            item.node.title,
            searchController.text,
          ),
        )
        .toList();

    return NavTreeFocusGroup(
      child: SingleChildScrollView(
        controller: _tocScrollController,
        padding: kNavTreeListPadding,
        child: Column(
          children: [
            NavTreeHeader(
              title: widget.title ?? '',
              trailing: const NavPanelSearchToggle(),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredNodes.length,
              itemBuilder: (context, index) => _buildOutlineItem(
                filteredNodes[index].node,
                level: filteredNodes[index].level,
                isGroupStart: index == 0,
                isGroupEnd: index == filteredNodes.length - 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutlineItem(
    PdfOutlineNode node, {
    int level = 0,
    bool isFirstChild = false,
    bool isGroupStart = false,
    bool isGroupEnd = false,
  }) {
    final itemKey = _tocItemKeys.putIfAbsent(node, () => GlobalKey());
    Future<void> navigateToEntry() async {
      setState(() {
        _isManuallyScrolling = false;
        _lastScrolledPage = null;
      });
      final targetPage = node.dest?.pageNumber;
      if (targetPage == null) {
        return;
      }

      final onNavigateToPage = widget.onNavigateToPage;
      if (onNavigateToPage != null) {
        await onNavigateToPage(targetPage);
        return;
      }

      await widget.controller.goToPage(pageNumber: targetPage);
    }

    final bool selected =
        widget.controller.isReady &&
        node.dest?.pageNumber == widget.controller.pageNumber;

    final hasChildren = node.children.isNotEmpty;
    final bool isExpanded = _expanded[node] ?? (level == 0 || isFirstChild);

    final tile = NavTreeTile.heading(
      title: node.title,
      level: level,
      isSelected: selected,
      isExpanded: isExpanded,
      hasChildren: hasChildren,
      onTap: navigateToEntry,
      onToggleExpand: hasChildren
          ? () => setState(() {
              _expanded[node] = !isExpanded;
            })
          : null,
    );

    if (!hasChildren) {
      return NavTreeGroupCard(
        isGroupStart: isGroupStart,
        isGroupEnd: isGroupEnd,
        child: KeyedSubtree(
          key: itemKey,
          child: tile,
        ),
      );
    }

    return Column(
      key: itemKey,
      children: [
        NavTreeGroupCard(
          isGroupStart: isGroupStart,
          isGroupEnd: isGroupEnd && !isExpanded,
          child: tile,
        ),
        if (isExpanded)
          ...node.children.asMap().entries.map(
            (e) => _buildOutlineItem(
              e.value,
              level: level + 1,
              isFirstChild: isFirstChild && e.key == 0,
              isGroupEnd: isGroupEnd && e.key == node.children.length - 1,
            ),
          ),
      ],
    );
  }
}
