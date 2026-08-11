import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'crc32.dart';
import 'encryption.dart';
import 'fec.dart';
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

  Future<EncodedTransfer> encodeFile({
    required String fileName,
    required String mimeType,
    required List<int> bytes,
    String? passphrase,
  }) async {
    final transferId = _randomId();
    final fileSha = sha256.convert(bytes).toString();

    List<int> payloadBytes = bytes;
    String? saltB64;
    String? nonceB64;
    String? macB64;

    if (encrypted) {
      if (passphrase == null || passphrase.isEmpty) {
        throw ArgumentError('A passphrase is required when encryption is enabled.');
      }
      final salt = _randomBytes(16);
      final encryptedPayload = await QrEncryption.encrypt(plainBytes: bytes, passphrase: passphrase, salt: salt);
      payloadBytes = encryptedPayload.cipherText;
      saltB64 = base64Url.encode(salt);
      nonceB64 = base64Url.encode(encryptedPayload.nonce);
      macB64 = base64Url.encode(encryptedPayload.mac);
    }

    final total = (payloadBytes.length / chunkSize).ceil().clamp(1, 1 << 31);
    final fecChunks = (total * profile.fecOverhead).ceil();
    final nameB64 = base64Url.encode(utf8.encode(fileName));
    final mimeB64 = base64Url.encode(utf8.encode(mimeType));

    final rawChunks = <List<int>>[];
    final frames = <String>[];
    for (var seq = 0; seq < total; seq++) {
      final start = seq * chunkSize;
      final end = min(start + chunkSize, payloadBytes.length);
      final chunk = payloadBytes.sublist(start, end);
      rawChunks.add(chunk);
      final chunkCrc = crc32Hex(chunk);
      final chunkB64 = base64Url.encode(chunk);
      frames.add(
        'QRD1|$transferId|$seq|$total|$chunkSize|$nameB64|$mimeB64|${payloadBytes.length}|$fileSha|$chunkCrc|$chunkB64',
      );
    }

    if (fecChunks > 0) {
      final padded = rawChunks
          .map((chunk) => chunk.length == chunkSize
              ? chunk
              : (List<int>.from(chunk)..addAll(List<int>.filled(chunkSize - chunk.length, 0))))
          .toList();
      final parity = FecCodec.buildParity(chunks: padded, parityCount: fecChunks, chunkSize: chunkSize);
      for (var i = 0; i < parity.length; i++) {
        frames.add('QRD1F|$transferId|$i|$fecChunks|${base64Url.encode(parity[i])}');
      }
    }

    final manifest = TransferManifest(
      protocol: 'QRD1',
      transferId: transferId,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: bytes.length,
      payloadSize: payloadBytes.length,
      sha256: fileSha,
      totalChunks: total,
      chunkSize: chunkSize,
      fecChunks: fecChunks,
      encrypted: encrypted,
      compressed: compressed,
      saltB64: saltB64,
      nonceB64: nonceB64,
      macB64: macB64,
    );

    frames.insert(0, manifest.toFrame());
    return EncodedTransfer(manifest: manifest, frames: frames, bytesToSend: bytes);
  }

  String _randomId() => base64Url.encode(_randomBytes(12));

  List<int> _randomBytes(int length) {
    final r = Random.secure();
    return List<int>.generate(length, (_) => r.nextInt(256));
  }
}
