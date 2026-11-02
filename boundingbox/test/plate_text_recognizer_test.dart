import 'package:boundingbox/features/plate_ocr/services/plate_text_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('combineSegments joins region and serial', () {
    test('two spatial segments WAW + 12345 combine to WAW12345', () {
      final segments = const [
        PlateSegment(text: 'WAW', cx: 10),
        PlateSegment(text: '12345', cx: 60),
      ];
      final combined = PlateTextRecognizer.combineSegments(segments);
      expect(combined.text, 'WAW12345');
      expect(combined.region, 'WAW');
      expect(combined.serial, '12345');
    });

    test('single token KR 123AB keeps full text', () {
      final segments = const [
        PlateSegment(text: 'KR123AB', cx: 40),
      ];
      final combined = PlateTextRecognizer.combineSegments(segments);
      expect(combined.text, 'KR123AB');
      expect(combined.region, 'KR');
      expect(combined.serial, '123AB');
    });

    test('reversed spatial order still sorts left to right', () {
      final segments = const [
        PlateSegment(text: '4567', cx: 80),
        PlateSegment(text: 'PO', cx: 20),
      ];
      final combined = PlateTextRecognizer.combineSegments(segments);
      expect(combined.text, 'PO4567');
      expect(combined.region, 'PO');
    });

    test('normalizePlateText legacy entry point keeps region', () {
      expect(PlateTextRecognizer.normalizePlateText('WAW 12345'), 'WAW12345');
      expect(PlateTextRecognizer.normalizePlateText('kr 123ab'), 'KR123AB');
    });

    test('too short input returns empty', () {
      expect(PlateTextRecognizer.normalizePlateText('AB'), '');
      expect(PlateTextRecognizer.normalizePlateText(''), '');
    });
  });
}
