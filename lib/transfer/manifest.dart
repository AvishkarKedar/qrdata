import 'dart:convert';

class TransferManifest {
  final String protocol;
  final String transferId;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final String sha256;
  final int totalChunks;
  final int chunkSize;
  final int fecChunks;
  final bool encrypted;
  final bool compressed;

  const TransferManifest({
    required this.protocol,
    required this.transferId,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.sha256,
    required this.totalChunks,
    required this.chunkSize,
    required this.fecChunks,
    required this.encrypted,
    required this.compressed,
  });

  String toFrame() {
    final payload = jsonEncode({
      'protocol': protocol,
      'transferId': transferId,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSize': fileSize,
      'sha256': sha256,
      'totalChunks': totalChunks,
      'chunkSize': chunkSize,
      'fecChunks': fecChunks,
      'encrypted': encrypted,
      'compressed': compressed,
    });
    return 'QRD1M|${base64Url.encode(utf8.encode(payload))}';
  }

  static TransferManifest? tryParse(String raw) {
    if (!raw.startsWith('QRD1M|')) return null;
    final encoded = raw.substring('QRD1M|'.length);
    final map = jsonDecode(utf8.decode(base64Url.decode(encoded))) as Map<String, dynamic>;
    return TransferManifest(
      protocol: map['protocol'] as String,
      transferId: map['transferId'] as String,
      fileName: map['fileName'] as String,
      mimeType: map['mimeType'] as String,
      fileSize: map['fileSize'] as int,
      sha256: map['sha256'] as String,
      totalChunks: map['totalChunks'] as int,
      chunkSize: map['chunkSize'] as int,
      fecChunks: map['fecChunks'] as int,
      encrypted: map['encrypted'] as bool,
      compressed: map['compressed'] as bool,
    );
  }
}
