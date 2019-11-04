import 'dart:typed_data';

import 'package:ml_linalg/dtype.dart';
import 'package:ml_linalg/src/common/float32_list_helper/float32_list_helper.dart';
import 'package:ml_linalg/src/matrix/base_matrix.dart';
import 'package:ml_linalg/src/matrix/common/data_manager/matrix_data_manager_impl.dart';
import 'package:ml_linalg/vector.dart';

class Float32Matrix extends BaseMatrix {
  Float32Matrix.fromList(List<List<double>> source) :
        super(MatrixDataManagerImpl.fromList(
          source,
          Float32List.bytesPerElement,
          DType.float32,
          Float32ListHelper()));

  Float32Matrix.columns(List<Vector> source) :
        super(MatrixDataManagerImpl.fromColumns(
          source,
          Float32List.bytesPerElement,
          DType.float32,
          Float32ListHelper()));

  Float32Matrix.rows(List<Vector> source) :
        super(MatrixDataManagerImpl.fromRows(
          source,
          Float32List.bytesPerElement,
          DType.float32,
          Float32ListHelper()));

  Float32Matrix.empty() :
        super(MatrixDataManagerImpl.fromList(
          [<double>[]],
          Float32List.bytesPerElement,
          DType.float32,
          Float32ListHelper()));

  Float32Matrix.flattened(List<double> source, int rowsNum,
      int columnsNum) :
        super(MatrixDataManagerImpl.fromFlattened(
          source,
          rowsNum,
          columnsNum,
          Float32List.bytesPerElement,
          DType.float32,
          Float32ListHelper()));

  Float32Matrix.diagonal(List<double> source) :
        super(MatrixDataManagerImpl.diagonal(
          source,
          Float32List.bytesPerElement,
          DType.float32,
          Float32ListHelper()));

  Float32Matrix.scalar(double scalar, int size) :
        super(MatrixDataManagerImpl.scalar(
          scalar,
          size,
          Float32List.bytesPerElement,
          DType.float32,
          Float32ListHelper()));

  @override
  final DType dtype = DType.float32;
}
