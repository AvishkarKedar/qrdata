class CalibrationResult {
  final int recommendedFps;
  final int recommendedChunkSize;
  final String note;

  const CalibrationResult({required this.recommendedFps, required this.recommendedChunkSize, required this.note});
}

class CalibrationEngine {
  static CalibrationResult recommend({required int successfulFramesPerSecond, required bool lowLight}) {
    if (lowLight || successfulFramesPerSecond < 12) {
      return const CalibrationResult(
        recommendedFps: 10,
        recommendedChunkSize: 450,
        note: 'Reliable mode recommended. Improve light and focus for faster transfer.',
      );
    }
    if (successfulFramesPerSecond < 25) {
      return const CalibrationResult(
        recommendedFps: 15,
        recommendedChunkSize: 700,
        note: 'Balanced mode recommended.',
      );
    }
    return const CalibrationResult(
      recommendedFps: 30,
      recommendedChunkSize: 900,
      note: 'Fast mode should work. Extreme mode may still fail on some cameras.',
    );
  }
}
