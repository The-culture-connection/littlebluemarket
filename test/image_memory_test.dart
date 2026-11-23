import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Photos are decoded at a width, never at the file's own size.
///
/// On 2026-11-23 iOS killed the app on Grace's iPhone 14 ("Terminated due to
/// memory issue"). Every feed pin measured its photo's shape by resolving a
/// bare `NetworkImage`, a second decode at full size (30 to 60 MB for a
/// 3000px shop photo) held while the pin was on screen. A bare provider, or
/// an `Image.memory` of a camera photo without `cacheWidth`, is the same
/// mistake again, so this reads the source and refuses both.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('every NetworkImage is wrapped in a ResizeImage', () {
    final bare = <String>[];
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (!line.contains('NetworkImage(')) continue;
        final before = [if (i > 0) lines[i - 1], line].join(' ');
        if (!before.contains('ResizeImage(')) bare.add('${file.path}:${i + 1}');
      }
    }
    expect(
      bare,
      isEmpty,
      reason: 'Decode at a width: ResizeImage(..., width: N)',
    );
  });

  test('every Image.memory and Image.network names a cacheWidth', () {
    final unsized = <String>[];
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (!RegExp(r'Image\.(memory|network)\(').hasMatch(line)) continue;
        final call = lines.skip(i).take(9).join(' ');
        if (!call.contains('cacheWidth')) unsized.add('${file.path}:${i + 1}');
      }
    }
    expect(unsized, isEmpty, reason: 'Give it cacheWidth: the drawn size');
  });
}
