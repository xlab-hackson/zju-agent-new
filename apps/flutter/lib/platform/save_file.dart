import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<void> saveBytes(String name, Uint8List bytes) async {
  // file_picker 12 writes the bytes on every platform. Android can return a
  // content URI, which must never be treated as a filesystem path here.
  await FilePicker.saveFile(fileName: name, bytes: bytes);
}
