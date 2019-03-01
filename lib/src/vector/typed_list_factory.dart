import 'dart:typed_data' show ByteBuffer;

abstract class TypedListFactory {
  /// returns a typed list with
  List<double> createTypedListFromByteBuffer(ByteBuffer data);

  /// returns a typed list (e.g. Float32List) of length equals [length]
  List<double> createTypedList(int length);

  /// returns a typed list (e.g. Float32List) created using [list] as a source
  List<double> createTypedListFromList(List<double> list);

  List<double> bufferAsTypedList(ByteBuffer buffer, int start, int length);

  /// converts a buffer into typed list and gets its iterator
  Iterator<double> getIterator(ByteBuffer buffer, int length);
}