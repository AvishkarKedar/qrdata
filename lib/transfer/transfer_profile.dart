enum TransferProfile {
  reliable,
  balanced,
  fast,
  extreme,
}

extension TransferProfileConfig on TransferProfile {
  String get label => switch (this) {
        TransferProfile.reliable => 'Reliable',
        TransferProfile.balanced => 'Balanced',
        TransferProfile.fast => 'Fast',
        TransferProfile.extreme => 'Extreme',
      };

  int get recommendedFps => switch (this) {
        TransferProfile.reliable => 10,
        TransferProfile.balanced => 15,
        TransferProfile.fast => 30,
        TransferProfile.extreme => 60,
      };

  int get chunkSize => switch (this) {
        TransferProfile.reliable => 450,
        TransferProfile.balanced => 700,
        TransferProfile.fast => 900,
        TransferProfile.extreme => 1100,
      };

  int get loopRedundancy => switch (this) {
        TransferProfile.reliable => 4,
        TransferProfile.balanced => 3,
        TransferProfile.fast => 2,
        TransferProfile.extreme => 2,
      };

  double get fecOverhead => switch (this) {
        TransferProfile.reliable => 0.25,
        TransferProfile.balanced => 0.15,
        TransferProfile.fast => 0.08,
        TransferProfile.extreme => 0.0,
      };
}
