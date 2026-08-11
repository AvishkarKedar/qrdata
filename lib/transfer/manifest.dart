import 'dart:convert';

class TransferManifest {
  final String protocol;
  final String transferId;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final int payloadSize;
  final String sha256;
  final int totalChunks;
  final int chunkSize;
  final int fecChunks;
  final bool encrypted;
  final bool compressed;
  final String? saltB64;
  final String? nonceB64;
  final String? macB64;

  const TransferManifest({
    required this.protocol,
    required this.transferId,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.payloadSize,
    required this.sha256,
    required this.totalChunks,
    required this.chunkSize,
    required this.fecChunks,
    required this.encrypted,
    required this.compressed,
    this.saltB64,
    this.nonceB64,
    this.macB64,
  });

  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'transferId': transferId,
        'fileName': fileName,
        'mimeType': mimeType,
        'fileSize': fileSize,
        'payloadSize': payloadSize,
        'sha256': sha256,
        'totalChunks': totalChunks,
        'chunkSize': chunkSize,
        'fecChunks': fecChunks,
        'encrypted': encrypted,
        'compressed': compressed,
        'saltB64': saltB64,
        'nonceB64': nonceB64,
        'macB64': macB64,
      };

  factory TransferManifest.fromJson(Map<String, dynamic> map) => TransferManifest(
        protocol: map['protocol'] as String,
        transferId: map['transferId'] as String,
        fileName: map['fileName'] as String,
        mimeType: map['mimeType'] as String,
        fileSize: map['fileSize'] as int,
        payloadSize: (map['payloadSize'] as int?) ?? map['fileSize'] as int,
        sha256: map['sha256'] as String,
        totalChunks: map['totalChunks'] as int,
        chunkSize: map['chunkSize'] as int,
        fecChunks: map['fecChunks'] as int,
        encrypted: map['encrypted'] as bool,
        compressed: map['compressed'] as bool,
        saltB64: map['saltB64'] as String?,
        nonceB64: map['nonceB64'] as String?,
        macB64: map['macB64'] as String?,
      );

  String toFrame() => 'QRD1M|${base64Url.encode(utf8.encode(jsonEncode(toJson())))}';

  static TransferManifest? tryParse(String raw) {
    if (!raw.startsWith('QRD1M|')) return null;
    final encoded = raw.substring('QRD1M|'.length);
    return TransferManifest.fromJson(jsonDecode(utf8.decode(base64Url.decode(encoded))) as Map<String, dynamic>);
  }
}
