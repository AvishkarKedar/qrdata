# QRData MVP

Offline file transfer over camera using animated QR frames.

## Goal
QRData lets Android and Windows devices send and receive files without internet, Bluetooth, cables, or local network. A sender selects a file, the app splits it into chunks, encodes chunks into QR frames, and plays them in a loop. A receiver scans the frames, verifies chunks, reconstructs the file, and previews common file types.

## Current MVP
- Single Flutter codebase for Android and Windows.
- Android send/receive scaffold.
- Windows send app with file picker and drag-and-drop.
- Windows receive screen scaffold for upcoming native camera bridge.
- Encode any selected file into QR frame payloads.
- Animated QR playback at selectable FPS: 10, 15, 30, 60, 90, 120.
- Transfer profiles: Reliable, Balanced, Fast, Extreme.
- Manifest frame before data frames.
- Missing-chunk report QR for retransmission design.
- Per-chunk CRC32 validation and full-file SHA-256 validation.
- Transfer estimate and live decoded FPS.
- Privacy warning and encryption/compression UI toggles.
- Artifact preview scaffold.

## Build
```bash
flutter pub get
flutter run -d android
flutter run -d windows
flutter build apk --release
flutter build windows --release
```

## Important engineering note
QR camera transfer must be tuned on real devices. High FPS is not guaranteed. The app should default to Reliable/Balanced mode, then unlock Fast/Extreme only after calibration.

## Next production milestone
1. Add Windows camera decoding using OpenCV + ZBar/ZXing native bridge.
2. Add real FEC reconstruction.
3. Add AES-GCM encryption.
4. Add persistent pause/resume chunks.
5. Add rich file previews.
