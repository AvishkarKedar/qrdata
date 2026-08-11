import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'crc32.dart';

class QRFileEncoder {
  static const defaultChunkSize = 700;
  final int chunkSize;

  QRFileEncoder({required this.chunkSize});

  List<String> encodeFile({
    required String fileName,
    required String mimeType,
    required List<int> bytes,
  }) {
    final transferId = _randomId();
    final fileSha = sha256.convert(bytes).toString();
    final total = (bytes.length / chunkSize).ceil().clamp(1, 1 << 31);
    final nameB64 = base64Url.encode(utf8.encode(fileName));
    final mimeB64 = base64Url.encode(utf8.encode(mimeType));

    final frames = <String>[];
    for (var seq = 0; seq < total; seq++) {
      final start = seq * chunkSize;
      final end = min(start + chunkSize, bytes.length);
      final chunk = bytes.sublist(start, end);
      final chunkCrc = crc32Hex(chunk);
      final chunkB64 = base64Url.encode(chunk);
      frames.add('QRD1|$transferId|$seq|$total|$chunkSize|$nameB64|$mimeB64|${bytes.length}|$fileSha|$chunkCrc|$chunkB64');
    }
    return frames;
  }

  String _randomId() {
    final r = Random.secure();
    final bytes = List<int>.generate(12, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }
}
