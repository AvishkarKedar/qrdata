import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'crc32.dart';

class DecodedFile {
  final String fileName;
  final String mimeType;
  final List<int> bytes;

  DecodedFile({required this.fileName, required this.mimeType, required this.bytes});
}

class QRFileDecoder {
  String? transferId;
  String? fileName;
  String? mimeType;
  String? fileSha256;
  int? total;
  int? fileSize;
  final Map<int, List<int>> chunks = {};

  double get progress => total == null || total == 0 ? 0 : chunks.length / total!;
  String get statusText => total == null
      ? 'Waiting for first frame'
      : 'Received ${chunks.length}/$total chunks';

  DecodedFile? acceptFrame(String raw) {
    if (!raw.startsWith('QRD1|')) return null;
    final parts = raw.split('|');
    if (parts.length != 11) return null;

    final incomingTransferId = parts[1];
    final seq = int.tryParse(parts[2]);
    final incomingTotal = int.tryParse(parts[3]);
    final incomingFileSize = int.tryParse(parts[7]);
    final incomingSha = parts[8];
    final chunkCrc = parts[9];
    final chunk = base64Url.decode(parts[10]);

    if (seq == null || incomingTotal == null || incomingFileSize == null) return null;
    if (crc32Hex(chunk) != chunkCrc) return null;

    if (transferId == null || transferId != incomingTransferId) {
      transferId = incomingTransferId;
      total = incomingTotal;
      fileName = utf8.decode(base64Url.decode(parts[5]));
      mimeType = utf8.decode(base64Url.decode(parts[6]));
      fileSize = incomingFileSize;
      fileSha256 = incomingSha;
      chunks.clear();
    }

    if (seq < 0 || seq >= total!) return null;
    chunks.putIfAbsent(seq, () => chunk);

    if (chunks.length == total) {
      final output = <int>[];
      for (var i = 0; i < total!; i++) {
        output.addAll(chunks[i]!);
      }
      if (output.length != fileSize) return null;
      if (sha256.convert(output).toString() != fileSha256) return null;
      return DecodedFile(fileName: fileName!, mimeType: mimeType!, bytes: output);
    }
    return null;
  }
}
