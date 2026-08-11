# QRData MVP

Offline file transfer over camera using animated QR frames.

## Goal
QRData lets Android and Windows devices send and receive files without internet, Bluetooth, cables, or local network. A sender selects a file, the app splits it into chunks, encodes chunks into QR frames, and plays them in a loop. A receiver scans the frames, verifies chunks, reconstructs the file, and previews common file types.

## MVP scope
- Single Flutter codebase for Android and Windows.
- Encode any selected file into QR frame payloads.
- Animated QR playback at selectable FPS: 30, 60, 90, 120.
- Decode scanned QR frames and assemble file chunks.
- Per-chunk CRC32 validation and full-file SHA-256 validation.
- Transfer estimate based on file size, chunk size, redundancy, and FPS.
- Basic artifact preview support plan for images, text, PDF, office files, audio, and video.

## Recommended stack
- Flutter for Android + Windows.
- Dart core transfer protocol shared by both platforms.
- Android camera scanning via `mobile_scanner`.
- Windows camera scanning via native plugin or OpenCV/ZBar bridge in the next phase.

## MVP limitations
This first commit contains the protocol, project structure, and UI/logic scaffold. Windows camera decoding needs a native scanner implementation before production use. High FPS QR transfer depends heavily on display refresh rate, camera exposure, focus, and QR density.

## Transfer protocol
Each QR frame is text:

```text
QRD1|<transferId>|<seq>|<total>|<chunkSize>|<fileNameB64>|<mimeB64>|<fileSize>|<fileSha256>|<chunkCrc32>|<chunkBase64>
```

The receiver accepts frames in any order, deduplicates by sequence number, validates each chunk CRC32, and validates the final SHA-256 before saving.

## Run
```bash
flutter pub get
flutter run -d android
flutter run -d windows
```

## Build
```bash
flutter build apk --release
flutter build windows --release
```

## Roadmap
See `docs/SUGGESTIONS.md` for 30 product and technical improvements.
