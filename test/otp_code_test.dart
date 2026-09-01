import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/core/utils/otp_code.dart';

/// The paste has to survive how people actually copy.
///
/// This exists because of a design argument worth recording. The confirmation
/// email wanted to show the code as six separate chips — it reads better and
/// it is far easier to transcribe by eye. The objection was that chips live in
/// six table cells, so a long-press selection returns `1 2 3 4 5 6`, and a
/// matcher looking for six ADJACENT digits would silently fail on it.
///
/// The wrong conclusion was to make the email plainer. The right one is that
/// the parser should tolerate what a mail client actually puts on the
/// clipboard, because the parser is one testable function and the email is
/// seen by everyone. These cases are that tolerance, pinned down.
void main() {
  group('finds the code', () {
    test('plain', () => expect(extractOtpCode('482913'), '482913'));

    test('per-digit chip selection — the case that unblocked the design',
        () => expect(extractOtpCode('4 8 2 9 1 3'), '482913'));

    test('non-breaking spaces, which is what HTML cells actually yield',
        () => expect(extractOtpCode('4 8 2 9 1 3'), '482913'));

    test('newlines, from a vertical or wrapped layout',
        () => expect(extractOtpCode('4\n8\n2\n9\n1\n3'), '482913'));

    test('hyphenated', () => expect(extractOtpCode('482-913'), '482913'));

    test('the whole subject line',
        () => expect(extractOtpCode('482913 is your AFOS confirmation code'), '482913'));

    test('a sentence with the code mid-way',
        () => expect(extractOtpCode('Your confirmation code is 482913 — enter it in the app.'),
            '482913'));

    test('surrounding whitespace', () => expect(extractOtpCode('  482913\n'), '482913'));
  });

  group('refuses what is not a code', () {
    test('null', () => expect(extractOtpCode(null), isNull));
    test('empty', () => expect(extractOtpCode(''), isNull));
    test('no digits', () => expect(extractOtpCode('no code here'), isNull));
    test('too short', () => expect(extractOtpCode('4829'), isNull));

    // The important refusals. Slicing six digits out of a longer number gives
    // the user a rejection they cannot explain, because the field would look
    // correct to them.
    test('a longer number is not a code',
        () => expect(extractOtpCode('4829131'), isNull));
    test('a student id is not a code',
        () => expect(extractOtpCode('id 012345792'), isNull));
  });

  test('takes the FIRST code when a mail repeats it in the preheader', () {
    expect(extractOtpCode('482913 is your code. Code: 482913'), '482913');
  });
}
