import 'package:resqlite/src/tracelite_profile.dart';
import 'package:test/test.dart';

void main() {
  test('tracelite bridge is inert unless profile flags are enabled', () {
    expect(TraceliteProfile.isEnabled, isFalse);

    expect(() {
      final correlationId = TraceliteProfile.nextCorrelationId();
      final sqlId = TraceliteProfile.internString('SELECT 1');

      TraceliteProfile.begin(
        TraceliteResqliteSpans.databaseSelect,
        args: [sqlId],
        correlationId: correlationId,
      );
      TraceliteProfile.counter(
        TraceliteResqliteCounters.rowsDecoded,
        1,
        correlationId: correlationId,
      );
      TraceliteProfile.end(
        TraceliteResqliteSpans.databaseSelect,
        args: [1],
        correlationId: correlationId,
      );
      TraceliteProfile.detach();
    }, returnsNormally);
  });
}
