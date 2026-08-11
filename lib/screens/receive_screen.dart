import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../transfer/qr_decoder.dart';
import '../widgets/artifact_preview.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final decoder = QRFileDecoder();
  DecodedFile? decodedFile;
  String status = 'Point camera at sender QR screen';

  Future<void> onCode(String raw) async {
    final result = decoder.acceptFrame(raw);
    setState(() {
      status = decoder.statusText;
      decodedFile = result;
    });

    if (result != null && !kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/${result.fileName}');
      await out.writeAsBytes(result.bytes, flush: true);
      setState(() => status = 'Saved: ${out.path}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWindows = !kIsWeb && Platform.isWindows;
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
                        'Windows scanner bridge placeholder. Android camera scanning works now; Windows scanning needs OpenCV/ZBar native plugin in phase 2.',
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
                Text('${(decoder.progress * 100).toStringAsFixed(1)}% complete'),
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
