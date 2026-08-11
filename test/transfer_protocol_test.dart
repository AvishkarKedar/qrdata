import 'package:flutter_test/flutter_test.dart';
import 'package:qrdata/transfer/crc32.dart';
import 'package:qrdata/transfer/encryption.dart';
import 'package:qrdata/transfer/fec.dart';
import 'package:qrdata/transfer/manifest.dart';
import 'package:qrdata/transfer/qr_decoder.dart';
import 'package:qrdata/transfer/qr_encoder.dart';
import 'package:qrdata/transfer/retransmission.dart';
import 'package:qrdata/transfer/transfer_estimator.dart';
import 'package:qrdata/transfer/transfer_profile.dart';

void main() {
  test('crc32Hex is deterministic and detects changes', () {
    final a = crc32Hex([1, 2, 3, 4]);
    final b = crc32Hex([1, 2, 3, 4]);
    final c = crc32Hex([1, 2, 3, 5]);
    expect(a, b);
    expect(a, isNot(c));
  });

  test('manifest round-trips through toFrame/tryParse', () {
    const manifest = TransferManifest(
      protocol: 'QRD1',
      transferId: 'abc123',
      fileName: 'photo.png',
      mimeType: 'image/png',
      fileSize: 2048,
      payloadSize: 2048,
      sha256: 'deadbeef',
      totalChunks: 3,
      chunkSize: 700,
      fecChunks: 1,
      encrypted: false,
      compressed: false,
    );
    final frame = manifest.toFrame();
    final parsed = TransferManifest.tryParse(frame);
    expect(parsed, isNotNull);
    expect(parsed!.transferId, 'abc123');
    expect(parsed.totalChunks, 3);
    expect(parsed.payloadSize, 2048);
  });

  test('encoder and decoder reconstruct file without corruption', () async {
    final bytes = List<int>.generate(4096, (i) => i % 256);
    final encoder = QRFileEncoder(chunkSize: 333, profile: TransferProfile.reliable);
    final transfer = await encoder.encodeFile(
      fileName: 'sample.bin',
      mimeType: 'application/octet-stream',
      bytes: bytes,
    );

    final decoder = QRFileDecoder();
    for (final frame in transfer.frames.reversed) {
      decoder.acceptFrame(frame);
    }
    for (final frame in transfer.frames) {
      decoder.acceptFrame(frame);
    }

    expect(decoder.isComplete, isTrue);
    final decoded = await decoder.buildFile();
    expect(decoded, isNotNull);
    expect(decoded!.fileName, 'sample.bin');
    expect(decoded.bytes, bytes);
    expect(decoder.progress, 1.0);
  });

  test('decoder reports missing chunks', () async {
    final bytes = List<int>.generate(1200, (i) => i % 200);
    final transfer = await QRFileEncoder(chunkSize: 300).encodeFile(
      fileName: 'partial.bin',
      mimeType: 'application/octet-stream',
      bytes: bytes,
    );
    final decoder = QRFileDecoder();

    decoder.acceptFrame(transfer.frames[0]); // manifest
    decoder.acceptFrame(transfer.frames[1]); // data chunk 0
    decoder.acceptFrame(transfer.frames[2]); // data chunk 1

    expect(decoder.progress, greaterThan(0));
    expect(decoder.progress, lessThan(1));
    expect(decoder.missingChunks, isNotEmpty);
    expect(decoder.missingChunkReport!.toFrame(), startsWith('QRD1R|'));
  });

  test('decoder can restore partial session', () async {
    final bytes = List<int>.generate(900, (i) => i % 100);
    final transfer = await QRFileEncoder(chunkSize: 300).encodeFile(
      fileName: 'resume.bin',
      mimeType: 'application/octet-stream',
      bytes: bytes,
    );
    final firstDecoder = QRFileDecoder();
    firstDecoder.acceptFrame(transfer.frames[0]); // manifest
    firstDecoder.acceptFrame(transfer.frames[1]); // data chunk 0

    final secondDecoder = QRFileDecoder();
    secondDecoder.restore(savedManifest: transfer.manifest, savedChunks: Map<int, List<int>>.from(firstDecoder.chunks));
    for (final frame in transfer.frames.skip(2)) {
      secondDecoder.acceptFrame(frame);
    }

    expect(secondDecoder.isComplete, isTrue);
    final decoded = await secondDecoder.buildFile();
    expect(decoded, isNotNull);
    expect(decoded!.bytes, bytes);
  });

  test('retransmission request filters only missing data frames', () async {
    final bytes = List<int>.generate(1000, (i) => i % 50);
    final transfer = await QRFileEncoder(chunkSize: 250).encodeFile(
      fileName: 'filter.bin',
      mimeType: 'application/octet-stream',
      bytes: bytes,
    );
    final request = RetransmissionRequest(transferId: transfer.manifest.transferId, missing: {0, 2});
    final filter = RetransmissionFilter(request);

    final toResend = transfer.frames.where((f) => filter.shouldResend(f)).toList();
    expect(toResend.length, 2);
  });

  test('transfer estimator produces a positive human time estimate', () {
    final estimate = TransferEstimator.estimate(
      fileSizeBytes: 5 * 1024 * 1024,
      frameCount: 800,
      fps: 30,
      loopRedundancy: 2,
    );
    expect(estimate.totalSeconds, greaterThan(0));
    expect(estimate.humanTime, isNotEmpty);
  });

  test('FEC codec recovers exactly one missing chunk per parity group', () {
    const chunkSize = 4;
    final chunks = [
      [1, 2, 3, 4],
      [5, 6, 7, 8],
      [9, 10, 11, 12],
      [13, 14, 15, 16],
    ];
    final parity = FecCodec.buildParity(chunks: chunks, parityCount: 2, chunkSize: chunkSize);
    final known = <int, List<int>>{0: chunks[0], 1: chunks[1], 3: chunks[3]};
    final recovered = FecCodec.recoverChunk(
      missingIndex: 2,
      totalChunks: 4,
      parityCount: 2,
      knownChunks: known,
      parityChunk: parity[0],
      originalChunkLength: chunkSize,
    );
    expect(recovered, chunks[2]);
  });

  test('FEC codec declines recovery when two chunks in a group are missing', () {
    const chunkSize = 4;
    final chunks = [
      [1, 2, 3, 4],
      [5, 6, 7, 8],
      [9, 10, 11, 12],
      [13, 14, 15, 16],
    ];
    final parity = FecCodec.buildParity(chunks: chunks, parityCount: 2, chunkSize: chunkSize);
    final known = <int, List<int>>{1: chunks[1], 3: chunks[3]};
    final recovered = FecCodec.recoverChunk(
      missingIndex: 2,
      totalChunks: 4,
      parityCount: 2,
      knownChunks: known,
      parityChunk: parity[0],
      originalChunkLength: chunkSize,
    );
    expect(recovered, isNull);
  });

  test('encoder + decoder auto-heal one missing chunk per group using FEC', () async {
    final bytes = List<int>.generate(2400, (i) => i % 256);
    final transfer = await QRFileEncoder(chunkSize: 300, profile: TransferProfile.reliable).encodeFile(
      fileName: 'heal.bin',
      mimeType: 'application/octet-stream',
      bytes: bytes,
    );

    final decoder = QRFileDecoder();
    // Drop exactly one data frame (seq 1) and feed everything else, including
    // the FEC parity frames, so the decoder can self-heal.
    for (final frame in transfer.frames) {
      final isDroppedChunk = frame.startsWith('QRD1|') && frame.split('|')[2] == '1';
      if (isDroppedChunk) continue;
      decoder.acceptFrame(frame);
    }

    expect(decoder.isComplete, isTrue);
    final decoded = await decoder.buildFile();
    expect(decoded, isNotNull);
    expect(decoded!.bytes, bytes);
  });

  test('encrypted transfer round-trips and rejects the wrong passphrase', () async {
    final bytes = List<int>.generate(2000, (i) => i % 256);
    final encoder = QRFileEncoder(chunkSize: 400, encrypted: true);
    final transfer = await encoder.encodeFile(
      fileName: 'secret.bin',
      mimeType: 'application/octet-stream',
      bytes: bytes,
      passphrase: 'correct horse battery staple',
    );

    final decoder = QRFileDecoder();
    for (final frame in transfer.frames) {
      decoder.acceptFrame(frame);
    }
    expect(decoder.isComplete, isTrue);

    final decoded = await decoder.buildFile(passphrase: 'correct horse battery staple');
    expect(decoded, isNotNull);
    expect(decoded!.bytes, bytes);

    final decoder2 = QRFileDecoder();
    for (final frame in transfer.frames) {
      decoder2.acceptFrame(frame);
    }
    await expectLater(
      decoder2.buildFile(passphrase: 'wrong passphrase'),
      throwsA(isA<QrEncryptionRequiredException>()),
    );
  });
}
