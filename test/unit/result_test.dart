import 'package:flutter_test/flutter_test.dart';
import 'package:docerena/core/errors/result.dart';

void main() {
  group('Result<T, E> Tests', () {
    test('Success returns data and handles map/fold/getOrElse', () {
      const Result<int, StorageError> res = Success(42);

      expect(res.isSuccess, isTrue);
      expect(res.isFailure, isFalse);
      expect(res.dataOrNull, equals(42));
      expect(res.errorOrNull, isNull);
      expect(res.getOrElse((e) => 0), equals(42));
      expect(res.getOrThrow(), equals(42));

      final mapped = res.map((val) => val * 2);
      expect(mapped.dataOrNull, equals(84));

      final folded = res.fold(
        (val) => 'Value: $val',
        (err) => 'Error: $err',
      );
      expect(folded, equals('Value: 42'));
    });

    test('Failure returns error and handles mapError/fold/getOrElse', () {
      const error = StorageError(
        message: 'Disk full',
        code: StorageErrorCode.diskFull,
      );
      const Result<int, StorageError> res = Failure(error);

      expect(res.isSuccess, isFalse);
      expect(res.isFailure, isTrue);
      expect(res.dataOrNull, isNull);
      expect(res.errorOrNull, equals(error));
      expect(res.getOrElse((e) => -1), equals(-1));
      expect(() => res.getOrThrow(), throwsStateError);

      final folded = res.fold(
        (val) => 'Value: $val',
        (err) => 'Handled error: ${err.message}',
      );
      expect(folded, equals('Handled error: Disk full'));
    });
  });
}
