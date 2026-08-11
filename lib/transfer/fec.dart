/// A lightweight forward-error-correction codec using XOR parity groups.
/// Each parity chunk lets the receiver reconstruct exactly one missing data
/// chunk within its group, without waiting for a full retransmission.
/// This is not as strong as Reed-Solomon, but it is simple, dependency-free,
/// and meaningfully improves reliability for an MVP.
class FecCodec {
  static List<List<int>> buildParity({
    required List<List<int>> chunks,
    required int parityCount,
    required int chunkSize,
  }) {
    if (parityCount <= 0 || chunks.isEmpty) return [];
    final parity = List.generate(parityCount, (_) => List<int>.filled(chunkSize, 0));
    for (var i = 0; i < chunks.length; i++) {
      final group = i % parityCount;
      final chunk = chunks[i];
      for (var b = 0; b < chunk.length; b++) {
        parity[group][b] ^= chunk[b];
      }
    }
    return parity;
  }

  /// Attempts to recover exactly one missing chunk in its parity group.
  /// Returns null when recovery is not possible (more than one chunk
  /// missing in the group, or the parity chunk itself is missing).
  static List<int>? recoverChunk({
    required int missingIndex,
    required int totalChunks,
    required int parityCount,
    required Map<int, List<int>> knownChunks,
    required List<int>? parityChunk,
    required int originalChunkLength,
  }) {
    if (parityChunk == null || parityCount <= 0) return null;
    final group = missingIndex % parityCount;
    final groupIndices = [for (var i = 0; i < totalChunks; i++) if (i % parityCount == group) i];
    final missingInGroup = groupIndices.where((i) => !knownChunks.containsKey(i)).toList();
    if (missingInGroup.length != 1 || missingInGroup.first != missingIndex) return null;

    final recovered = List<int>.from(parityChunk);
    for (final idx in groupIndices) {
      if (idx == missingIndex) continue;
      final chunk = knownChunks[idx]!;
      for (var b = 0; b < chunk.length && b < recovered.length; b++) {
        recovered[b] ^= chunk[b];
      }
    }
    if (recovered.length > originalChunkLength) {
      return recovered.sublist(0, originalChunkLength);
    }
    return recovered;
  }
}
