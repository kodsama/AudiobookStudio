import 'package:audiobook_studio/util/filename.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safeFileStem', () {
    test('keeps accents and apostrophes (regression for "Llgance")', () {
      // The old [^\w\- ] form deleted é/è/à and apostrophes.
      expect(
        safeFileStem("L'élégance de la manipulation - Influencer et convaincre"),
        "L'élégance de la manipulation - Influencer et convaincre",
      );
    });

    test('strips filesystem-illegal characters', () {
      expect(safeFileStem('a/b\\c:d*e?f"g<h>i|j'), 'abcdefghij');
    });

    test('collapses whitespace and trims', () {
      expect(safeFileStem('  Title   with\tgaps  '), 'Title with gaps');
    });

    test('falls back to "audiobook" when nothing usable remains', () {
      expect(safeFileStem('   '), 'audiobook');
      expect(safeFileStem('/\\:*?'), 'audiobook');
    });
  });
}
