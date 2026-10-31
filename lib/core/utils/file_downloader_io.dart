import 'dart:typed_data';
import 'package:printing/printing.dart';

void downloadFileBytes(
  List<int> bytes,
  String fileName, {
  String mimeType = 'text/csv;charset=utf-8;',
}) async {
  final uint8List = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  await Printing.sharePdf(bytes: uint8List, filename: fileName);
}
