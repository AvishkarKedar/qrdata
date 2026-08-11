import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mime/mime.dart';

class ArtifactPreview extends StatelessWidget {
  final String fileName;
  final List<int>? bytes;

  const ArtifactPreview({super.key, required this.fileName, required this.bytes});

  @override
  Widget build(BuildContext context) {
    final mime = lookupMimeType(fileName, headerBytes: bytes) ?? 'application/octet-stream';
    final data = bytes == null ? null : Uint8List.fromList(bytes!);

    Widget child;
    if (data != null && mime.startsWith('image/')) {
      child = Image.memory(data, height: 180, fit: BoxFit.contain);
    } else if (data != null && mime.startsWith('text/')) {
      child = Text(utf8.decode(data, allowMalformed: true), maxLines: 8, overflow: TextOverflow.ellipsis);
    } else {
      child = ListTile(
        leading: Icon(_iconForMime(mime)),
        title: Text(fileName),
        subtitle: Text(mime),
      );
    }

    return Card(
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }

  IconData _iconForMime(String mime) {
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('spreadsheet') || mime.contains('excel')) return Icons.table_chart;
    if (mime.contains('word') || mime.contains('document')) return Icons.description;
    if (mime.startsWith('video/')) return Icons.movie;
    if (mime.startsWith('audio/')) return Icons.audiotrack;
    if (mime.startsWith('image/')) return Icons.image;
    return Icons.insert_drive_file;
  }
}
