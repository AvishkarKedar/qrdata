import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../transfer/qr_encoder.dart';
import '../transfer/transfer_estimator.dart';
import '../transfer/transfer_profile.dart';
import '../widgets/artifact_preview.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final fpsOptions = const [10, 15, 30, 60, 90, 120];
  int fps = 15;
  TransferProfile profile = TransferProfile.balanced;
  List<String> frames = [];
  PlatformFile? selectedFile;
  List<int>? selectedBytes;
  int frameIndex = 0;
  Timer? timer;
  TransferEstimate? estimate;
  bool isDragging = false;
  bool compress = true;
  bool encrypt = false;
  double brightness = 1.0;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    await loadPlatformFile(result.files.single);
  }

  Future<void> loadDroppedFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    await loadPlatformFile(PlatformFile(name: path.split(Platform.pathSeparator).last, size: bytes.length, path: path, bytes: bytes));
  }

  Future<void> loadPlatformFile(PlatformFile file) async {
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    final mimeType = lookupMimeType(file.name, headerBytes: bytes) ?? 'application/octet-stream';
    final encoder = QRFileEncoder(
      chunkSize: profile.chunkSize,
      profile: profile,
      encrypted: encrypt,
      compressed: compress && _shouldCompress(mimeType),
    );
    final transfer = encoder.encodeFile(fileName: file.name, mimeType: mimeType, bytes: bytes);

    setState(() {
      selectedFile = file;
      selectedBytes = bytes;
      frames = transfer.frames;
      frameIndex = 0;
      estimate = TransferEstimator.estimate(
        fileSizeBytes: bytes.length,
        frameCount: transfer.frames.length,
        fps: fps,
        loopRedundancy: profile.loopRedundancy,
      );
    });
  }

  bool _shouldCompress(String mimeType) {
    final alreadyCompressed = ['image/jpeg', 'image/png', 'video/', 'audio/', 'zip', 'pdf', 'officedocument'];
    return !alreadyCompressed.any(mimeType.contains);
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
    final isWindows = !kIsWeb && Platform.isWindows;
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isWindows)
          Card(
            color: isDragging ? Colors.indigo.shade50 : null,
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Drag and drop a file here, or use Choose file')),
            ),
          ),
        FilledButton.icon(onPressed: pickFile, icon: const Icon(Icons.attach_file), label: const Text('Choose file')),
        const SizedBox(height: 16),
        DropdownButtonFormField<TransferProfile>(
          value: profile,
          decoration: const InputDecoration(labelText: 'Transfer profile'),
          items: TransferProfile.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              profile = value;
              fps = value.recommendedFps;
            });
            if (selectedFile != null) loadPlatformFile(selectedFile!);
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(title: const Text('Compress when useful'), value: compress, onChanged: (v) => setState(() => compress = v)),
        SwitchListTile(title: const Text('Encrypt transfer - planned'), subtitle: const Text('UI toggle added; crypto implementation comes next'), value: encrypt, onChanged: (v) => setState(() => encrypt = v)),
        ListTile(title: const Text('Sender brightness'), subtitle: Slider(value: brightness, min: 0.4, max: 1.0, onChanged: (v) => setState(() => brightness = v))),
        if (selectedFile != null) ...[
          Text('File: ${selectedFile!.name}'),
          Text('Size: ${selectedFile!.size} bytes'),
          const SizedBox(height: 8),
          ArtifactPreview(fileName: selectedFile!.name, bytes: selectedBytes),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: fps,
            decoration: const InputDecoration(labelText: 'Playback FPS'),
            items: fpsOptions.map((value) => DropdownMenuItem(value: value, child: Text('$value FPS'))).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                fps = value;
                estimate = TransferEstimator.estimate(fileSizeBytes: selectedFile!.size, frameCount: frames.length, fps: fps, loopRedundancy: profile.loopRedundancy);
              });
            },
          ),
          const SizedBox(height: 8),
          if (estimate != null) Text('Estimated transfer: ${estimate!.humanTime} (${frames.length} frames x ${profile.loopRedundancy} loops)'),
          const SizedBox(height: 16),
          Center(
            child: currentFrame == null
                ? const SizedBox.shrink()
                : Container(
                    color: Colors.white.withOpacity(brightness),
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(data: currentFrame, version: QrVersions.auto, size: 340, backgroundColor: Colors.white),
                  ),
          ),
          const SizedBox(height: 8),
          Text('Frame ${frames.isEmpty ? 0 : frameIndex + 1}/${frames.length}', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: FilledButton(onPressed: start, child: const Text('Play loop'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton(onPressed: stop, child: const Text('Stop'))),
          ]),
          const SizedBox(height: 12),
          const Text('Privacy warning: QR frames are visible. Anyone with a camera can capture them. Use encryption before sensitive transfers.'),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Send file')),
      body: isWindows
          ? DropTarget(
              onDragEntered: (_) => setState(() => isDragging = true),
              onDragExited: (_) => setState(() => isDragging = false),
              onDragDone: (details) async {
                setState(() => isDragging = false);
                if (details.files.isNotEmpty) await loadDroppedFile(details.files.first.path);
              },
              child: content,
            )
          : content,
    );
  }
}
