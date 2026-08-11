import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../transfer/qr_decoder.dart';
import '../transfer/receive_session_store.dart';
import '../widgets/artifact_preview.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final decoder = QRFileDecoder();
  final store = ReceiveSessionStore();
  DecodedFile? decodedFile;
  String status = 'Point camera at sender QR screen';
  DateTime? startedAt;
  int decodedFrames = 0;

  Future<void> onCode(String raw) async {
    startedAt ??= DateTime.now();
    decodedFrames++;
    final beforeChunks = decoder.chunks.length;
    final result = decoder.acceptFrame(raw);

    final manifest = decoder.manifest;
    if (manifest != null) await store.saveManifest(manifest);
    if (decoder.transferId != null && decoder.chunks.length > beforeChunks) {
      final newestSeq = decoder.chunks.keys.reduce((a, b) => a > b ? a : b);
      await store.saveChunk(transferId: decoder.transferId!, seq: newestSeq, bytes: decoder.chunks[newestSeq]!);
    }

    setState(() {
      status = decoder.statusText;
      decodedFile = result;
    });

    if (result != null && !kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/${result.fileName}');
      await out.writeAsBytes(result.bytes, flush: true);
      await store.delete(decoder.transferId!);
      setState(() => status = 'Verified and saved: ${out.path}');
    }
  }

  double get actualFps {
    final start = startedAt;
    if (start == null) return 0;
    final elapsed = DateTime.now().difference(start).inMilliseconds / 1000;
    if (elapsed <= 0) return 0;
    return decodedFrames / elapsed;
  }

  @override
  Widget build(BuildContext context) {
    final isWindows = !kIsWeb && Platform.isWindows;
    final missingReport = decoder.missingChunkReport;
    return Scaffold(
      appBar: AppBar(title: const Text('Receive file')),
      body: Column(
        children: [
          Expanded(
            child: isWindows
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Windows camera scanner bridge placeholder. Next phase: OpenCV/ZBar native decoder with focus/exposure controls.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : MobileScanner(
                    onDetect: (capture) {
                      for (final barcode in capture.barcodes) {
                        final raw = barcode.rawValue;
                        if (raw != null) onCode(raw);
                      }
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(status),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: decoder.progress),
                const SizedBox(height: 8),
                Text('${(decoder.progress * 100).toStringAsFixed(1)}% complete • Actual decoded FPS: ${actualFps.toStringAsFixed(1)}'),
                if (missingReport != null && decoder.progress > 0 && decoder.progress < 1) ...[
                  const SizedBox(height: 12),
                  const Text('Missing-chunk retransmission QR'),
                  Center(child: QrImageView(data: missingReport.toFrame(), size: 160)),
                ],
                if (decodedFile != null) ...[
                  const SizedBox(height: 12),
                  ArtifactPreview(fileName: decodedFile!.fileName, bytes: decodedFile!.bytes),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
