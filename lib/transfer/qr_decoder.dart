import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'crc32.dart';
import 'encryption.dart';
import 'fec.dart';
import 'manifest.dart';
import 'retransmission.dart';

class DecodedFile {
  final String fileName;
  final String mimeType;
  final List<int> bytes;

  DecodedFile({required this.fileName, required this.mimeType, required this.bytes});
}

class QRFileDecoder {
  TransferManifest? manifest;
  String? transferId;
  String? fileName;
  String? mimeType;
  String? fileSha256;
  int? total;
  int? chunkSize;
  int? payloadSize;
  int? fileSize;
  final Map<int, List<int>> chunks = {};
  final Map<int, List<int>> parityChunks = {};
  final Set<String> seenFrameHashes = {};

  double get progress => total == null || total == 0 ? 0 : chunks.length / total!;
  String get statusText => total == null ? 'Waiting for first frame' : 'Received ${chunks.length}/$total chunks';
  bool get isComplete => total != null && chunks.length == total;

  List<int> get missingChunks {
    final t = total;
    if (t == null) return const [];
    return [for (var i = 0; i < t; i++) if (!chunks.containsKey(i)) i];
  }

  RetransmissionRequest? get missingChunkReport {
    final id = transferId;
    if (id == null) return null;
    return RetransmissionRequest(transferId: id, missing: missingChunks.toSet());
  }

  void restore({required TransferManifest savedManifest, required Map<int, List<int>> savedChunks}) {
    manifest = savedManifest;
    transferId = savedManifest.transferId;
    total = savedManifest.totalChunks;
    chunkSize = savedManifest.chunkSize;
    payloadSize = savedManifest.payloadSize;
    fileName = savedManifest.fileName;
    mimeType = savedManifest.mimeType;
    fileSize = savedManifest.fileSize;
    fileSha256 = savedManifest.sha256;
    chunks
      ..clear()
      ..addAll(savedChunks);
  }

  void acceptFrame(String raw) {
    final frameHash = sha256.convert(utf8.encode(raw)).toString();
    if (seenFrameHashes.contains(frameHash)) return;
    seenFrameHashes.add(frameHash);

    final incomingManifest = TransferManifest.tryParse(raw);
    if (incomingManifest != null) {
      _adoptManifest(incomingManifest);
      attemptFecRecovery();
      return;
    }

    if (raw.startsWith('QRD1F|')) {
      _acceptParityFrame(raw);
      return;
    }

    if (!raw.startsWith('QRD1|')) return;
    _acceptDataFrame(raw);
    attemptFecRecovery();
  }

  void _adoptManifest(TransferManifest incoming) {
    if (transferId != null && transferId != incoming.transferId) {
      chunks.clear();
      parityChunks.clear();
    }
    manifest = incoming;
    transferId = incoming.transferId;
    total = incoming.totalChunks;
    chunkSize = incoming.chunkSize;
    payloadSize = incoming.payloadSize;
    fileName = incoming.fileName;
    mimeType = incoming.mimeType;
    fileSize = incoming.fileSize;
    fileSha256 = incoming.sha256;
  }

  void _acceptParityFrame(String raw) {
    final parts = raw.split('|');
    if (parts.length != 5) return;
    final incomingTransferId = parts[1];
    if (transferId != null && transferId != incomingTransferId) return;
    final idx = int.tryParse(parts[2]);
    if (idx == null) return;
    transferId ??= incomingTransferId;
    parityChunks.putIfAbsent(idx, () => base64Url.decode(parts[4]));
  }

  void _acceptDataFrame(String raw) {
    final parts = raw.split('|');
    if (parts.length != 11) return;

    final incomingTransferId = parts[1];
    final seq = int.tryParse(parts[2]);
    final incomingTotal = int.tryParse(parts[3]);
    final incomingChunkSize = int.tryParse(parts[4]);
    final incomingPayloadSize = int.tryParse(parts[7]);
    final incomingSha = parts[8];
    final chunkCrc = parts[9];

    if (seq == null || incomingTotal == null || incomingChunkSize == null || incomingPayloadSize == null) return;

    final chunk = base64Url.decode(parts[10]);
    if (crc32Hex(chunk) != chunkCrc) return;

    if (transferId == null || transferId != incomingTransferId) {
      transferId = incomingTransferId;
      total = incomingTotal;
      chunkSize = incomingChunkSize;
      payloadSize = incomingPayloadSize;
      fileName = utf8.decode(base64Url.decode(parts[5]));
      mimeType = utf8.decode(base64Url.decode(parts[6]));
      fileSize ??= incomingPayloadSize;
      fileSha256 = incomingSha;
      chunks.clear();
      parityChunks.clear();
    }

    if (seq < 0 || seq >= total!) return;
    chunks.putIfAbsent(seq, () => chunk);
  }

  void attemptFecRecovery() {
    final t = total;
    final m = manifest;
    if (t == null || m == null || m.fecChunks <= 0) return;
    for (final idx in missingChunks) {
      final group = idx % m.fecChunks;
      final parity = parityChunks[group];
      if (parity == null) continue;
      final recovered = FecCodec.recoverChunk(
        missingIndex: idx,
        totalChunks: t,
        parityCount: m.fecChunks,
        knownChunks: chunks,
        parityChunk: parity,
        originalChunkLength: _chunkLength(idx, m),
      );
      if (recovered != null) chunks[idx] = recovered;
    }
  }

  int _chunkLength(int index, TransferManifest m) {
    if (index != m.totalChunks - 1) return m.chunkSize;
    final remainder = m.payloadSize % m.chunkSize;
    return remainder == 0 ? m.chunkSize : remainder;
  }

  Future<DecodedFile?> buildFile({String? passphrase}) async {
    if (!isComplete) return null;
    final expectedPayloadSize = payloadSize;
    final output = <int>[];
    for (var i = 0; i < total!; i++) {
      output.addAll(chunks[i]!);
    }
    if (expectedPayloadSize != null && output.length != expectedPayloadSize) return null;

    var plainBytes = output;
    final m = manifest;
    if (m != null && m.encrypted) {
      if (passphrase == null || passphrase.isEmpty) {
        throw const QrEncryptionRequiredException('A passphrase is required to decrypt this file.');
      }
      if (m.saltB64 == null || m.nonceB64 == null || m.macB64 == null) {
        throw const QrEncryptionRequiredException('Encryption metadata is missing; rescan the manifest QR frame.');
      }
      plainBytes = await QrEncryption.decrypt(
        cipherText: output,
        nonce: base64Url.decode(m.nonceB64!),
        mac: base64Url.decode(m.macB64!),
        passphrase: passphrase,
        salt: base64Url.decode(m.saltB64!),
      );
    }

    if (fileSize != null && plainBytes.length != fileSize) return null;
    if (fileSha256 != null && sha256.convert(plainBytes).toString() != fileSha256) return null;
    return DecodedFile(fileName: fileName!, mimeType: mimeType!, bytes: plainBytes);
  }
}
