/// Web addresses without the `#`.
///
/// Flutter's default on the web puts the route after a hash, so
/// `/delete-account` is not a route at all: the app boots at `/`, the router
/// sends a known visitor to the market, and the address becomes
/// `/delete-account#/market`. The app stores need a plain link that lands on
/// the page it names, so the web build reads the path instead. The server
/// already answers every path with the same page, which is what makes a
/// reload of a deep link work.
///
/// Does nothing on a phone, where there are no addresses to strategise.
library;

export 'url_strategy_io.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart';
