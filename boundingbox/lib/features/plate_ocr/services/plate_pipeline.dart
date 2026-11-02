import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/tracked_plate.dart';
import 'plate_cropper.dart';
import 'plate_text_recognizer.dart';

enum PlatePipelineState { idle, reading }

class PlatePipeline {
  PlatePipeline({
    required this.onTracks,
    required this.onState,
    this.minConfidence = 0.40,
    this.minRelativeArea = 0.002,
    this.maxTracks = 8,
    this.matchIou = 0.30,
    this.trackTtl = const Duration(milliseconds: 1500),
    this.ocrCooldown = const Duration(milliseconds: 1500),
    this.ocrVotesRequired = 2,
    this.ocrMaxAttempts = 4,
    required Future<Uint8List?> Function() captureFrame,
  }) : _recognizer = PlateTextRecognizer(),
       _captureFrame = captureFrame;

  final void Function(List<TrackedPlate> tracks) onTracks;
  final void Function(PlatePipelineState state) onState;

  final double minConfidence;
  final double minRelativeArea;
  final int maxTracks;
  final double matchIou;
  final Duration trackTtl;
  final Duration ocrCooldown;
  final int ocrVotesRequired;
  final int ocrMaxAttempts;
  final Future<Uint8List?> Function() _captureFrame;

  final PlateTextRecognizer _recognizer;

  final Map<int, TrackedPlate> _tracks = {};
  int _nextId = 1;
  bool _disposed = false;
  String? _tempDir;
  final Map<int, DateTime> _lastOcrAt = {};

  /// Bufor wyników OCR per track – temporal smoothing.
  final Map<int, List<String>> _ocrVotes = {};

  void handleDetections(List<YOLOResult> results) {
    if (_disposed) return;
    final now = DateTime.now();

    _tracks.removeWhere((id, t) => now.difference(t.lastSeen) > trackTtl);
    _lastOcrAt.removeWhere((id, _) => !_tracks.containsKey(id));

    final candidates = results
        .where((r) =>
            r.confidence >= minConfidence &&
            r.normalizedBox.width * r.normalizedBox.height >= minRelativeArea)
        .toList()
      ..sort((a, b) {
        final aa = a.normalizedBox.width * a.normalizedBox.height;
        final bb = b.normalizedBox.width * b.normalizedBox.height;
        return bb.compareTo(aa);
      });

    final limited = candidates.take(maxTracks).toList();
    final matchedIds = <int>{};

    for (final det in limited) {
      final box = _clampBox(det.normalizedBox);
      int? bestId;
      double bestIou = 0;
      for (final entry in _tracks.entries) {
        if (matchedIds.contains(entry.key)) continue;
        final iou = _iou(entry.value.box, box);
        if (iou > bestIou) {
          bestIou = iou;
          bestId = entry.key;
        }
      }
      if (bestId != null && bestIou >= matchIou) {
        final prev = _tracks[bestId]!;
        _tracks[bestId] = prev.copyWith(
          box: box,
          confidence: det.confidence,
          lastSeen: now,
        );
        matchedIds.add(bestId);
      } else {
        final id = _nextId++;
        _tracks[id] = TrackedPlate(
          id: id,
          box: box,
          confidence: det.confidence,
          text: '',
          region: '',
          serial: '',
          reading: false,
          lastSeen: now,
          ocrInFlight: false,
          selected: false,
        );
        matchedIds.add(id);
      }
    }

    // Uruchom OCR automatycznie dla nowych śladów bez tekstu (nie wymaga kliknięcia)
    for (final entry in _tracks.entries) {
      final id = entry.key;
      final t = entry.value;
      if (t.hasText || t.ocrInFlight) continue;

      final attempts = _ocrVotes[id]?.length ?? 0;
      if (attempts >= ocrMaxAttempts) continue; // nie spamuj OCR w nieskończoność

      final last = _lastOcrAt[id];
      if (last != null && now.difference(last) < ocrCooldown) continue;
      _lastOcrAt[id] = now;
      _startOcr(id);
      _startOcr(id);
    }

    onTracks(_tracks.values.toList());
    final anyReading = _tracks.values.any((t) => t.ocrInFlight);
    onState(anyReading ? PlatePipelineState.reading : PlatePipelineState.idle);
  }

  void _startOcr(int id) {
    if (_disposed || _tracks[id] == null || _tracks[id]!.ocrInFlight) return;
    final cur = _tracks[id]!;
    _tracks[id] = cur.copyWith(ocrInFlight: true, reading: true);
    if (!_disposed) onTracks(_tracks.values.toList());
    if (!_disposed) onState(PlatePipelineState.reading);

    _doOcr(id);
  }

