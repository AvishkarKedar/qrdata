# 30 suggestions for QRData

1. Use adaptive FPS instead of fixed FPS: receiver tells the sender the best stable speed.
2. Add an automatic calibration screen before transfer to test camera/display limits.
3. Start with 5-15 FPS for reliability; 30+ FPS should be advanced mode.
4. Use larger QR modules for low-end cameras and smaller modules only for good cameras.
5. Add Reed-Solomon or fountain-code forward error correction so missing frames do not break transfers.
6. Add per-chunk CRC32 and full-file SHA-256 validation, already planned in MVP.
7. Add a manifest QR frame with file name, type, size, hash, total chunks, and protocol version.
8. Add pause/resume support by saving received chunks locally.
9. Add retransmission mode: receiver shows a QR code listing missing chunks; sender replays only those chunks.
10. Compress files before QR encoding when the file type benefits from compression.
11. Skip compression for already-compressed formats like jpg, png, mp4, zip, pdf, docx, xlsx.
12. Add optional encryption with a passphrase or pairing QR so visible QR frames cannot leak data.
13. Add a privacy warning because anyone with a camera can capture visible QR frames.
14. Add transfer profiles: Reliable, Balanced, Fast, Extreme.
15. Add brightness and contrast controls on the sender screen.
16. Keep screen awake during transfers on Android and Windows.
17. Add automatic QR size scaling based on screen resolution.
18. Add camera focus/exposure lock on receiver.
19. Add support for batch file transfer as a folder-like package.
20. Add ZIP packaging for multiple files.
21. Add artifact previews for images, text, PDF thumbnails, audio/video metadata, and Office document metadata.
22. Add safe preview sandboxing: never execute received files.
23. Add duplicate transfer detection using file hash.
24. Add estimated transfer time that updates live based on actually decoded FPS.
25. Add progress sound/vibration feedback on Android.
26. Add dark-room mode with high-brightness white QR background.
27. Add light-room mode with high-contrast borders.
28. Add QR frame numbering visible below the QR for debugging.
29. Add detailed transfer logs for failed or corrupted transfers.
30. Consider using animated color QR or multiple QR regions only after black-and-white QR is reliable.
