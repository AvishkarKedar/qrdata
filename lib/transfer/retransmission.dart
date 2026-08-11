class RetransmissionRequest {
  final String transferId;
  final Set<int> missing;

  const RetransmissionRequest({required this.transferId, required this.missing});

  String toFrame() => 'QRD1R|$transferId|${missing.toList()..sort()}';

  static RetransmissionRequest? tryParse(String raw) {
    if (!raw.startsWith('QRD1R|')) return null;
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    final missing = parts[2].isEmpty
        ? <int>{}
        : parts[2].split(',').map(int.tryParse).whereType<int>().toSet();
    return RetransmissionRequest(transferId: parts[1], missing: missing);
  }
}

class RetransmissionFilter {
  static List<String> onlyMissingFrames({required List<String> frames, required RetransmissionRequest request}) {
    return frames.where((frame) {
      if (!frame.startsWith('QRD1|')) return false;
      final parts = frame.split('|');
      if (parts.length != 11) return false;
      if (parts[1] != request.transferId) return false;
      final seq = int.tryParse(parts[2]);
      return seq != null && request.missing.contains(seq);
    }).toList();
  }
}
