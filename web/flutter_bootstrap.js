// How the web app starts. Replaces the one Flutter generates, for one reason:
// no service worker.
//
// Flutter's default registers a worker that caches the whole app and serves it
// from the cache on the next visit. That is useful for an offline app and a
// liability for this one: a freshly deployed page kept showing the previous
// build, and the address the app stores are given has to resolve the moment
// someone opens it. This is an online marketplace; there is nothing to do
// offline anyway.
//
// A worker installed by an earlier version is unregistered here, and its
// caches dropped, so someone who visited before recovers by themselves.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker
    .getRegistrations()
    .then((registrations) => {
      for (const registration of registrations) registration.unregister();
    })
    .catch(() => {});
}
if (window.caches) {
  caches
    .keys()
    .then((keys) => Promise.all(keys.map((key) => caches.delete(key))))
    .catch(() => {});
}

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();
