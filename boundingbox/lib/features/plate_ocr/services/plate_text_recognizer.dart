import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/plate_reading.dart';

class PlateSegment {
  const PlateSegment({required this.text, required this.cx});

  final String text;
  final double cx;
}

class PlateTextRecognizer {
  PlateTextRecognizer() : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;
  bool _closed = false;

  Future<PlateReading> readPlateFile(String path, double detectionConfidence) async {
    if (_closed) return const PlateReading.empty();
    final input = InputImage.fromFilePath(path);
    final result = await _recognizer.processImage(input);
    final segments = collectSegments(result);
    final combined = combineSegments(segments);
    if (combined.isEmpty) return const PlateReading.empty();
    return PlateReading(
      text: combined.text,
      region: combined.region,
      serial: combined.serial,
      rawText: result.text.trim(),
      confidence: detectionConfidence,
      capturedAt: DateTime.now(),
    );
  }

  Future<void> dispose() async {
    _closed = true;
    await _recognizer.close();
  }

  static List<PlateSegment> collectSegments(RecognizedText result) {
    final out = <PlateSegment>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final cleaned = cleanToken(element.text);
          if (cleaned.isEmpty) continue;
          final box = element.boundingBox;
          final double cx = (box.left + box.right) / 2.0;
          out.add(PlateSegment(text: cleaned, cx: cx));
        }
        final lineCleaned = cleanToken(line.text);
        if (lineCleaned.length >= 4 && !out.any((s) => s.text == lineCleaned)) {
          out.add(PlateSegment(text: lineCleaned, cx: -1));
        }
      }
    }
    if (out.isEmpty) {
      final fallback = cleanToken(result.text);
      if (fallback.isNotEmpty) out.add(PlateSegment(text: fallback, cx: 0));
    }
    return out;
  }

  /// Czyści token – tylko wielkie litery i cyfry.
  /// USUNIĘTO wszystkie hardcoded zamiany (I→1, L→1, O→0, Q→0).
  /// Model ML Kit sam rozpoznaje litery; żadne sztuczne podmienianie znaków.
  static String cleanToken(String raw) {
    final upper = raw.toUpperCase();
    final fixed = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (fixed.length < 2 || fixed.length > 9) return '';
    return fixed;
  }

  static Combined combineSegments(List<PlateSegment> segments) {
    if (segments.isEmpty) return const Combined(text: '', region: '', serial: '');
    final spatial = segments.where((s) => s.cx >= 0).toList()
      ..sort((a, b) => a.cx.compareTo(b.cx));
    final pool = spatial.isNotEmpty ? spatial : segments;

    final texts = pool.map((s) => s.text).toList();
    final joined = texts.join();
    if (joined.length >= 4 && joined.length <= 9) {
      final parts = splitRegionSerial(joinIfSplit(joined, texts));
      return parts;
    }

    final flat = texts.join(' ');
    final parts = splitRegionSerial(cleanToken(flat.replaceAll(' ', '')));
    if (parts.text.isNotEmpty) return parts;

    final longest = texts.fold<String>('', (a, b) => b.length > a.length ? b : a);
    if (longest.length >= 3) {
      return splitRegionSerial(longest);
    }
    return const Combined(text: '', region: '', serial: '');
  }

  static String joinIfSplit(String joined, List<String> texts) {
    if (texts.length == 2 &&
        texts[0].length <= 3 &&
        RegExp(r'^[A-Z]+$').hasMatch(texts[0]) &&
        texts[1].length >= 3) {
      return texts[0] + texts[1];
    }
    return joined;
  }

  static Combined splitRegionSerial(String plate) {
    if (plate.length < 4 || plate.length > 9) {
      return const Combined(text: '', region: '', serial: '');
    }
    final regionMatch = RegExp(r'^[A-Z]{1,3}').firstMatch(plate);
    if (regionMatch == null) return const Combined(text: '', region: '', serial: '');
    final region = regionMatch.group(0)!;
    final serial = plate.substring(region.length);
    if (serial.length < 3 || serial.length > 6) {
      return Combined(text: plate, region: region, serial: serial);
    }
    if (!RegExp(r'^[A-Z0-9]{3,6}$').hasMatch(serial)) {
      return const Combined(text: '', region: '', serial: '');
    }
    return Combined(text: region + serial, region: region, serial: serial);
  }

  static String normalizePlateText(String raw) {
    final parts = splitRegionSerial(cleanToken(raw));
    return parts.text;
  }
}

class Combined {
  const Combined({required this.text, required this.region, required this.serial});

  final String text;
  final String region;
  final String serial;

  bool get isEmpty => text.isEmpty;
}
