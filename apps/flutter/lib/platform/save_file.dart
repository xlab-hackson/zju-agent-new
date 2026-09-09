import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<void> saveBytes(String name,Uint8List bytes) async {
  final path=await FilePicker.platform.saveFile(fileName:name,bytes:bytes);
  // Desktop pickers select a path; mobile pickers write through the system document provider.
  if(path!=null && !Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes,flush:true);
}
