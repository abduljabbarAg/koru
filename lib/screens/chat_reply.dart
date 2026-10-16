import 'package:flutter/material.dart';

import '../theme.dart';

/// Renders the small amount of markdown a chat reply actually uses.
///
/// Deliberately not a markdown parser. Bold, italics, bullets, numbered steps
/// and headings are what models reach for; tables, links, images and HTML are
/// what a full renderer would also accept, and on a phone a link someone did
/// not ask for is a worse failure than an unrendered pipe character.
///
/// Streaming is the constraint that shapes this. The text arrives a token at a
/// time, so an unterminated "**" has to render as literal asterisks until the
/// closing pair turns up, or the answer visibly flickers between two layouts as
/// it is written. A pattern that does not close is therefore not styled at all.
/// Public because it is testable on its own and is the shape any reply in the
/// app should have. A renderer this fussy about streaming is not something to
/// verify only through a chat bubble.
///
/// Lives beside the chat screen rather than inside it so that the thread's
/// layout and the way a reply is set can change for different reasons. The two
/// used to be one file, and a reply arriving token by token re-ran the same
/// three hundred lines that decide how the composer looks.
class RichReply extends StatelessWidget {
  const RichReply({super.key, required this.text, required this.muted});

  final String text;

  /// True while the reply is still arriving, so the finished answer does not
  /// appear suddenly darker than the one being written above it.
  final bool muted;

  /// The column a bullet or a number sits in.
  ///
  /// One width for both, so the text of a bulleted list and the text of a
  /// numbered one start at the same place. Sized for a two-digit step, because
  /// a column that fits "1." and overflows "10." throws the list's alignment
  /// away exactly on the answers that are long enough to be numbered to ten.
  static const double markerWidth = 24;

  @override
  Widget build(BuildContext context) {
    final base = KoruType.bodyStrong.copyWith(
      color: muted ? KoruColors.inkFaint : KoruColors.ink,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _blocks(text, base),
    );
  }

  /// Splits [text] into paragraphs and returns a widget per line.
  List<Widget> _blocks(String raw, TextStyle base) {
    final out = <Widget>[];
    final lines = raw.split('\n');

    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.trim().isEmpty) {
        if (out.isNotEmpty) out.add(const SizedBox(height: KoruSpace.sm));
        continue;
      }

      final bullet = RegExp(r'^\s*[-*+]\s+').firstMatch(trimmed);
      final numbered = RegExp(r'^\s*\d+[.)]\s+').firstMatch(trimmed);

      if (bullet != null) {
        out.add(_row('\u2022', trimmed.substring(bullet.end), base));
        continue;
      }
      if (numbered != null) {
        final n = RegExp(r'^\s*(\d+)').firstMatch(trimmed)!.group(1)!;
        out.add(_row('$n.', trimmed.substring(numbered.end), base));
        continue;
      }

      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        out.add(Padding(
          padding: const EdgeInsets.only(top: KoruSpace.xsm, bottom: KoruSpace.xxs),
          child: _InlineText(
            _inline(heading.group(2)!),
            style: base.copyWith(
              fontWeight: FontWeight.w700,
              // A heading takes its size from the type scale rather than a
              // number chosen here, so it cannot drift from the prose it
              // interrupts by half a pixel.
              fontSize: level == 1
                  ? KoruType.rowTitle.fontSize
                  : KoruType.bodyStrong.fontSize,
            ),
          ),
        ));
        continue;
      }

      out.add(Padding(
        padding: const EdgeInsets.only(bottom: KoruSpace.xxs),
        child: _InlineText(_inline(trimmed), style: base),
      ));
    }
    return out;
  }

  Widget _row(String marker, String body, TextStyle base) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoruSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: markerWidth,
            child: Text(
              marker,
              style: base.copyWith(color: KoruColors.inkFaint),
            ),
          ),
          Expanded(child: _InlineText(_inline(body), style: base)),
        ],
      ),
    );
  }

  /// The one inline pass: **bold**, *italic* and `code`.
  ///
  /// Rewrites the matched text to a tag the next pass knows how to style.
  /// Anything with no closing pair is left alone: an unclosed run while a reply
  /// is still streaming would otherwise restyle the rest of the paragraph on
  /// every token, which reads as the app breaking.
  static String _inline(String s) {
    // The two passes cannot nest: bold is consumed first, and the italic
    // pattern refuses to match anything still wrapped in asterisks.
    var out = s.replaceAllMapped(
      RegExp(r'\*\*([^*]{1,200}?)\*\*'),
      (m) => '<b>${m.group(1)}</b>',
    );
    out = out.replaceAllMapped(
      RegExp(r'(?<!\*)\*([^*]{1,200}?)\*(?!\*)'),
      (m) => '<i>${m.group(1)}</i>',
    );
    out = out.replaceAllMapped(
      RegExp(r'`([^`]{1,200}?)`'),
      (m) => '<c>${m.group(1)}</c>',
    );
    return out;
  }
}

/// Renders the tiny inline dialect produced by [RichReply._inline].
///
/// A bespoke parser rather than a general one, because the tags that can appear
/// here are exactly three and all of them nest. Accepting anything else would
/// mean accepting markup nobody asked to render.
class _InlineText extends StatelessWidget {
  const _InlineText(this.raw, {required this.style});

  final String raw;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final re = RegExp(r'<(b|i|c)>(.*?)</\1>');
    var at = 0;
    for (final m in re.allMatches(raw)) {
      if (m.start > at) {
        spans.add(TextSpan(text: raw.substring(at, m.start)));
      }
      final inner = m.group(2)!;
      spans.add(TextSpan(
        text: inner,
        style: switch (m.group(1)) {
          'b' => style.copyWith(fontWeight: FontWeight.w700),
          'i' => style.copyWith(fontStyle: FontStyle.italic),
          // A monospace run needs a fill behind it, or a rendered span and a
          // paragraph of the same colour look like the same thing.
          _ => KoruType.mono.copyWith(
              backgroundColor: KoruColors.surfaceAlt,
              color: style.color),
        },
      ));
      at = m.end;
    }
    if (at < raw.length) spans.add(TextSpan(text: raw.substring(at)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}