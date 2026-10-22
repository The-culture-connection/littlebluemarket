// Non-web builds: the QA harness bridge is a no-op.

void qaPost(Map<String, Object?> message) {}

void qaListen(void Function(Map<String, dynamic> message) onMessage) {}
