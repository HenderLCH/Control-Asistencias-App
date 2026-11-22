import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

Future<bool> downloadFileBytes(
  List<int> bytes,
  String fileName, {
  String mimeType = 'text/csv;charset=utf-8;',
}) async {
  final uint8List = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  try {
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar reporte',
      fileName: fileName,
      bytes: uint8List,
    );
    if (savedPath == null) {
      return false;
    }
    // En escritorio (Windows/macOS/Linux), saveFile solo devuelve la ruta y no escribe bytes automáticamente
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final file = File(savedPath);
      await file.writeAsBytes(uint8List, flush: true);
    }
    return true;
  } catch (_) {
    await Printing.sharePdf(bytes: uint8List, filename: fileName);
    return true;
  }
}
