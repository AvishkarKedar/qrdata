# QRData

Offline file transfer over camera using animated QR frames. Android and
Windows, no internet/Bluetooth/cable/local network required.

## How it works
A sender selects a file (or multiple files, zipped), the app splits it into
chunks, encodes chunks into QR frames (optionally compressed and AES-256-GCM
encrypted), and plays them in a loop on screen. A receiver scans the frames
with a camera, verifies each chunk (CRC32) and the whole file (SHA-256),
reconstructs it, and previews common file types.

## Implemented
- Single Flutter codebase for Android and Windows.
- Send: file picker, multi-file picker zipped into one bundle, Windows
  drag-and-drop, transfer profiles (Reliable/Balanced/Fast/Extreme),
  selectable playback FPS (10/15/30/60/90/120), brightness + dark/light room
  presets, AES-256-GCM encryption with a shared passphrase, optional
  compression.
- Protocol: manifest frame, CRC32 per chunk, SHA-256 whole-file check, XOR
  parity (FEC) frames for lossy scans, persisted receive sessions (resume
  after the app is closed mid-transfer).
- Retransmission: receiver shows/copies a missing-chunk code; sender pastes
  it back in to replay only the missing chunks instead of the whole file.
- Receiver: runtime camera permission handling (Android/iOS), duplicate-file
  detection by content hash with a confirmation prompt, vibration feedback on
  a verified transfer, artifact preview for images/text (other types show a
  named file tile), a Windows QR reader using flutter_zxing.
- Diagnostics: local crash/error log with an in-app viewer (Home -> log
  icon), no third-party service or API key required.
- Attribution footer on the home screen linking to the developer's GitHub
  profile.
- CI (`\.github/workflows/flutter-ci.yml`): analyze + test, then build a real
  Android APK and Windows executable as downloadable Actions artifacts. See
  `docs/GETTING_BINARIES.md`.
- Optional real release signing for the Android APK once you add your own
  keystore as CI secrets -- see `docs/RELEASE_SIGNING.md`.

## Not yet implemented
- Adaptive FPS/QR-density negotiation based on live scan quality.
- Contrast/module-size tuning beyond the current brightness + room-mode
  presets.
- Rich previews for pdf/office/audio/video artifacts (currently a generic
  file tile with name + mime type).
- Automatic (non-manual) retransmission loop; today the receiver must
  show/copy the missing-chunk code and the sender must paste it in.

## Build
```bash
flutter pub get
flutter run -d android
flutter run -d windows
flutter build apk --release
flutter build windows --release
```
See `docs/GETTING_BINARIES.md` if you don't want to install the Flutter SDK
locally -- GitHub Actions builds both binaries on every push.

## Important engineering note
QR camera transfer must be tuned on real devices. High FPS is not guaranteed
on every camera/screen combination. Default to Reliable/Balanced mode, and
only use Fast/Extreme after testing on your actual hardware.
