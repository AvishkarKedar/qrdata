String crc32Hex(List<int> bytes) {
  var crc = 0xffffffff;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      final mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xedb88320 & mask);
    }
  }
  crc = crc ^ 0xffffffff;
  return crc.toUnsigned(32).toRadixString(16).padLeft(8, '0');
}
