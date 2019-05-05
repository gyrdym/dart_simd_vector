import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ml_linalg/distance.dart';
import 'package:ml_linalg/matrix.dart';
import 'package:ml_linalg/norm.dart';
import 'package:ml_linalg/src/vector/common/simd_helper.dart';
import 'package:ml_linalg/src/vector/common/typed_list_factory.dart';
import 'package:ml_linalg/vector.dart';
import 'package:quiver/core.dart';
import 'package:quiver/iterables.dart';

abstract class BaseVector<E, S extends List<E>> with IterableMixin<double>
    implements Vector {

  BaseVector.fromList(
    List<double> source,
    this._bucketSize,
    this._typedListFactory,
    this._simdHelper,
  ) : length = source.length, _genInnerList = (() sync* {
    final numOfBuckets = (source.length / _bucketSize).ceil();
    final data = _simdHelper.createList(numOfBuckets);
    yield _genSimdList<E, S>(source, _bucketSize, data,
        _simdHelper.createFromList);
  });

  BaseVector.randomFilled(
    this.length,
    int seed,
    this._bucketSize,
    this._typedListFactory,
    this._simdHelper,
  ) {
    final random = math.Random(seed);
    final source = List<double>.generate(length, (_) => random.nextDouble());
//    data = _genSimdList(source);
  }

  BaseVector.filled(
    this.length,
    double value,
    this._bucketSize,
    this._typedListFactory,
    this._simdHelper,
  ) {
    final source = List<double>.filled(length, value);
//    data = _genSimdList(source);
  }

  BaseVector.zero(
    this.length,
    this._bucketSize,
    this._typedListFactory,
    this._simdHelper,
  ) {
    final source = List<double>.filled(length, 0.0);
//    data = _genSimdList(source);
  }

  BaseVector.fromSimdList(
    S source,
    this.length,
    this._bucketSize,
    this._typedListFactory,
    this._simdHelper,
  ) {
    _data = source;
  }

  final Function _genInnerList;

  S _data;

  @override
  Iterator<double> get iterator =>
      _typedListFactory.createIterator((_innerList as TypedData).buffer, length);

  @override
  final int length;

  @override
  final Type dtype = Float32x4;

  final int _bucketSize;
  final SimdHelper<E, S> _simdHelper;
  final TypedListFactory _typedListFactory;

  Iterable<E> get _dataWithoutLastBucket => _innerList
      .take(_innerList.length - 1);

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
    if (other is BaseVector<E, S>) {
      // TODO: consider checking hashcode here to compare two vectors
      if (length != other.length) {
        return false;
      }
      return zip<E>([_innerList, other._innerList]).any((values) =>
          _simdHelper.areValuesEqual(values.first, values.last));
    }
    return false;
  }

  @override
  int get hashCode => _hash ??= hashObjects(_innerList);

  @override
  Vector operator +(Object value) {
    if (value is Vector) {
      return _elementWiseVectorOperation(value, _simdHelper.sum);
    } else if (value is Matrix) {
      final other = value.toVector();
      return _elementWiseVectorOperation(other, _simdHelper.sum);
    } else if (value is num) {
      return _elementWiseSimdScalarOperation(
          _simdHelper.createFilled(value.toDouble()), _simdHelper.sum);
    }
    throw UnsupportedError('Unsupported operand type: ${value.runtimeType}');
  }

  @override
  Vector operator -(Object value) {
    if (value is Vector) {
      return _elementWiseVectorOperation(value, _simdHelper.sub);
    } else if (value is Matrix) {
      final other = value.toVector();
      return _elementWiseVectorOperation(other, _simdHelper.sub);
    } else if (value is num) {
      return _elementWiseSimdScalarOperation(
          _simdHelper.createFilled(value.toDouble()), _simdHelper.sub);
    }
    throw UnsupportedError('Unsupported operand type: ${value.runtimeType}');
  }

  @override
  Vector operator *(Object value) {
    if (value is Vector) {
      return _elementWiseVectorOperation(value, _simdHelper.mul);
    } else if (value is Matrix) {
      return _matrixMul(value);
    } else if (value is num) {
      return _elementWiseFloatScalarOperation(value.toDouble(),
          _simdHelper.scale);
    }
    throw UnsupportedError('Unsupported operand type: ${value.runtimeType}');
  }

  @override
  Vector operator /(Object value) {
    if (value is Vector) {
      return _elementWiseVectorOperation(value, _simdHelper.div);
    } else if (value is num) {
      return _elementWiseFloatScalarOperation(1 / value, _simdHelper.scale);
    }
    throw UnsupportedError('Unsupported operand type: ${value.runtimeType}');
  }

  @override
  Vector toIntegerPower(int power) => _elementWisePow(power);

  /// Returns a vector filled with absolute values of an each component of
  /// [this] vector
  @override
  Vector abs() =>
      _abs ??= _elementWiseSelfOperation((E element, [int i]) =>
          _simdHelper.abs(element));

  @override
  double dot(Vector vector) => (this * vector).sum();

  /// Returns sum of all vector components
  @override
  double sum() => _sum ??= _simdHelper.sumLanes(_innerList
      .reduce(_simdHelper.sum));

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
  double mean() => sum() / length;

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
  double max() {
    if (_maxValue == null) {
      if (_isLastBucketNotFull) {
        var max = -double.infinity;
        final fullBucketsList = _dataWithoutLastBucket;
        if (fullBucketsList.isNotEmpty) {
          max = _simdHelper.getMaxLane(fullBucketsList
              .reduce(_simdHelper.selectMax));
        }
        _maxValue = _simdHelper.toList(_innerList.last)
            .take(length % _bucketSize)
            .fold(max, math.max);
      } else {
        _maxValue = _simdHelper
            .getMaxLane(_innerList.reduce(_simdHelper.selectMax));
      }
    }
    return _maxValue;
  }

  @override
  double min() {
    if (_minValue == null) {
      if (_isLastBucketNotFull) {
        var min = double.infinity;
        final listOnlyWithFullBuckets = _dataWithoutLastBucket;
        if (listOnlyWithFullBuckets.isNotEmpty) {
          min = _simdHelper.getMinLane(listOnlyWithFullBuckets
              .reduce(_simdHelper.selectMin));
        }
        _minValue = _simdHelper.toList(_innerList.last)
            .take(length % _bucketSize)
            .fold(min, math.min);
      } else {
        _minValue = _simdHelper
            .getMinLane(_innerList.reduce(_simdHelper.selectMin));
      }
    }
    return _minValue;
  }

  @override
  Vector query(Iterable<int> indexes) {
    final list = _typedListFactory.empty(indexes.length);
    int i = 0;
    for (final idx in indexes) list[i++] = this[idx];
    return Vector.fromList(list, dtype: dtype);
  }

  @override
  Vector unique() => _unique ??= Vector
      .fromList(Set<double>.from(this).toList(growable: false), dtype: dtype);

  @override
  Vector fastMap<T>(T mapper(T element)) {
    final source = _innerList.map((value) => mapper(value as T))
        .toList(growable: false) as List<E>;
    return Vector.fromSimdList(_simdHelper.createListFrom(source), length,
        dtype: dtype);
  }

  @override
  double operator [](int index) {
    if (index >= length) throw RangeError.index(index, this);
    final base = (index / _bucketSize).floor();
    final offset = index - base * _bucketSize;
    return _simdHelper.getLaneByIndex(_innerList.elementAt(base), offset);
  }

  @override
  Vector subvector(int start, [int end]) {
    final collection = _typedListFactory
        .fromBuffer((_innerList as TypedData).buffer, start,
        (end > length ? length : end) - start);
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
  E _simdToIntPow(E lane, int power) {
    if (power == 0) {
      return _simdHelper.createFilled(1.0);
    }

    final x = _simdToIntPow(lane, power ~/ 2);
    final sqrX = _simdHelper.mul(x, x);

    if (power % 2 == 0) {
      return sqrX;
    }

    return _simdHelper.mul(lane, sqrX);
  }

  Iterable<E> get _innerList => _data ?? _genInnerList();

  /// Returns SIMD list (e.g. Float32x4List) as a result of converting iterable
  /// source
  ///
  /// All sequence of [source] elements splits into groups with
  /// [_bucketSize] length
  static Iterable<E> _genSimdList<E, S extends List<E>>(List<double> source,
      int bucketSize, S data, E simdValueFactory(List<double> source)) sync* {
    final numOfBuckets = (source.length / bucketSize).ceil();
    for (int i = 0; i < numOfBuckets; i++) {
      final start = i * bucketSize;
      final end = start + bucketSize;
      final bucketAsList = source.sublist(start, math.min(end, source.length));
      final value = simdValueFactory(bucketAsList);
      data[i] = value;
      yield value;
    }
  }

  /// Returns a vector as a result of applying to [this] any element-wise
  /// operation with a simd value
  Vector _elementWiseFloatScalarOperation(double arg, E operation(E a, double b)) {
    final source = _innerList.map((value) => operation(value, arg))
        .toList(growable: false);
    return Vector.fromSimdList(_simdHelper.createListFrom(source), length,
        dtype: dtype);
  }

  /// Returns a vector as a result of applying to [this] any element-wise
  /// operation with a simd value
  Vector _elementWiseSimdScalarOperation(E arg, E operation(E a, E b)) {
    final source = _innerList.map((value) => operation(value, arg))
        .toList(growable: false);
    return Vector.fromSimdList(_simdHelper.createListFrom(source), length,
        dtype: dtype);
  }

  /// Returns a vector as a result of applying to [this] any element-wise
  /// operation with a vector (e.g. vector addition)
  Vector _elementWiseVectorOperation(Vector arg, E operation(E a, E b)) {
    if (arg.length != length) throw _mismatchLengthError();
    final source = zip<E>([_innerList, (arg as BaseVector<E, S>)._innerList])
        .map((values) => operation(values.first, values.last))
        .toList(growable: false);
    return Vector.fromSimdList(_simdHelper.createListFrom(source), length,
        dtype: dtype);
  }

  Vector _elementWiseSelfOperation(E operation(E element, [int index])) {
    final source = _innerList.map(operation).toList(growable: false);
    return Vector.fromSimdList(_simdHelper.createListFrom(source), length,
        dtype: dtype);
  }

  /// Returns a vector as a result of applying to [this] element-wise raising
  /// to the integer power
  Vector _elementWisePow(int exp) {
    final source = _innerList.map((value) => _simdToIntPow(value, exp))
        .toList(growable: false);
    return Vector.fromSimdList(_simdHelper.createListFrom(source), length,
        dtype: dtype);
  }

  Vector _matrixMul(Matrix matrix) {
    if (length != matrix.rowsNum) {
      throw Exception(
          'Multiplication by a matrix with diffrent number of rows than the '
              'vector length is not allowed: vector length: $length, matrix '
              'row number: ${matrix.rowsNum}');
    }
    final source = List<double>.generate(
        matrix.columnsNum, (int i) => dot(matrix.getColumn(i)));
    return Vector.fromList(source, dtype: dtype);
  }

  RangeError _mismatchLengthError() =>
      RangeError('Vectors length must be equal');
}
