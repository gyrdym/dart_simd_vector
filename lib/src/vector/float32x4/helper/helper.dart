import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ml_linalg/src/vector/common/simd_helper.dart';

class Float32x4Helper
    implements SimdHelper<Float32x4, Float32x4List> {

  @override
  final bucketSize = 4;

  @override
  Float32x4 createFilled(double value) => Float32x4.splat(value);

  @override
  Float32x4 createFromList(List<double> list) {
    final x = list.isNotEmpty ? list[0] ?? 0.0 : 0.0;
    final y = list.length > 1 ? list[1] ?? 0.0 : 0.0;
    final z = list.length > 2 ? list[2] ?? 0.0 : 0.0;
    final w = list.length > 3 ? list[3] ?? 0.0 : 0.0;
    return Float32x4(x, y, z, w);
  }

  @override
  Float32x4 sum(Float32x4 a, Float32x4 b) => a + b;

  @override
  Float32x4 sub(Float32x4 a, Float32x4 b) => a - b;

  @override
  Float32x4 mul(Float32x4 a, Float32x4 b) => a * b;

  @override
  Float32x4 scale(Float32x4 a, double scalar) => a.scale(scalar);

  @override
  Float32x4 div(Float32x4 a, Float32x4 b) => a / b;

  @override
  Float32x4 abs(Float32x4 a) => a.abs();

  @override
  bool areValuesEqual(Float32x4 a, Float32x4 b) =>
    a.equal(b).signMask == 15;

  @override
  double sumLanes(Float32x4 a) =>
      (a.x.isNaN ? 0.0 : a.x) +
      (a.y.isNaN ? 0.0 : a.y) +
      (a.z.isNaN ? 0.0 : a.z) +
      (a.w.isNaN ? 0.0 : a.w);

  @override
  Float32x4List createList(int length) => Float32x4List(length);

  @override
  Float32x4List createListFrom(List<Float32x4> source) =>
      Float32x4List.fromList(source);

  @override
  double getLaneByIndex(Float32x4 value, int offset) {
    switch (offset) {
      case 0:
        return value.x;
      case 1:
        return value.y;
      case 2:
        return value.z;
      case 3:
        return value.w;
      default:
        throw RangeError('wrong offset');
    }
  }

  @override
  Float32x4 selectMax(Float32x4 a, Float32x4 b) => a.max(b);

  @override
  double getMaxLane(Float32x4 a) =>
      math.max(math.max(a.x, a.y), math.max(a.z, a.w));

  @override
  Float32x4 selectMin(Float32x4 a, Float32x4 b) => a.min(b);

  @override
  double getMinLane(Float32x4 a) =>
      math.min(math.min(a.x, a.y), math.min(a.z, a.w));

  @override
  List<double> toList(Float32x4 a) => <double>[a.x, a.y, a.z, a.w];

  @override
  List<double> takeFirstNLanes(Float32x4 a, int n) =>
      toList(a).take(n).toList();

  @override
  Float32x4List sublist(Float32x4List list, int start, [int end]) =>
      list.buffer.asFloat32x4List(start * Float32x4List.bytesPerElement, end);

  @override
  Float32x4 mutate(
      Float32x4 simd, int offset, double value) {
    switch (offset) {
      case 0:
        return simd.withX(value);
      case 1:
        return simd.withY(value);
      case 2:
        return simd.withZ(value);
      case 3:
        return simd.withW(value);
      default:
        throw RangeError('wrong offset');
    }
  }
}
