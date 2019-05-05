// Performance test of vector (10 000 elements in vector) multiplication operation
// It takes approximately 0.175 microseconds (MacBook Air 2017)

import 'dart:math' as math;

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:ml_linalg/src/vector/float32x4/float32x4_vector.dart';

const amountOfElements = 10000;

Float32x4Vector vector;

class VectorUniqueBenchmark extends BenchmarkBase {
  const VectorUniqueBenchmark()
      : super('Vector unnique elements obtaining, $amountOfElements elements');

  static void main() {
    const VectorUniqueBenchmark().report();
  }

  @override
  void run() {
    vector.unique();
  }

  @override
  void setup() {
    final generator = math.Random(DateTime.now().millisecondsSinceEpoch);
    vector = Float32x4Vector.fromList(List<double>.generate(
        amountOfElements, (int idx) => generator.nextDouble()));
  }

  void tearDown() {
    vector = null;
  }
}

void main() {
  VectorUniqueBenchmark.main();
}
