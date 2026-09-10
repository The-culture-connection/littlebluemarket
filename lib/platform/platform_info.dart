/// Which platform this build runs on, without `dart:io`.
///
/// `dart:io` does not exist in a web build, so anything that imported it kept
/// the app off the web entirely. The two implementations behind this file are
/// chosen at compile time: the io one on phones, the web one in a browser.
library;

export 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart';