  Future<void> _doOcr(int id) async {
    try {
      final frame = await _captureFrame();
      if (frame == null || _disposed) {
        _finishFlight(id);
        return;
      }

      _tempDir ??= (await getTemporaryDirectory()).path;
      final cur = _tracks[id];
      if (cur == null) {
        _finishFlight(id);
        return;
      }
      final out = await cropPlateCrop(CropRequest(
        jpeg: frame,
        left: cur.box.left,
        top: cur.box.top,
        right: cur.box.right,
        bottom: cur.box.bottom,
      ));
      if (out == null || _disposed) {
        _finishFlight(id);
        return;
      }
      final path =
          '$_tempDir/plate_$id-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(out.jpeg, flush: false);
      final reading = await _recognizer.readPlateFile(path, cur.confidence);
      if (_disposed) return;
      final cur2 = _tracks[id];
      if (cur2 == null) return;

      // Dodaj wynik do bufora głosów (temporal smoothing)
      _ocrVotes.putIfAbsent(id, () => []);
      if (reading.hasText) {
        _ocrVotes[id]!.add(reading.text);
      } else {
        _ocrVotes[id]!.add('');
      }

      // Sprawdź czy jakiś tekst został potwierdzony (wystarczająca liczba głosów)
      final confirmed = _getConfirmedText(id);
      final votes = _ocrVotes[id]!;

      if (confirmed != null) {
        // Tekst potwierdzony – zapisz i zakończ OCR dla tego tracka
        _tracks[id] = cur2.copyWith(
          text: confirmed.text,
          region: confirmed.region,
          serial: confirmed.serial,
          ocrInFlight: false,
          reading: false,
          lastSeen: DateTime.now(),
        );
        _ocrVotes.remove(id);
      } else if (votes.length >= ocrMaxAttempts) {
        // Wyczerpano próby i nie ma potwierdzenia – zostaw bez tekstu
        _tracks[id] = cur2.copyWith(ocrInFlight: false, reading: false);
        _ocrVotes.remove(id);
      } else {
        // Jeszcze nie ma potwierdzenia, ale są jeszcze próby – kontynuuj OCR
        _tracks[id] = cur2.copyWith(ocrInFlight: false, reading: false);
      }

      onTracks(_tracks.values.toList());
      onState(PlatePipelineState.idle);
    } catch (e) {
      debugPrint('PlatePipeline track $id error: $e');
      _finishFlight(id);
    }
  }

  /// Zwraca potwierdzony tekst jeśli jakiś napis pojawił się >= ocrVotesRequired razy.
  /// Wykorzystuje najczęstszy wynik (mode) z bufora głosów i waliduje format tablicy.
  Combined? _getConfirmedText(int id) {
    final votes = _ocrVotes[id];
    if (votes == null || votes.isEmpty) return null;

    // Zlicz wystąpienia każdego niepustego tekstu
    final counts = <String, int>{};
    for (final v in votes) {
      if (v.isNotEmpty) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) return null;

    // Znajdź tekst z największą liczbą głosów
    String bestText = '';
    int bestCount = 0;
    counts.forEach((text, count) {
      if (count > bestCount) {
        bestCount = count;
        bestText = text;
      }
    });

    if (bestCount < ocrVotesRequired) return null;

    // Walidacja i rozbicie na region + serial przez PlateTextRecognizer
    final cleaned = PlateTextRecognizer.normalizePlateText(bestText);
    if (cleaned.isEmpty) return null;

    return PlateTextRecognizer.combineSegments(
      [PlateSegment(text: cleaned, cx: 0.0)],
    );
  }

  void _finishFlight(int id) {
    final cur = _tracks[id];
    if (cur != null && cur.ocrInFlight) {
      _tracks[id] = cur.copyWith(ocrInFlight: false, reading: false);
      if (!_disposed) onTracks(_tracks.values.toList());
    }
    if (!_disposed) onState(PlatePipelineState.idle);
  }

  void clearTexts() {
    for (final entry in _tracks.entries) {
      _tracks[entry.key] = entry.value.copyWith(
        text: '',
        region: '',
        serial: '',
        reading: false,
        ocrInFlight: false,
        selected: false,
      );
    }
    _lastOcrAt.clear();
    _ocrVotes.clear();
    if (!_disposed) onTracks(_tracks.values.toList());
  }

  Rect _clampBox(Rect b) {
    double l = b.left.clamp(0.0, 1.0);
    double t = b.top.clamp(0.0, 1.0);
    double r = b.right.clamp(0.0, 1.0);
    double bb = b.bottom.clamp(0.0, 1.0);
    if (r <= l) r = (l + 0.01).clamp(0.0, 1.0);
    if (bb <= t) bb = (t + 0.01).clamp(0.0, 1.0);
    return Rect.fromLTRB(l, t, r, bb);
  }

  double _iou(Rect a, Rect b) {
    final x0 = a.left > b.left ? a.left : b.left;
    final y0 = a.top > b.top ? a.top : b.top;
    final x1 = a.right < b.right ? a.right : b.right;
    final y1 = a.bottom < b.bottom ? a.bottom : b.bottom;
    final iw = x1 - x0;
    final ih = y1 - y0;
    if (iw <= 0 || ih <= 0) return 0;
    final inter = iw * ih;
    final union = a.width * a.height + b.width * b.height - inter;
    if (union <= 0) return 0;
    return inter / union;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _recognizer.dispose();
  }
}
