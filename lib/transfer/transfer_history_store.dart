import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ReceivedFileRecord {
  final String sha256;
  final String fileName;
  final DateTime receivedAt;

  const ReceivedFileRecord({required this.sha256, required this.fileName, required this.receivedAt});

  Map<String, dynamic> toJson() => {
        'sha256': sha256,
        'fileName': fileName,
        'receivedAt': receivedAt.toIso8601String(),
      };

  factory ReceivedFileRecord.fromJson(Map<String, dynamic> map) => ReceivedFileRecord(
        sha256: map['sha256'] as String,
        fileName: map['fileName'] as String,
        receivedAt: DateTime.tryParse(map['receivedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Tracks completed transfers by file hash so the receiver can warn about
/// re-receiving a file it already has, instead of silently duplicating work.
class TransferHistoryStore {
  static const _fileName = 'received_history.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<ReceivedFileRecord>> _readAll() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return raw.map((e) => ReceivedFileRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<ReceivedFileRecord?> findBySha256(String sha256) async {
    final all = await _readAll();
    for (final record in all) {
      if (record.sha256 == sha256) return record;
    }
    return null;
  }

  Future<void> record({required String sha256, required String fileName}) async {
    final all = await _readAll();
    all.removeWhere((r) => r.sha256 == sha256);
    all.add(ReceivedFileRecord(sha256: sha256, fileName: fileName, receivedAt: DateTime.now()));
    final file = await _file();
    await file.writeAsString(jsonEncode(all.map((r) => r.toJson()).toList()), flush: true);
  }

  Future<List<ReceivedFileRecord>> history() => _readAll();
}
