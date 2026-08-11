import 'package:flutter_test/flutter_test.dart';
import 'package:qrdata/transfer/crc32.dart';
import 'package:qrdata/transfer/manifest.dart';
import 'package:qrdata/transfer/qr_decoder.dart';
import 'package:qrdata/transfer/qr_encoder.dart';
import 'package:qrdata/transfer/retransmission.dart';
import 'package:qrdata/transfer/transfer_estimator.dart';
import 'package:qrdata/transfer/transfer_profile.dart';

void main() {
  test('crc32 gives stable known value', () {
    expect(crc32Hex('hello'.codeUnits), '3610a686');
  });

  test('manifest round-trips through QR frame', () {
    const manifest = TransferManifest(
      protocol: 'QRD1',
      transferId: 'abc',
      fileName: 'photo.png',
      mimeType: 'image/png',
      fileSize: 10,
      sha256: 'hash',
      totalChunks: 2,
      chunkSize: 5,
      fecChunks: 1,
      encrypted: false,
      compressed: false,
    );

    final parsed = TransferManifest.tryParse(manifest.toFrame());
    expect(parsed, isNotNull);
    expect(parsed!.fileName, 'photo.png');
    expect(parsed.totalChunks, 2);
  });

  test('encoder and decoder reconstruct file without corruption', () {
    final bytes = List<int>.generate(4096, (i) => i % 256);
    final encoder = QRFileEncoder(chunkSize: 333, profile: TransferProfile.reliable);
    final transfer = encoder.encodeFile(fileName: 'sample.bin', mimeType: 'application/octet-stream', bytes: bytes);

    final decoder = QRFileDecoder();
    DecodedFile? decoded;
    for (final frame in transfer.frames.reversed) {
      decoded ??= decoder.acceptFrame(frame);
    }
    for (final frame in transfer.frames) {
      decoded ??= decoder.acceptFrame(frame);
    }

    expect(decoded, isNotNull);
    expect(decoded!.fileName, 'sample.bin');
    expect(decoded.bytes, bytes);
    expect(decoder.progress, 1.0);
  });

  test('decoder reports missing chunks', () {
    final bytes = List<int>.generate(1200, (i) => i % 200);
    final transfer = QRFileEncoder(chunkSize: 300).encodeFile(fileName: 'partial.bin', mimeType: 'application/octet-stream', bytes: bytes);
    final decoder = QRFileDecoder();

    decoder.acceptFrame(transfer.frames.first);
    decoder.acceptFrame(transfer.frames[1]);

    expect(decoder.progress, greaterThan(0));
    expect(decoder.progress, lessThan(1));
    expect(decoder.missingChunks, isNotEmpty);
    expect(decoder.missingChunkReport!.toFrame(), startsWith('QRD1R|'));
  });

  test('retransmission request filters only missing data frames', () {
    final bytes = List<int>.generate(1000, (i) => i % 256);
    final transfer = QRFileEncoder(chunkSize: 250).encodeFile(fileName: 'again.bin', mimeType: 'application/octet-stream', bytes: bytes);
    final request = RetransmissionRequest(transferId: transfer.manifest.transferId, missing: {1, 3});
    final filtered = RetransmissionFilter.onlyMissingFrames(frames: transfer.frames, request: request);

    expect(filtered.length, 2);
    expect(filtered.every((frame) => frame.startsWith('QRD1|')), isTrue);
    expect(filtered.any((frame) => frame.split('|')[2] == '1'), isTrue);
    expect(filtered.any((frame) => frame.split('|')[2] == '3'), isTrue);
  });

  test('decoder can restore partial session', () {
    final bytes = List<int>.generate(900, (i) => i % 100);
    final transfer = QRFileEncoder(chunkSize: 300).encodeFile(fileName: 'resume.bin', mimeType: 'application/octet-stream', bytes: bytes);
    final firstDecoder = QRFileDecoder();
    firstDecoder.acceptFrame(transfer.frames[0]);
    firstDecoder.acceptFrame(transfer.frames[1]);

    final secondDecoder = QRFileDecoder();
    secondDecoder.restore(savedManifest: transfer.manifest, savedChunks: Map<int, List<int>>.from(firstDecoder.chunks));
    DecodedFile? decoded;
    for (final frame in transfer.frames.skip(2)) {
      decoded ??= secondDecoder.acceptFrame(frame);
    }

    expect(decoded, isNotNull);
    expect(decoded!.bytes, bytes);
  });

  test('transfer estimator computes duration', () {
    final estimate = TransferEstimator.estimate(fileSizeBytes: 1000, frameCount: 60, fps: 30, loopRedundancy: 2);
    expect(estimate.duration.inSeconds, 4);
  });
}
