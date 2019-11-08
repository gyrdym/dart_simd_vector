import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ml_linalg/distance.dart';
import 'package:ml_linalg/dtype.dart';
import 'package:ml_linalg/matrix.dart';
import 'package:ml_linalg/norm.dart';
import 'package:ml_linalg/src/vector/simd_helper.dart';
import 'package:ml_linalg/src/vector/float32x4_helper.dart';
import 'package:ml_linalg/vector.dart';

const _bytesPerElement = Float32List.bytesPerElement;
const _bucketSize = Float32x4List.bytesPerElement ~/ Float32List.bytesPerElement;

/// Vector with SIMD (single instruction, multiple data) architecture support
///
/// An entity, that extends this class, may have potentially infinite length
/// (in terms of vector algebra - number of dimensions). Vector components are
/// contained in a special typed data structure, that allow to perform vector
/// operations extremely fast due to hardware assisted computations.
///
/// Let's assume some considerations:
///
/// - High performance of vector operations is provided by SIMD types of Dart
/// language
///
/// - Each SIMD-typed value is a "cell", that contains several floating point
/// values (2 or 4).
///
/// - Sequence of SIMD-values forms a "computation lane", where computations
/// are performed with each floating point element simultaneously (in parallel)
class Float32x4Vector with IterableMixin<double> implements Vector {
  Float32x4Vector.fromList(List<num> source) :
        length = source.length,
        _numOfBuckets = _getNumOfBuckets(source.length, _bucketSize),
        _buffer = _getBuffer(
            _getNumOfBuckets(source.length, _bucketSize) * _bucketSize,
            _bytesPerElement) {
    _setByteData((i) => source[i]);
  }

  Float32x4Vector.randomFilled(this.length, int seed, {
    num min = 0,
    num max = 1,
  }) :
        _numOfBuckets = _getNumOfBuckets(length, _bucketSize),
        _buffer = _getBuffer(
            _getNumOfBuckets(length, _bucketSize) * _bucketSize,
            _bytesPerElement) {
    final generator = math.Random(seed);
    final diff = (max - min).abs();
    final realMin = math.min(min, max);
    _setByteData((i) => generator.nextDouble() * diff + realMin);
  }

  Float32x4Vector.filled(this.length, num value) :
        _numOfBuckets = _getNumOfBuckets(length, _bucketSize),
        _buffer = _getBuffer(
            _getNumOfBuckets(length, _bucketSize) * _bucketSize,
            _bytesPerElement) {
    _setByteData((_) => value);
  }

  Float32x4Vector.zero(this.length) :
        _numOfBuckets = _getNumOfBuckets(length, _bucketSize),
        _buffer = _getBuffer(
            _getNumOfBuckets(length, _bucketSize) * _bucketSize,
            _bytesPerElement) {
    _setByteData((_) => 0.0);
  }

  Float32x4Vector.fromSimdList(Float32x4List data, this.length) :
        _numOfBuckets = _getNumOfBuckets(length, _bucketSize),
        _buffer = data.buffer {
    _cachedInnerSimdList = data;
  }

  Float32x4Vector.empty() :
        length = 0,
        _numOfBuckets = 0,
        _buffer = _getBuffer(0, _bytesPerElement);

  static int _getNumOfBuckets(int length, int bucketSize) =>
      (length / bucketSize).ceil();

  static ByteBuffer _getBuffer(int length, int bytesPerElement) =>
      ByteData(length * bytesPerElement).buffer;

  @override
  final int length;

  final SimdHelper _simdHelper = const Float32x4Helper();
  final ByteBuffer _buffer;
  final int _numOfBuckets;

  @override
  Iterator<double> get iterator => _innerTypedList.iterator;

  Float32x4List get _innerSimdList =>
      _cachedInnerSimdList ??= _buffer.asFloat32x4List();
  Float32x4List _cachedInnerSimdList;

  List<double> get _innerTypedList =>
      _cachedInnerTypedList ??= _buffer.asFloat32List(0, length);
  Float32List _cachedInnerTypedList;

  bool get _isLastBucketNotFull => length % _bucketSize > 0;

  // Vector's cache
  final Map<Norm, double> _cachedNorms = {};
  double _maxValue;
  double _minValue;
  Vector _normalized;
  Vector _rescaled;
  Vector _unique;
  Vector _abs;
  double _sum;
  int _hash;

