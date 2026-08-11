import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../transfer/qr_encoder.dart';
import '../transfer/transfer_estimator.dart';
import '../widgets/artifact_preview.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final fpsOptions = const [30, 60, 90, 120];
  int fps = 30;
  List<String> frames = [];
  PlatformFile? selectedFile;
  int frameIndex = 0;
  Timer? timer;
  TransferEstimate? estimate;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    final mimeType = lookupMimeType(file.name, headerBytes: bytes) ?? 'application/octet-stream';
    final encoder = QRFileEncoder(chunkSize: QRFileEncoder.defaultChunkSize);
    final encodedFrames = encoder.encodeFile(
      fileName: file.name,
      mimeType: mimeType,
      bytes: bytes,
    );

    setState(() {
      selectedFile = file;
      frames = encodedFrames;
      frameIndex = 0;
      estimate = TransferEstimator.estimate(
        fileSizeBytes: bytes.length,
        frameCount: encodedFrames.length,
        fps: fps,
        loopRedundancy: 2,
      );
    });
  }

  void start() {
    if (frames.isEmpty) return;
    timer?.cancel();
    final intervalMs = (1000 / fps).round().clamp(8, 1000);
    timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      setState(() => frameIndex = (frameIndex + 1) % frames.length);
    });
  }

  void stop() {
    timer?.cancel();
    timer = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentFrame = frames.isEmpty ? null : frames[frameIndex];
    return Scaffold(
      appBar: AppBar(title: const Text('Send file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: pickFile,
            icon: const Icon(Icons.attach_file),
            label: const Text('Choose file'),
          ),
          const SizedBox(height: 16),
          if (selectedFile != null) ...[
            Text('File: ${selectedFile!.name}'),
            Text('Size: ${selectedFile!.size} bytes'),
            const SizedBox(height: 8),
            ArtifactPreview(fileName: selectedFile!.name, bytes: selectedFile!.bytes),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: fps,
              decoration: const InputDecoration(labelText: 'Playback FPS'),
              items: fpsOptions
                  .map((value) => DropdownMenuItem(value: value, child: Text('$value FPS')))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  fps = value;
                  if (selectedFile != null && estimate != null) {
                    estimate = TransferEstimator.estimate(
                      fileSizeBytes: selectedFile!.size,
                      frameCount: frames.length,
                      fps: fps,
                      loopRedundancy: 2,
                    );
                  }
                });
              },
            ),
            const SizedBox(height: 8),
            if (estimate != null)
              Text('Estimated transfer: ${estimate!.humanTime} for ${frames.length} frames x 2 loops'),
            const SizedBox(height: 16),
            Center(
              child: currentFrame == null
                  ? const SizedBox.shrink()
                  : QrImageView(
                      data: currentFrame,
                      version: QrVersions.auto,
                      size: 320,
                      backgroundColor: Colors.white,
                    ),
            ),
            const SizedBox(height: 8),
            Text('Frame ${frames.isEmpty ? 0 : frameIndex + 1}/${frames.length}', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: FilledButton(onPressed: start, child: const Text('Play loop'))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton(onPressed: stop, child: const Text('Stop'))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
