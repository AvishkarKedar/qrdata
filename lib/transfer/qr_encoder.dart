import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'crc32.dart';
import 'manifest.dart';
import 'transfer_profile.dart';

class EncodedTransfer {
  final TransferManifest manifest;
  final List<String> frames;
  final List<int> bytesToSend;

  const EncodedTransfer({required this.manifest, required this.frames, required this.bytesToSend});
}

class QRFileEncoder {
  static const defaultChunkSize = 700;
  final int chunkSize;
  final TransferProfile profile;
  final bool encrypted;
  final bool compressed;

  QRFileEncoder({
    this.chunkSize = defaultChunkSize,
    this.profile = TransferProfile.balanced,
    this.encrypted = false,
    this.compressed = false,
  });

  EncodedTransfer encodeFile({
    required String fileName,
    required String mimeType,
    required List<int> bytes,
  }) {
    final transferId = _randomId();
    final fileSha = sha256.convert(bytes).toString();
    final total = (bytes.length / chunkSize).ceil().clamp(1, 1 << 31);
    final fecChunks = (total * profile.fecOverhead).ceil();
    final nameB64 = base64Url.encode(utf8.encode(fileName));
    final mimeB64 = base64Url.encode(utf8.encode(mimeType));

    final manifest = TransferManifest(
      protocol: 'QRD1',
      transferId: transferId,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: bytes.length,
      sha256: fileSha,
      totalChunks: total,
      chunkSize: chunkSize,
      fecChunks: fecChunks,
      encrypted: encrypted,
      compressed: compressed,
    );

    final frames = <String>[manifest.toFrame()];
    for (var seq = 0; seq < total; seq++) {
      final start = seq * chunkSize;
      final end = min(start + chunkSize, bytes.length);
      final chunk = bytes.sublist(start, end);
      final chunkCrc = crc32Hex(chunk);
      final chunkB64 = base64Url.encode(chunk);
      frames.add('QRD1|$transferId|$seq|$total|$chunkSize|$nameB64|$mimeB64|${bytes.length}|$fileSha|$chunkCrc|$chunkB64');
    }

    // MVP placeholder FEC frames. Phase 2 will replace this with real fountain/Reed-Solomon parity.
    for (var i = 0; i < fecChunks; i++) {
      frames.add('QRD1F|$transferId|$i|$fecChunks|placeholder');
    }

    return EncodedTransfer(manifest: manifest, frames: frames, bytesToSend: bytes);
  }

  String _randomId() {
    final r = Random.secure();
    final bytes = List<int>.generate(12, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }
}