  @override
  bool operator ==(Object other) {
    if (other is Float32x4Vector) {
      if (length != other.length) {
        return false;
      }
      for (int i = 0; i < _numOfBuckets; i++) {
        if (_innerSimdList[i].equal(other._innerSimdList[i]).signMask != 15) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  @override
  int get hashCode => _hash ??= length > 0 ? _generateHash() : 0;

  int _generateHash() {
    int i = 0;
    final simdHash = _innerSimdList.reduce(
            (sum, element) => sum + element.scale((31 * (i++)) * 1.0));
    return _simdHelper.sumLanesForHash(simdHash) ~/ 1;
  }

  @override
  Vector operator +(Object value) {
    if (value is Vector) {
      return _elementWiseVectorOperation(value, (a, b) => a + b);
    } else if (value is Matrix) {
      final other = value.toVector();
      return _elementWiseVectorOperation(other, (a, b) => a + b);
    } else if (value is num) {
      return _elementWiseScalarOperation<Float32x4>(
          Float32x4.splat(value.toDouble()), (a, b) => a + b);
    }
    throw UnsupportedError('Unsupported operand type: ${value.runtimeType}');
  }

  @override
  Vector operator -(Object value) {
    if (value is Vector) {
      return _elementWiseVectorOperation(value, (a, b) => a - b);
    } else if (value is Matrix) {
      final other = value.toVector();
      return _elementWiseVectorOperation(other, (a, b) => a - b);
    } else if (value is num) {
      return _elementWiseScalarOperation<Float32x4>(
          Float32x4.splat(value.toDouble()), (a, b) => a - b);
    }
    throw UnsupportedError('Unsupported operand type: ${value.runtimeType}');
  }

  @override
  Vector operator *(Object value) {
    if (value is Vector) {
      return _elementWiseVectorOperation(value, (a, b) => a * b);
    } else if (value is Matrix) {
      return _matrixMul(value);
    } else if (value is num) {
      return _elementWiseScalarOperation<double>(value.toDouble(),
          (a, b) => a.scale(b));
    }
    throw UnsupportedError('Unsupported operand type: ${value.runtimeType}');
  }

  @override
  Vector operator /(Object value) {
    if (value is Vector) {
      return _elementWiseVectorOperation(value, (a, b) => a / b);
    } else if (value is num) {
      return _elementWiseScalarOperation<double>(1 / value, (a, b) => a.scale(b));
    }
    throw UnsupportedError('Unsupported operand type: ${value.runtimeType}');
  }

  @override
  Vector sqrt() => _elementWiseSelfOperation((el, [_]) => el.sqrt());

  @override
  Vector scalarDiv(num scalar) => this / scalar;

  @override
  Vector toIntegerPower(int power) => _elementWisePow(power);

  @override
  Vector abs() =>
      _abs ??= _elementWiseSelfOperation((element, [int i]) => element.abs());

  @override
  double dot(Vector vector) => (this * vector).sum();

  /// Returns sum of all vector components
  @override
  double sum() => _sum ??= _simdHelper.sumLanes(_innerSimdList
      .reduce((a, b) => a + b));

  @override
  double distanceTo(Vector other, {
    Distance distance = Distance.euclidean,
  }) {
    switch (distance) {
      case Distance.euclidean:
        return (this - other).norm(Norm.euclidean);
      case Distance.manhattan:
        return (this - other).norm(Norm.manhattan);
      case Distance.cosine:
        return 1 - getCosine(other);
      default:
        throw UnimplementedError('Unimplemented distance type - $distance');
    }
  }

  @override
  double getCosine(Vector other) {
    final cosine = (dot(other) / norm(Norm.euclidean) /
        other.norm(Norm.euclidean));
    if (cosine.isInfinite || cosine.isNaN) {
      throw Exception('It is impossible to find cosine of an angle of two '
          'vectors if at least one of the vectors is zero-vector');
    }
    return cosine;
  }

  @override
  double mean() {
    if (isEmpty) {
      throw _emptyVectorException;
    }
    return sum() / length;
  }

  @override
  double norm([Norm norm = Norm.euclidean]) {
    if (!_cachedNorms.containsKey(norm)) {
      final power = _getPowerByNormType(norm);
      if (power == 1) {
        return abs().sum();
      }
      _cachedNorms[norm] = math.pow(toIntegerPower(power)
          .sum(), 1 / power) as double;
    }
    return _cachedNorms[norm];
  }

  @override
  double max() =>
      _maxValue ??= _findExtrema(-double.infinity, _simdHelper.getMaxLane,
          (a, b) => a.max(b), math.max);

  @override
  double min() =>
      _minValue ??= _findExtrema(double.infinity, _simdHelper.getMinLane,
              (a, b) => a.min(b), math.min);

  double _findExtrema(double initialValue,
      double getExtremalLane(Float32x4 bucket),
      Float32x4 getExtremalBucket(Float32x4 first, Float32x4 second),
      double getExtremalValue(double first, double second),
  ) {
    if (_isLastBucketNotFull) {
      var extrema = initialValue;
      final fullBucketsList = _innerSimdList.take(_numOfBuckets - 1);
      if (fullBucketsList.isNotEmpty) {
        extrema = getExtremalLane(fullBucketsList.reduce(getExtremalBucket));
      }
      return _simdHelper.simdValueToList(_innerSimdList.last)
          .take(length % _bucketSize)
          .fold(extrema, getExtremalValue);
    } else {
      return getExtremalLane(_innerSimdList.reduce(getExtremalBucket));
    }
  }

  @override
  Vector sample(Iterable<int> indices) {
    final list = Float32List(indices.length);
    int i = 0;
    for (final idx in indices) {
      list[i++] = this[idx];
    }
    return Vector.fromList(list, dtype: dtype);
  }

  @override
  Vector unique() => _unique ??= Vector
      .fromList(Set<double>.from(this).toList(growable: false), dtype: dtype);

  @override
  Vector fastMap<T>(T mapper(T element)) {
    final source = _innerSimdList.map<Float32x4>(
            (value) => mapper(value as T) as Float32x4).toList(growable: false);
    return Vector.fromSimdList(Float32x4List.fromList(source), length,
        dtype: dtype);
  }

  @override
  double operator [](int index) {
    if (isEmpty) {
      throw _emptyVectorException;
    }
    if (index >= length) {
      throw RangeError.index(index, this);
    }
    return _innerTypedList[index];
  }

  @override
  Vector subvector(int start, [int end]) {
    if (start < 0) {
      throw RangeError.range(start, 0, length - 1, '`start` cannot'
          ' be negative');
    }
    if (end != null && start >= end) {
      throw RangeError.range(start, 0,
          length - 1, '`start` cannot be greater than or equal to `end`');
    }
    if (start >= length) {
      throw RangeError.range(start, 0,
          length - 1, '`start` cannot be greater than or equal to the vector'
              'length');
    }
    final limit = end == null || end > length ? length : end;
    final collection = _innerTypedList.sublist(start, limit);
    return Vector.fromList(collection, dtype: dtype);
  }

  @override
  Vector normalize([Norm normType = Norm.euclidean]) =>
      _normalized ??= this / norm(normType);

  @override
  Vector rescale() {
    if (_rescaled == null) {
      final minValue = min();
      final maxValue = max();
      _rescaled = (this - minValue) / (maxValue - minValue);
    }
    return _rescaled;
  }

  /// Returns exponent depending on vector norm type (for Euclidean norm - 2,
  /// Manhattan - 1)
  int _getPowerByNormType(Norm norm) {
    switch (norm) {
      case Norm.euclidean:
        return 2;
      case Norm.manhattan:
        return 1;
      default:
        throw UnsupportedError('Unsupported norm type!');
    }
  }

  /// Returns a SIMD value raised to the integer power
  Float32x4 _simdToIntPow(Float32x4 lane, num power) {
    if (power == 0) {
      return Float32x4.splat(1.0);
    }

    final x = _simdToIntPow(lane, power ~/ 2);
    final sqrX = x * x;

    if (power % 2 == 0) {
      return sqrX;
    }

    return lane * sqrX;
  }

  Vector _elementWiseScalarOperation<T>(T arg,
      Float32x4 operation(Float32x4 a, T b)) {
    final source = _innerSimdList.map((value) => operation(value, arg))
        .toList(growable: false);
    return Vector.fromSimdList(Float32x4List.fromList(source), length,
        dtype: dtype);
  }

  /// Returns a vector as a result of applying to [this] any element-wise
  /// operation with a vector (e.g. vector addition)
  Vector _elementWiseVectorOperation(Vector arg,
      Float32x4 operation(Float32x4 a, Float32x4 b)) {
    if (arg.length != length) {
      throw _mismatchLengthError;
    }
    final other = arg as Float32x4Vector;
    final source = Float32x4List(_numOfBuckets);
    for (int i = 0; i < _numOfBuckets; i++) {
      source[i] = operation(_innerSimdList[i], other._innerSimdList[i]);
    }
    return Vector.fromSimdList(source, length, dtype: dtype);
  }

  Vector _elementWiseSelfOperation(Float32x4 operation(Float32x4 element, [int index])) {
    final source = _innerSimdList.map(operation).toList(growable: false);
    return Vector.fromSimdList(Float32x4List.fromList(source), length,
        dtype: dtype);
  }

  /// Returns a vector as a result of applying to [this] element-wise raising
  /// to the integer power
  Vector _elementWisePow(int exp) {
    final source = _innerSimdList.map((value) => _simdToIntPow(value, exp))
        .toList(growable: false);
    return Vector.fromSimdList(Float32x4List.fromList(source), length,
        dtype: dtype);
  }

  Vector _matrixMul(Matrix matrix) {
    if (length != matrix.rowsNum) {
      throw Exception(
          'Multiplication by a matrix with diffrent number of rows than the '
              'vector length is not allowed: vector length: $length, matrix '
              'row number: ${matrix.rowsNum}');
    }
    final source = List.generate(
        matrix.columnsNum, (int i) => dot(matrix.getColumn(i)));
    return Vector.fromList(source, dtype: dtype);
  }

  void _setByteData(num generateValue(int i)) {
    final byteData = _buffer.asByteData();
    var byteOffset = -_bytesPerElement;
    for (int i = 0; i < length; i++) {
      byteData.setFloat32(
          byteOffset += _bytesPerElement,
          generateValue(i).toDouble(),
          Endian.host,
      );
    }
  }

  Exception get _emptyVectorException =>
      Exception('The vector is empty');

  RangeError get _mismatchLengthError =>
      RangeError('Vectors length must be equal');

  @override
  DType get dtype => DType.float32;
}
