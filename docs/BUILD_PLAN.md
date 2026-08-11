# QRData build plan

We will build and verify one layer at a time.

## Phase 1 — Core protocol
Status: started

Verification:
- CRC32 known-value test.
- Manifest round-trip test.
- Encode/decode reconstruction test.
- Out-of-order frame test.
- Missing-chunk report test.

## Phase 2 — Sender UX
Status: scaffolded

Verification:
- File picker works on Android and Windows.
- Drag-and-drop works on Windows.
- QR playback loops at selected FPS.
- Estimated time changes with profile and FPS.

## Phase 3 — Receiver UX
Status: scaffolded

Verification:
- Android camera detects QR frames.
- Progress increases only for valid chunks.
- Duplicate frames do not corrupt output.
- Final SHA-256 must match before saving.

## Phase 4 — Reliability
Status: next

Build:
- Persistent partial chunk storage.
- Real retransmission flow.
- Real FEC/parity recovery.

## Phase 5 — Security
Status: next

Build:
- AES-GCM encryption.
- Passphrase/pairing flow.
- Clear warnings for unencrypted transfers.

## Phase 6 — Windows receiver
Status: next native milestone

Build:
- OpenCV camera capture.
- ZBar or ZXing QR decoder bridge.
- Focus/exposure controls where supported.

## Phase 7 — Artifact previews
Status: scaffolded

Build:
- Image preview.
- Text preview.
- PDF thumbnail/info.
- Office metadata preview.
- Audio/video metadata preview.

## CI verification
GitHub Actions runs:
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`
