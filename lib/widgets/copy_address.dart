import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Puts a business's address on the clipboard and says so.
///
/// This replaced a Directions button that handed the phone a `geo:` link.
/// Not every phone has an app that takes one, and where none does the
/// person got "Could not open geo:0,0?q=…" and no address (Grace,
/// 2026-09-30). A copied address pastes into whatever maps app they use.
Future<void> copyAddress(BuildContext context, String address) async {
  final text = address.trim();
  if (text.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Address copied. Paste it into your maps app.'),
      ),
    );
}
