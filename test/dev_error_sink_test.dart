import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/data/repositories/dev_error_sink.dart';
import 'package:little_blue_market/data/repositories/repositories.dart';

void main() {
  setUp(() {
    DevErrorSink.enabled = true;
    DevErrorSink.clear();
  });

  tearDown(() {
    DevErrorSink.enabled = false;
    DevErrorSink.clear();
  });

  test('a disabled sink drops reports', () {
    DevErrorSink.enabled = false;
    DevErrorSink.report(const OfflineException());
    expect(DevErrorSink.recent, isEmpty);
  });

  test('an enabled sink keeps the raw error, its code and the operation', () {
    const error = BackendException('boom', code: 'not-wired');
    DevErrorSink.report(error, StackTrace.current, 'callable commerceAddLine');

    final report = DevErrorSink.recent.single;
    expect(report.error, same(error));
    expect(report.typeName, 'BackendException');
    expect(report.code, 'not-wired');
    expect(report.message, 'boom');
    expect(report.operation, 'callable commerceAddLine');
    expect(report.stack, isNotNull);
  });

  test('the same exception passing through two guards is reported once', () {
    const error = PermissionException('nope');
    DevErrorSink.report(error, null, 'inner');
    DevErrorSink.report(error, null, 'outer');
    expect(DevErrorSink.recent, hasLength(1));
    expect(DevErrorSink.recent.single.operation, 'inner');
  });

  test('errors without a code or message still describe themselves', () {
    DevErrorSink.report(StateError('raw'));
    final report = DevErrorSink.recent.single;
    expect(report.code, isNull);
    expect(report.message, contains('raw'));
    expect(report.details, isNull);
  });

  test('the buffer is bounded', () {
    for (var i = 0; i < DevErrorSink.capacity + 10; i++) {
      DevErrorSink.report(BackendException('e$i'));
    }
    expect(DevErrorSink.recent, hasLength(DevErrorSink.capacity));
    expect(
      (DevErrorSink.recent.last.error as BackendException).message,
      'e${DevErrorSink.capacity + 9}',
    );
  });

  test('the stream delivers each report to a listener', () async {
    final seen = <String?>[];
    final subscription = DevErrorSink.stream.listen(
      (r) => seen.add(r.operation),
    );
    DevErrorSink.report(const OfflineException(), null, 'a');
    DevErrorSink.report(const RateLimitException(), null, 'b');
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    expect(seen, ['a', 'b']);
  });
}
