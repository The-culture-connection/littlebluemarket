import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Text whose web addresses are tappable.
///
/// A bio that says "shop at www.foundhouse.com" should open the shop. The
/// address is recognised as typed (with or without https://), trailing
/// punctuation is left out of the link, and everything else is plain text.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text, {super.key, this.style, this.linkColor});

  final String text;
  final TextStyle? style;
  final Color? linkColor;

  /// The addresses in [text], in order, as they would be opened.
  static List<String> linksIn(String text) => [
    for (final match in _pattern.allMatches(text)) _clean(match.group(0)!).$1,
  ];

  /// Opens an address as typed. `www.…` gets `https://` in front.
  static Future<bool> open(String link) {
    final uri = Uri.tryParse(
      link.startsWith(RegExp(r'https?://', caseSensitive: false))
          ? link
          : 'https://$link',
    );
    if (uri == null) return Future.value(false);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static final _pattern = RegExp(
    r'(https?://[^\s<>"]+|www\.[^\s<>"]+)',
    caseSensitive: false,
  );

  /// The link without trailing punctuation, and how many characters were
  /// left off so the text keeps them.
  static (String, int) _clean(String raw) {
    var link = raw;
    var trimmed = 0;
    while (link.isNotEmpty && '.,;:!?)\'"]'.contains(link[link.length - 1])) {
      link = link.substring(0, link.length - 1);
      trimmed++;
    }
    return (link, trimmed);
  }

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final linkStyle = base.copyWith(
      color: widget.linkColor ?? Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor ?? Theme.of(context).colorScheme.primary,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in LinkedText._pattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      final (link, trimmed) = LinkedText._clean(match.group(0)!);
      final recognizer = TapGestureRecognizer()
        ..onTap = () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          final ok = await LinkedText.open(link);
          if (!ok) {
            messenger?.showSnackBar(
              SnackBar(content: Text('Could not open $link')),
            );
          }
        };
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: link, style: linkStyle, recognizer: recognizer));
      cursor = match.end - trimmed;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    if (spans.isEmpty) return Text(widget.text, style: base);
    return Text.rich(TextSpan(style: base, children: spans));
  }
}
