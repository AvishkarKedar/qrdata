import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../transfer/qr_encoder.dart';
import '../transfer/retransmission.dart';
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
  final passphraseController = TextEditingController();
  final retransmissionController = TextEditingController();
  int fps = 15;
  TransferProfile profile = TransferProfile.balanced;

  /// The complete frame set for the current transfer (manifest + all data +
  /// FEC frames). `frames` below is what is actually looping on screen, and
  /// may be a filtered subset while resending only missing chunks.
  List<String> allFrames = [];
  List<String> frames = [];
  String? resendNoticeText;

  String? fileName;
  int? fileSizeBytes;
  List<int>? selectedBytes;
  int frameIndex = 0;
  Timer? timer;
  TransferEstimate? estimate;
  bool isDragging = false;
  bool compress = true;
  bool encrypt = false;
  bool encoding = false;
  double brightness = 1.0;
  bool roomIsDark = true;

  @override
  void dispose() {
    timer?.cancel();
    passphraseController.dispose();
    retransmissionController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    await _stageSelection(name: file.name, bytes: bytes);
  }

  Future<void> pickMultipleFilesAsZip() async {
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final archive = Archive();
    for (final file in result.files) {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
    }
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) return;

    final stamp = DateTime.now().millisecondsSinceEpoch;
    await _stageSelection(name: 'bundle_$stamp.zip', bytes: zipBytes, forceMimeType: 'application/zip');
  }

  Future<void> loadDroppedFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    await _stageSelection(name: path.split(Platform.pathSeparator).last, bytes: bytes);
  }

  Future<void> _stageSelection({required String name, required List<int> bytes, String? forceMimeType}) async {
    if (encrypt && passphraseController.text.isEmpty) {
      setState(() {
        fileName = name;
        fileSizeBytes = bytes.length;
        selectedBytes = bytes;
        allFrames = [];
        frames = [];
        estimate = null;
      });
      return;
    }
    await _encodeAndShow(name: name, bytes: bytes, forceMimeType: forceMimeType);
  }

  Future<void> _encodeAndShow({required String name, required List<int> bytes, String? forceMimeType}) async {
    setState(() => encoding = true);
    final mimeType = forceMimeType ?? lookupMimeType(name, headerBytes: bytes) ?? 'application/octet-stream';
    final encoder = QRFileEncoder(
      chunkSize: profile.chunkSize,
      profile: profile,
      encrypted: encrypt,
      compressed: compress && _shouldCompress(mimeType),
    );
    final transfer = await encoder.encodeFile(
      fileName: name,
      mimeType: mimeType,
      bytes: bytes,
      passphrase: encrypt ? passphraseController.text : null,
    );

    if (!mounted) return;
    setState(() {
      fileName = name;
      fileSizeBytes = bytes.length;
      selectedBytes = bytes;
      allFrames = transfer.frames;
      frames = transfer.frames;
      resendNoticeText = null;
      frameIndex = 0;
      encoding = false;
      estimate = TransferEstimator.estimate(
        fileSizeBytes: bytes.length,
        frameCount: transfer.frames.length,
        fps: fps,
        loopRedundancy: profile.loopRedundancy,
      );
    });
  }

  void applyRetransmissionCode() {
    final request = RetransmissionRequest.tryParse(retransmissionController.text.trim());
    if (request == null || allFrames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that retransmission code.')),
      );
      return;
    }
    final missingOnly = RetransmissionFilter.onlyMissingFrames(frames: allFrames, request: request);
    if (missingOnly.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching chunks found for that transfer ID.')),
      );
      return;
    }
    final manifestFrame = allFrames.firstWhere((f) => f.startsWith('QRD1M|'), orElse: () => '');
    setState(() {
      frames = manifestFrame.isEmpty ? missingOnly : [manifestFrame, ...missingOnly];
      frameIndex = 0;
      resendNoticeText = 'Resending ${missingOnly.length} missing chunk(s) for transfer ${request.transferId}';
    });
  }

  void resumeFullLoop() {
    setState(() {
      frames = allFrames;
      frameIndex = 0;
      resendNoticeText = null;
    });
  }

  bool _shouldCompress(String mimeType) {
    final alreadyCompressed = ['image/jpeg', 'image/png', 'video/', 'audio/', 'zip', 'pdf', 'officedocument'];
    return !alreadyCompressed.any(mimeType.contains);
  }

  void start() {
    if (frames.isEmpty) return;
    WakelockPlus.enable();
    timer?.cancel();
    final intervalMs = (1000 / fps).round().clamp(8, 1000);
    timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      setState(() => frameIndex = (frameIndex + 1) % frames.length);
    });
  }

  void stop() {
    timer?.cancel();
    timer = null;
    WakelockPlus.disable();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentFrame = frames.isEmpty ? null : frames[frameIndex];
    final isWindows = !kIsWeb && Platform.isWindows;
    final needsPassphrase = encrypt && passphraseController.text.isEmpty && fileName != null && allFrames.isEmpty;

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isWindows)
          Card(
            color: isDragging ? Colors.indigo.shade50 : null,
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Drag and drop a file here, or use the buttons below')),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(onPressed: pickFile, icon: const Icon(Icons.attach_file), label: const Text('Choose file')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: pickMultipleFilesAsZip,
              icon: const Icon(Icons.folder_zip),
              label: const Text('Multiple files (ZIP)'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        DropdownButtonFormField<TransferProfile>(
          value: profile,
          decoration: const InputDecoration(labelText: 'Transfer profile'),
          items: TransferProfile.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(),
          onChanged: (value) async {
            if (value == null) return;
            setState(() {
              profile = value;
              fps = value.recommendedFps;
            });
            if (fileName != null && selectedBytes != null) await _encodeAndShow(name: fileName!, bytes: selectedBytes!);
          },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Compress when useful'),
          value: compress,
          onChanged: (v) async {
            setState(() => compress = v);
            if (fileName != null && selectedBytes != null) await _encodeAndShow(name: fileName!, bytes: selectedBytes!);
          },
        ),
        SwitchListTile(
          title: const Text('Encrypt this transfer'),
          subtitle: const Text('AES-256-GCM with a passphrase you share out-of-band'),
          value: encrypt,
          onChanged: (v) async {
            setState(() => encrypt = v);
            if (fileName != null && selectedBytes != null && !encrypt) await _encodeAndShow(name: fileName!, bytes: selectedBytes!);
          },
        ),
        if (encrypt)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: passphraseController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Passphrase'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (fileName == null || selectedBytes == null)
                      ? null
                      : () => _encodeAndShow(name: fileName!, bytes: selectedBytes!),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        SwitchListTile(
          title: const Text('Dark room mode'),
          subtitle: const Text('High-brightness white QR background for dark rooms; turn off for a high-contrast bordered look in bright rooms'),
          value: roomIsDark,
          onChanged: (v) => setState(() {
            roomIsDark = v;
            brightness = v ? 1.0 : 0.85;
          }),
        ),
        ListTile(
          title: const Text('Sender brightness'),
          subtitle: Slider(value: brightness, min: 0.4, max: 1.0, onChanged: (v) => setState(() => brightness = v)),
        ),
        ExpansionTile(
          title: const Text('Resend missing chunks'),
          subtitle: const Text('Paste the retransmission code shown/copied on the receiver'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: retransmissionController,
                    decoration: const InputDecoration(labelText: 'Retransmission code (QRD1R|...)'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: FilledButton(onPressed: applyRetransmissionCode, child: const Text('Resend those chunks'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(onPressed: allFrames.isEmpty ? null : resumeFullLoop, child: const Text('Back to full loop'))),
                  ]),
                  if (resendNoticeText != null) ...[
                    const SizedBox(height: 8),
                    Text(resendNoticeText!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (encoding) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
        if (needsPassphrase)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Enter a passphrase and press Apply to generate encrypted QR frames.'),
          ),
        if (fileName != null && frames.isNotEmpty) ...[
          Text('File: $fileName'),
          Text('Size: $fileSizeBytes bytes'),
          const SizedBox(height: 8),
          ArtifactPreview(fileName: fileName!, bytes: selectedBytes),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: fps,
            decoration: const InputDecoration(labelText: 'Playback FPS'),
            items: fpsOptions.map((value) => DropdownMenuItem(value: value, child: Text('$value FPS'))).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                fps = value;
                estimate = TransferEstimator.estimate(
                  fileSizeBytes: fileSizeBytes!,
                  frameCount: allFrames.length,
                  fps: fps,
                  loopRedundancy: profile.loopRedundancy,
                );
              });
            },
          ),
          const SizedBox(height: 8),
          if (estimate != null)
            Text('Estimated transfer: ${estimate!.humanTime} (${allFrames.length} frames x ${profile.loopRedundancy} loops)'),
          const SizedBox(height: 16),
          Center(
            child: currentFrame == null
                ? const SizedBox.shrink()
                : Container(
                    color: Colors.white.withOpacity(brightness),
                    padding: EdgeInsets.all(roomIsDark ? 12 : 4),
                    decoration: roomIsDark
                        ? null
                        : BoxDecoration(border: Border.all(color: Colors.black, width: 3)),
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
          const Text('Privacy warning: QR frames are visible to any camera pointed at the screen. Turn on encryption before sending sensitive files.'),
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
