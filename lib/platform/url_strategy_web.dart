import 'package:flutter_web_plugins/url_strategy.dart';

/// The browser: read the route from the path, not from after a `#`.
void useAppUrlStrategy() => usePathUrlStrategy();
