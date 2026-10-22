// Web builds: talk to the QA harness page that hosts the app in an iframe.
// Messages are JSON strings so neither side depends on JS object conversion.

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _fromApp = 'lbm-qa';
const _fromHost = 'lbm-qa-host';

void qaPost(Map<String, Object?> message) {
  final parent = web.window.parent;
  if (parent == null) return;
  try {
    parent.postMessage(
      jsonEncode({...message, 'source': _fromApp}).toJS,
      '*'.toJS,
    );
  } catch (_) {
    // Never let QA plumbing break the app.
  }
}

void qaListen(void Function(Map<String, dynamic> message) onMessage) {
  web.window.addEventListener(
    'message',
    ((web.MessageEvent event) {
      final data = event.data;
      if (data == null || !data.isA<JSString>()) return;
      try {
        final decoded = jsonDecode((data as JSString).toDart);
        if (decoded is Map<String, dynamic> && decoded['source'] == _fromHost) {
          onMessage(decoded);
        }
      } catch (_) {}
    }).toJS,
  );
}
