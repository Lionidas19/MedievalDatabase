import 'package:flutter/material.dart';

import '../models/models.dart';

/// `Food / Grain / **Wheat**` — the thing itself, set apart from its path.
///
/// Every item in this database is three levels deep, and reading it as one
/// grey run of text makes the wrong part loudest: `Food / Grain / Wheat` and
/// `Food / Grain / Barley` are nine identical characters followed by the only
/// ones that matter. Watching people use the app, that is exactly what went
/// wrong — the category read as the subject and the specific went unnoticed.
///
/// So the specific carries the weight and the path recedes behind it. The
/// path is not dropped: `Grain / Wheat` and `Nails / Wheat`-shaped collisions
/// are real, and a historian needs to see which branch a record sits on.
///
/// The specific is emphasised by **weight and contrast rather than by size**.
/// A larger glyph here would change the line height of every row in a table
/// of 7,800, which is a high price for emphasis that weight already buys;
/// pass a larger [style] where there is room for one, as the details dialog
/// does.
class ItemLabel extends StatelessWidget {
  const ItemLabel({
    super.key,
    required this.entry,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.emphasise = false,
  });

  final PriceEntry entry;
  final TextStyle? style;

  /// Set the specific a size larger as well as bolder.
  ///
  /// The researcher asked for bold and "possibly even a larger font size".
  /// Off in the table, where a taller glyph would change the line height of
  /// every one of 7,501 rows for the sake of one column; on in the cards and
  /// the record view, which lay out around their content and have the room.
  final bool emphasise;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = style ?? DefaultTextStyle.of(context).style;

    final parts = [entry.category, entry.subcategory, entry.specific]
        .where((p) => p != null && p.isNotEmpty)
        .cast<String>()
        .toList();

    if (parts.isEmpty) {
      return Text('—', style: base, maxLines: maxLines, overflow: overflow);
    }

    final lead = parts.sublist(0, parts.length - 1);
    final subject = parts.last;

    return Text.rich(
      TextSpan(
        children: [
          if (lead.isNotEmpty)
            TextSpan(
              text: '${lead.join(' / ')} / ',
              style: base.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
                fontSize: (base.fontSize ?? 14) * 0.92,
              ),
            ),
          TextSpan(
            text: subject,
            style: base.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: emphasise
                  ? (base.fontSize ?? 14) * 1.15
                  : base.fontSize,
            ),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
