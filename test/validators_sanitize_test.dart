import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/core/utils/validators.dart';

/// AppValidators.sanitize shipped for months with a character class that could
/// not compile: written as `RegExp(r'[<>"\'']')`, which Dart parsed as the raw
/// string `[<>"\` concatenated with `]`, producing the unterminated class
/// `[<>"\]`. Every call would have thrown a FormatException — but it had zero
/// callers, so nothing ever executed it and only `flutter analyze`'s
/// valid_regexps lint ever noticed.
///
/// These tests exist so the function is actually executed by the suite. If the
/// pattern regresses, the first case throws instead of returning.
void main() {
  group('AppValidators.sanitize', () {
    test('compiles and runs at all (the original bug threw here)', () {
      expect(AppValidators.sanitize('hello'), 'hello');
    });

    test('strips angle-bracketed tags', () {
      expect(AppValidators.sanitize('<script>alert(1)</script>drop'), 'alert(1)drop');
    });

    test('strips stray quote and bracket characters', () {
      expect(AppValidators.sanitize('a<b>c"d\'e'), 'acde');
    });

    test('trims surrounding whitespace', () {
      expect(AppValidators.sanitize('   padded   '), 'padded');
    });

    test('leaves ordinary text untouched', () {
      expect(AppValidators.sanitize('CSE 412 - Section A'), 'CSE 412 - Section A');
    });
  });
}
