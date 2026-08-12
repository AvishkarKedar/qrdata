import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../transfer/calibration.dart';
import '../transfer/encryption.dart';
import '../transfer/qr_decoder.dart';
import '../transfer/receive_session_store.dart';
import '../transfer/transfer_history_store.dart';
import '../diagnostics/app_logger.dart';
import '../widgets/artifact_preview.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final decoder = QRFileDecoder();
  final store = ReceiveSessionStore();
  final historyStore = TransferHistoryStore();
  final Set<String> _duplicateCheckedTransferIds = {};

  DecodedFile? decodedFile;
  String status = 'Point camera at sender QR screen';
  DateTime? startedAt;
  int decodedFrames = 0;
  bool finishing = false;

  // Mobile runtime permission state.
  bool _needsMobileCameraPermission = false;
  bool _cameraPermanentlyDenied = false;
  bool _permissionChecked = false;

  // Explicit controller (rather than letting MobileScanner create its own
  // default one) so the errorBuilder's Retry button can call start() again
  // after a failed camera start.
  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _ensureCameraPermission();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _scannerController.dispose();
    super.dispose();
  }

  bool get _isMobilePlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _ensureCameraPermission() async {
    if (!_isMobilePlatform) {
      setState(() => _permissionChecked = true);
      return;
    }
    var status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() {
      _permissionChecked = true;
      _needsMobileCameraPermission = !status.isGranted;
      _cameraPermanentlyDenied = status.isPermanentlyDenied;
    });
  }

  Future<void> onCode(String raw) async {
    if (finishing) return;
    startedAt ??= DateTime.now();
    decodedFrames++;
    final beforeChunks = decoder.chunks.length;
    decoder.acceptFrame(raw);

    final manifest = decoder.manifest;
    if (manifest != null) {
      await store.saveManifest(manifest);
      _checkDuplicate(manifest.transferId, manifest.sha256, manifest.fileName);
    }
    if (decoder.transferId != null && decoder.chunks.length > beforeChunks) {
      final newestSeq = decoder.chunks.keys.reduce((a, b) => a > b ? a : b);
      await store.saveChunk(transferId: decoder.transferId!, seq: newestSeq, bytes: decoder.chunks[newestSeq]!);
    }

    if (!mounted) return;
    setState(() => status = decoder.statusText);

    if (decoder.isComplete) {
      await _finish();
    }
  }

  void _checkDuplicate(String transferId, String sha256, String fileName) {
    if (_duplicateCheckedTransferIds.contains(transferId)) return;
    _duplicateCheckedTransferIds.add(transferId);
    historyStore.findBySha256(sha256).then((existing) {
      if (existing == null || !mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already received this file'),
          content: Text(
            'A file with identical contents ("${existing.fileName}") was already received on ${existing.receivedAt.toLocal()}. Continue scanning anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Discard, go back'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Continue anyway')),
          ],
        ),
      );
    });
  }

  Future<void> _finish() async {
    finishing = true;
    String? passphrase;
    if (decoder.manifest?.encrypted == true) {
      passphrase = await _promptPassphrase();
      if (passphrase == null || passphrase.isEmpty) {
        if (mounted) setState(() => status = 'Passphrase required to finish decrypting. Keep scanning and try again.');
        finishing = false;
        return;
      }
    }

    try {
      final result = await decoder.buildFile(passphrase: passphrase);
      if (result == null) {
        await AppLogger.log(
          'Integrity check failed for transfer ${decoder.transferId ?? 'unknown'} (${decoder.fileName ?? 'unknown file'})',
          level: 'ERROR',
        );
        if (mounted) setState(() => status = 'Integrity check failed. Waiting for a clean retransmission.');
        finishing = false;
        return;
      }
      if (!kIsWeb) {
        final dir = await getApplicationDocumentsDirectory();
        final out = File('${dir.path}/${result.fileName}');
        await out.writeAsBytes(result.bytes, flush: true);
        if (decoder.transferId != null) await store.delete(decoder.transferId!);
        if (decoder.fileSha256 != null) {
          await historyStore.record(sha256: decoder.fileSha256!, fileName: result.fileName);
        }
        await AppLogger.log('Received and saved ${result.fileName} (${result.bytes.length} bytes)');
        await _vibrateSuccess();
        if (mounted) {
          setState(() {
            decodedFile = result;
            status = 'Verified and saved: ${out.path}';
          });
        }
      } else if (mounted) {
        if (decoder.fileSha256 != null) {
          await historyStore.record(sha256: decoder.fileSha256!, fileName: result.fileName);
        }
        await _vibrateSuccess();
        setState(() {
          decodedFile = result;
          status = 'Verified: ${result.fileName}';
        });
      }
    } on QrEncryptionRequiredException catch (e) {
      await AppLogger.log('Decryption failed: ${e.message}', level: 'ERROR');
      if (mounted) setState(() => status = 'Decryption failed: ${e.message}');
    } finally {
      finishing = false;
    }
  }

  Future<void> _vibrateSuccess() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator) await Vibration.vibrate(duration: 200);
      }
    } catch (_) {
      // Vibration is a nice-to-have; never let it interrupt a successful transfer.
    }
  }

  Future<String?> _promptPassphrase() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter passphrase'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Passphrase used by the sender'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Decrypt')),
        ],
      ),
    );
  }

  double get actualFps {
    final start = startedAt;
    if (start == null) return 0;
    final elapsed = DateTime.now().difference(start).inMilliseconds / 1000;
    if (elapsed <= 0) return 0;
    return decodedFrames / elapsed;
  }

  /// Once enough frames have been observed, recommend a sender profile based
  /// on how fast this camera/device is actually able to decode frames. This
  /// is a lightweight stand-in for a full calibration screen: it uses the
  /// same `CalibrationEngine` that was previously written but never wired
  /// into any UI.
  CalibrationResult? get _calibration {
    if (decodedFrames < 20 || startedAt == null) return null;
    return CalibrationEngine.recommend(successfulFramesPerSecond: actualFps.round(), lowLight: false);
  }

  /// Plain-language guidance for a camera-start failure, keyed by the
  /// MobileScannerErrorCode reported by the platform layer.
  String _cameraErrorGuidance(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'The system denied camera permission to this app. Open Settings '
            '\u2192 Apps \u2192 qrdata \u2192 Permissions and allow Camera, then tap Retry.';
      case MobileScannerErrorCode.unsupported:
        return 'Android reported "No cameras available" when starting the camera. '
            'The most common cause is that an older copy of this app (installed '
            'before camera permission was added) is still on the device: fully '
            'uninstall the app, then install the latest build, so Android grants '
            'the new permission. If it still fails, close any other app that '
            'might be using the camera, restart the phone, then tap Retry.';
      case MobileScannerErrorCode.genericError:
        return 'The camera failed to start due to a transient error '
            '(${error.errorDetails?.message ?? error.errorCode.message}). This can '
            'happen briefly right after granting permission, or if another app is '
            'still holding the camera. Tap Retry; if it keeps happening, fully '
            'close any other camera app and restart the phone.';
      default:
        return error.errorDetails?.message ?? error.errorCode.message;
    }
  }

  Widget _buildScanner() {
    final isWindows = !kIsWeb && Platform.isWindows;

    if (isWindows) {
      // Reverted: an earlier attempt wired in the flutter_zxing native plugin
      // here, but it requires a CMake/NDK native build on both Android and
      // Windows that could not be verified in this sandbox and broke CI.
      // Reverted to this placeholder until a verified-working native Windows
      // camera+decode path is confirmed green in CI.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Windows camera scanner is not wired up yet. A prior attempt using a native barcode plugin broke the build and was reverted; '
            'a verified replacement is still pending. In the meantime, use an Android device to receive files.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isMobilePlatform && !_permissionChecked) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isMobilePlatform && _needsMobileCameraPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Camera permission is required to scan QR frames.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _cameraPermanentlyDenied ? openAppSettings : _ensureCameraPermission,
                child: Text(_cameraPermanentlyDenied ? 'Open app settings' : 'Grant camera permission'),
              ),
            ],
          ),
        ),
      );
    }

    return MobileScanner(
      controller: _scannerController,
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null) onCode(raw);
        }
      },
      // Without this, any camera-start failure (permission race, no camera
      // reported by the OS, a transient CameraX/HAL error, etc.) silently
      // rendered as a plain black box with a small error icon and no
      // explanation. Surface the real error code and give the user a way to
      // retry.
      errorBuilder: (context, error) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(
                  'Camera error: ${error.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(_cameraErrorGuidance(error), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _scannerController.start(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final missingReport = decoder.missingChunkReport;
    final calibration = _calibration;
    return Scaffold(
      appBar: AppBar(title: const Text('Receive file')),
      body: Column(
        children: [
          Expanded(child: _buildScanner()),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(status),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: decoder.progress),
                const SizedBox(height: 8),
                Text('${(decoder.progress * 100).toStringAsFixed(1)}% complete \u2022 Actual decoded FPS: ${actualFps.toStringAsFixed(1)}'),
                if (calibration != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Camera calibration: ${calibration.note} (try ~${calibration.recommendedFps} FPS on the sender)',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
                if (missingReport != null && decoder.progress > 0 && decoder.progress < 1) ...[
                  const SizedBox(height: 12),
                  const Text('Missing-chunk retransmission code (show this QR to the sender, or copy and paste it into the sender app)'),
                  Center(child: QrImageView(data: missingReport.toFrame(), size: 160)),
                  const SizedBox(height: 8),
                  Center(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy retransmission code'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: missingReport.toFrame()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Retransmission code copied. Paste it into the sender app.')),
                        );
                      },
                    ),
                  ),
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
