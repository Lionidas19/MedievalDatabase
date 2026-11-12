import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The text of a screen or a dialog, selectable and copyable.
///
/// The researcher's sharpest complaint was having to retype what the app
/// showed. Flutter paints its own text, so nothing can be selected unless it
/// is asked for. This asks: round each of the three screens in
/// `home_shell.dart`, and inside each dialog a reader would copy from. The
/// table body opts out (`entry_table.dart` says why) and copies a whole row
/// instead.
///
/// **One per page, never one round the whole app.** That was tried first,
/// in `MaterialApp.builder`, and looked tidier. But a selection holds the
/// keyboard while anything is selected, and from up there it held it from
/// outside every dialog: once a reader had selected a word in a record,
/// Escape no longer closed it, and closing it no longer gave the table its
/// keys back. Inside the dialog, the dialog's own keys work as before. It
/// also leaves the navigation rail and the app bar out of a selection,
/// which otherwise picked up "Advanced Search" from the rail whenever a drag
/// passed its height.
class AppSelection extends StatefulWidget {
  const AppSelection({super.key, required this.child});
  final Widget child;

  @override
  State<AppSelection> createState() => _AppSelectionState();
}

class _AppSelectionState extends State<AppSelection> {
  /// The selection takes focus so that Ctrl+C reaches it, but it is not
  /// somewhere Tab should stop: a stop there would highlight a whole page.
  /// Out of traversal it is also out of the browser's focus-on-arrival pass,
  /// which otherwise measured it before it had been laid out and threw.
  final _focus = FocusNode(debugLabel: 'selection', skipTraversal: true);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionArea(
    focusNode: _focus,
    child: CopyLayout(child: widget.child),
  );
}

/// Copies the text inside it with the shape it had on screen.
///
/// Flutter joins the pieces of a selection with nothing between them, so a
/// record's dialog came out as `Year1270PlaceKaynham, Yorkshire` and two
/// paragraphs as `sold by.There are`. Inside this, a piece that starts below
/// the one before it starts a new line, and a piece beside it on the same
/// line is separated by a tab. A label and its value therefore paste into a
/// spreadsheet as two cells of one row, and into a document as a line that
/// still reads.
///
/// **It has to go inside every scrolling page, not just round the app.** A
/// scroll view gathers the text within it into a selection of its own and
/// joins it there, Flutter's way, before anything outside ever sees the
/// pieces. Round the app alone, this fixed nothing that scrolls, which is
/// nearly everything. Put it directly round a scroll view's content.
class CopyLayout extends StatefulWidget {
  const CopyLayout({super.key, required this.child});
  final Widget child;

  @override
  State<CopyLayout> createState() => _CopyLayoutState();
}

class _CopyLayoutState extends State<CopyLayout> {
  final _delegate = _LaidOutSelection();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _delegate, child: widget.child);
}

class _LaidOutSelection extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final buffer = StringBuffer();
    Rect? previous;
    for (final selectable in selectables) {
      final content = selectable.getSelectedContent();
      if (content == null || content.plainText.isEmpty) continue;
      final rect = _onScreen(selectable);
      if (previous != null) {
        // Two pixels of grace: lines of different sizes that sit on one row
        // do not share a top to the pixel.
        final below = rect != null && rect.top >= previous.bottom - 2;
        buffer.write(below ? '\n' : '\t');
      }
      buffer.write(content.plainText);
      previous = rect ?? previous;
    }
    return buffer.isEmpty
        ? null
        : SelectedContent(plainText: buffer.toString());
  }

  static Rect? _onScreen(Selectable selectable) {
    final boxes = selectable.boundingBoxes;
    if (boxes.isEmpty) return null;
    final local = boxes.reduce((a, b) => a.expandToInclude(b));
    return MatrixUtils.transformRect(selectable.getTransformTo(null), local);
  }
}
