import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_rig/widgets/scan_luma_preview.dart';

void main() {
  test('rotateLuma90Cw turns landscape into portrait', () {
    // 2x3: rows [1,2] [3,4] [5,6]
    final src = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
    final rotated = rotateLuma90Cw(src, 2, 3);
    expect(rotated.$2, 3); // width
    expect(rotated.$3, 2); // height
    // 90 CW: [5,3,1] [6,4,2]
    expect(rotated.$1, Uint8List.fromList([5, 3, 1, 6, 4, 2]));
  });
}
