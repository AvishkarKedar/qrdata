import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'manifest.dart';

class ReceiveSessionSnapshot {
  final TransferManifest manifest;
  final Map<int, List<int>> chunks;

  const ReceiveSessionSnapshot({required this.manifest, required this.chunks});
}

class ReceiveSessionStore {
  static const _folderName = 'receive_sessions';

  Future<Directory> _sessionDir(String transferId) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/$_folderName/$transferId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> saveManifest(TransferManifest manifest) async {
    final dir = await _sessionDir(manifest.transferId);
    final file = File('${dir.path}/manifest.json');
    await file.writeAsString(jsonEncode(manifest.toJson()), flush: true);
  }

  Future<void> saveChunk({required String transferId, required int seq, required List<int> bytes}) async {
    final dir = await _sessionDir(transferId);
    final file = File('${dir.path}/chunk_$seq.bin');
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
  }

  Future<ReceiveSessionSnapshot?> load(String transferId) async {
    final dir = await _sessionDir(transferId);
    final manifestFile = File('${dir.path}/manifest.json');
    if (!await manifestFile.exists()) return null;
    final manifest = TransferManifest.fromJson(jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>);
    final chunks = <int, List<int>>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('chunk_') || !name.endsWith('.bin')) continue;
      final seq = int.tryParse(name.substring(6, name.length - 4));
      if (seq != null) chunks[seq] = await entity.readAsBytes();
    }
    return ReceiveSessionSnapshot(manifest: manifest, chunks: chunks);
  }

  Future<void> delete(String transferId) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/$_folderName/$transferId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
