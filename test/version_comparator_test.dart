import 'package:app_availability_guard/app_availability_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersionComparator', () {
    // ── compare() ──────────────────────────────────────────────────────────
    group('compare()', () {
      test('equal versions return 0', () {
        expect(AppVersionComparator.compare('1.0.0', '1.0.0'), 0);
        expect(AppVersionComparator.compare('2.3.1', '2.3.1'), 0);
      });

      test('older version returns negative', () {
        expect(AppVersionComparator.compare('1.0.0', '1.0.1'), isNegative);
        expect(AppVersionComparator.compare('1.9.0', '1.10.0'), isNegative);
        expect(AppVersionComparator.compare('0.9.9', '1.0.0'), isNegative);
      });

      test('newer version returns positive', () {
        expect(AppVersionComparator.compare('1.0.1', '1.0.0'), isPositive);
        expect(AppVersionComparator.compare('1.10.0', '1.9.0'), isPositive);
        expect(AppVersionComparator.compare('2.0.0', '1.9.9'), isPositive);
      });

      test('missing patch segment treated as 0', () {
        expect(AppVersionComparator.compare('1.0', '1.0.0'), 0);
        expect(AppVersionComparator.compare('1.2', '1.2.0'), 0);
        expect(AppVersionComparator.compare('1.0', '1.0.1'), isNegative);
      });

      test('1.10.0 is newer than 1.9.0 (numeric not lexicographic)', () {
        expect(AppVersionComparator.compare('1.10.0', '1.9.0'), isPositive);
      });

      test('major version wins', () {
        expect(AppVersionComparator.compare('2.0.0', '1.99.99'), isPositive);
      });
    });

    // ── isOlderThan / isEqualOrNewerThan ───────────────────────────────────
    group('isOlderThan()', () {
      test('returns true when a < b', () {
        expect(AppVersionComparator.isOlderThan('1.0.0', '1.0.1'), isTrue);
      });
      test('returns false when a == b', () {
        expect(AppVersionComparator.isOlderThan('1.0.0', '1.0.0'), isFalse);
      });
      test('returns false when a > b', () {
        expect(AppVersionComparator.isOlderThan('1.1.0', '1.0.0'), isFalse);
      });
    });

    group('isEqualOrNewerThan()', () {
      test('returns true when a == b', () {
        expect(
          AppVersionComparator.isEqualOrNewerThan('1.2.0', '1.2.0'),
          isTrue,
        );
      });
      test('returns true when a > b', () {
        expect(
          AppVersionComparator.isEqualOrNewerThan('1.2.1', '1.2.0'),
          isTrue,
        );
      });
      test('returns false when a < b', () {
        expect(
          AppVersionComparator.isEqualOrNewerThan('1.1.0', '1.2.0'),
          isFalse,
        );
      });
    });

    // ── isValid() ──────────────────────────────────────────────────────────
    group('isValid()', () {
      test('valid version strings', () {
        expect(AppVersionComparator.isValid('1.0.0'), isTrue);
        expect(AppVersionComparator.isValid('10.20.30'), isTrue);
        expect(AppVersionComparator.isValid('1.0'), isTrue);
        expect(AppVersionComparator.isValid('1'), isTrue);
      });

      test('empty string is invalid', () {
        expect(AppVersionComparator.isValid(''), isFalse);
      });

      test('non-numeric segment is invalid', () {
        expect(AppVersionComparator.isValid('1.a.0'), isFalse);
        expect(AppVersionComparator.isValid('latest'), isFalse);
        expect(AppVersionComparator.isValid('1.0.x'), isFalse);
      });

      test('negative segment is invalid', () {
        expect(AppVersionComparator.isValid('1.-1.0'), isFalse);
      });
    });

    // ── FormatException for invalid input ──────────────────────────────────
    group('compare() throws on invalid input', () {
      test('throws FormatException for empty string', () {
        expect(
          () => AppVersionComparator.compare('', '1.0.0'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException for non-numeric segment', () {
        expect(
          () => AppVersionComparator.compare('1.a.0', '1.0.0'),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
