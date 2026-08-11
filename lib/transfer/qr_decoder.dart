import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'crc32.dart';
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
  int? fileSize;
  final Map<int, List<int>> chunks = {};
  final Set<String> seenFrameHashes = {};

  double get progress => total == null || total == 0 ? 0 : chunks.length / total!;
  String get statusText => total == null ? 'Waiting for first frame' : 'Received ${chunks.length}/$total chunks';

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
    fileName = savedManifest.fileName;
    mimeType = savedManifest.mimeType;
    fileSize = savedManifest.fileSize;
    fileSha256 = savedManifest.sha256;
    chunks
      ..clear()
      ..addAll(savedChunks);
  }

  DecodedFile? acceptFrame(String raw) {
    final frameHash = sha256.convert(utf8.encode(raw)).toString();
    if (seenFrameHashes.contains(frameHash)) return null;
    seenFrameHashes.add(frameHash);

    final incomingManifest = TransferManifest.tryParse(raw);
    if (incomingManifest != null) {
      manifest = incomingManifest;
      transferId ??= incomingManifest.transferId;
      total ??= incomingManifest.totalChunks;
      fileName ??= incomingManifest.fileName;
      mimeType ??= incomingManifest.mimeType;
      fileSize ??= incomingManifest.fileSize;
      fileSha256 ??= incomingManifest.sha256;
      return null;
    }

    if (raw.startsWith('QRD1F|')) return null;
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
    return tryBuildFile();
  }

  DecodedFile? tryBuildFile() {
    if (total == null || chunks.length != total) return null;
    final output = <int>[];
    for (var i = 0; i < total!; i++) {
      output.addAll(chunks[i]!);
    }
    if (output.length != fileSize) return null;
    if (sha256.convert(output).toString() != fileSha256) return null;
    return DecodedFile(fileName: fileName!, mimeType: mimeType!, bytes: output);
  }
}
