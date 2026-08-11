class TransferEstimate {
  final Duration duration;
  final double bytesPerSecond;

  TransferEstimate({required this.duration, required this.bytesPerSecond});

  /// Total estimated transfer time in seconds (fractional).
  double get totalSeconds => duration.inMilliseconds / 1000.0;

  String get humanTime {
    final seconds = duration.inSeconds;
    if (seconds < 60) return '$seconds sec';
    final minutes = seconds ~/ 60;
    final rem = seconds % 60;
    return '${minutes}m ${rem}s';
  }
}

class TransferEstimator {
  static TransferEstimate estimate({
    required int fileSizeBytes,
    required int frameCount,
    required int fps,
    int loopRedundancy = 2,
  }) {
    final totalFramesToShow = frameCount * loopRedundancy;
    final seconds = totalFramesToShow / fps;
    return TransferEstimate(
      duration: Duration(milliseconds: (seconds * 1000).ceil()),
      bytesPerSecond: fileSizeBytes / seconds,
    );
  }
}
