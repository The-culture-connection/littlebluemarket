import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The seam, enforced.
///
/// Screens and widgets must reach data through a repository provider, never by
/// importing the fixtures directly. Nothing else stops that from creeping back
/// in one convenient import at a time, and the day it does the live build
/// starts rendering demo content.
void main() {
  test('no screen or widget imports the fixtures', () {
    final offenders = <String>[];

    for (final dir in ['lib/screens', 'lib/widgets']) {
      final directory = Directory(dir);
      if (!directory.existsSync()) continue;

      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('data/fixtures')) {
          offenders.add(entity.path.replaceAll(r'\', '/'));
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These files import the fixtures directly. Read through a repository '
          'provider instead:\n  ${offenders.join('\n  ')}',
    );
  });
}
