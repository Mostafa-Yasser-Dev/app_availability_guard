/// Numeric dotted versions; omitted trailing segments equal zero.
/// Prerelease/build suffixes are intentionally unsupported.
class AppVersionComparator {
  AppVersionComparator._();

  static List<BigInt> _parse(String version) {
    final value = version.trim();
    if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(value)) {
      throw FormatException('Invalid numeric version', version);
    }
    return value.split('.').map(BigInt.parse).toList();
  }

  static int compare(String a, String b) {
    final left = _parse(a);
    final right = _parse(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final result = (i < left.length ? left[i] : BigInt.zero).compareTo(
        i < right.length ? right[i] : BigInt.zero,
      );
      if (result != 0) return result;
    }
    return 0;
  }

  static bool isOlderThan(String a, String b) => compare(a, b) < 0;
  static bool isEqualOrNewerThan(String a, String b) => compare(a, b) >= 0;
  static bool isValid(String version) {
    try {
      _parse(version);
      return true;
    } on FormatException {
      return false;
    }
  }
}
