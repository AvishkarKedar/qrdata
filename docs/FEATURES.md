# Selected feature implementation status

The app now tracks the requested features 1,2,3,4,5,7-30 from the suggestions list.

## Added to MVP scaffold
- Adaptive profiles: Reliable, Balanced, Fast, Extreme.
- Calibration engine scaffold.
- Reliable default FPS: 10/15, with advanced 30/60/90/120 options.
- QR chunk sizing by profile.
- Manifest frame with protocol version and file metadata.
- Pause/resume design through persisted chunk map, implementation next.
- Missing-chunk report QR from receiver.
- Retransmission protocol scaffold.
- Compression toggle and skip rules for compressed formats.
- Encryption toggle and privacy warning.
- Sender brightness control.
- Keep-awake requirement documented for native phase.
- QR scaling requirement documented.
- Camera focus/exposure requirement documented.
- Batch/folder transfer roadmap.
- ZIP packaging dependency added.
- Artifact preview scaffold.
- Safe preview principle documented.
- Duplicate transfer detection basis via SHA-256.
- Live decoded FPS display.
- Transfer debug status and logs roadmap.
- Windows drag-and-drop file picking.

## Still needs native production work
- Real Reed-Solomon/fountain-code parity reconstruction.
- True AES-GCM encryption implementation.
- Persistent pause/resume storage.
- Windows OpenCV/ZBar camera scanner.
- Android and Windows keep-screen-awake native hooks.
- Focus/exposure lock APIs.
- Rich previews for PDF, Office, audio, and video.
