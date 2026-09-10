/// The browser: no `dart:io`, no process environment, and neither phone OS.
bool get platformIsIOS => false;
bool get platformIsAndroid => false;
String get platformName => 'web';
bool environmentHas(String key) => false;
