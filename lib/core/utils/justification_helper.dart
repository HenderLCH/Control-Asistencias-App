import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';

class JustificationInfo {
  final String cleanReason;
  final String? attachmentName;
  final Uint8List? attachmentBytes;
  final List<DateTime> coveredDates;

  const JustificationInfo({
    required this.cleanReason,
    this.attachmentName,
    this.attachmentBytes,
    this.coveredDates = const [],
  });

  bool get hasAttachment => attachmentName != null && attachmentName!.trim().isNotEmpty;
  bool get hasViewableData => attachmentBytes != null && attachmentBytes!.isNotEmpty;
  bool get isPdf => attachmentName?.toLowerCase().endsWith('.pdf') ?? false;
  bool get isImage => hasAttachment && !isPdf;
}

class JustificationHelper {
  static final RegExp _attachmentNameRegex = RegExp(r'\[Adjunto:\s*([^\]]+)\]');
  static final RegExp _dataRegex = RegExp(r'\[DATA:([^\]]+)\]');
  static final RegExp _daysRegex = RegExp(r'\[DIAS:([^\]]+)\]');

  /// Parsea el campo `notes` de un registro de asistencia extrayendo el motivo limpio,
  /// el nombre del archivo adjunto, los bytes en base64 y las fechas cubiertas.
  static JustificationInfo parseNotes(String? rawNotes) {
    if (rawNotes == null || rawNotes.trim().isEmpty || rawNotes == '[DESMARCADO]') {
      return const JustificationInfo(cleanReason: '');
    }

    String? attachmentName;
    final nameMatch = _attachmentNameRegex.firstMatch(rawNotes);
    if (nameMatch != null) {
      attachmentName = nameMatch.group(1)?.trim();
    }

    Uint8List? attachmentBytes;
    final dataMatch = _dataRegex.firstMatch(rawNotes);
    if (dataMatch != null) {
      final b64 = dataMatch.group(1)?.trim();
      if (b64 != null && b64.isNotEmpty) {
        try {
          attachmentBytes = base64Decode(b64);
        } catch (_) {}
      }
    }

    final List<DateTime> coveredDates = [];
    final daysMatch = _daysRegex.firstMatch(rawNotes);
    if (daysMatch != null) {
      final rawDays = daysMatch.group(1)?.split(',') ?? [];
      for (final d in rawDays) {
        final parsed = DateTime.tryParse(d.trim());
        if (parsed != null) coveredDates.add(parsed);
      }
    }

    final clean = rawNotes
        .replaceAll(_attachmentNameRegex, '')
        .replaceAll(_dataRegex, '')
        .replaceAll(_daysRegex, '')
        .trim();

    return JustificationInfo(
      cleanReason: clean,
      attachmentName: attachmentName,
      attachmentBytes: attachmentBytes,
      coveredDates: coveredDates,
    );
  }

  /// Construye la cadena `notes` codificando el adjunto y las fechas cubiertas si existen.
  static String? buildNotes({
    required String reason,
    String? attachmentName,
    Uint8List? attachmentBytes,
    List<DateTime>? coveredDates,
  }) {
    final cleanReason = reason.trim();
    final hasFile = attachmentName != null && attachmentName.trim().isNotEmpty;
    final hasDays = coveredDates != null && coveredDates.length > 1;

    if (cleanReason.isEmpty && !hasFile && !hasDays) {
      return null;
    }

    final buffer = StringBuffer();
    buffer.write(cleanReason.isEmpty && hasFile ? 'Justificativo adjunto' : cleanReason);

    if (hasDays) {
      final sorted = List<DateTime>.from(coveredDates)..sort((a, b) => a.compareTo(b));
      final joined = sorted.map((d) => DateFormat('yyyy-MM-dd').format(d)).join(',');
      buffer.write(' [DIAS:$joined]');
    }

    if (hasFile) {
      buffer.write(' [Adjunto: ${attachmentName.trim()}]');
      if (attachmentBytes != null && attachmentBytes.isNotEmpty) {
        buffer.write('[DATA:${base64Encode(attachmentBytes)}]');
      }
    }

    return buffer.toString().trim();
  }

  /// Muestra un visor interactivo para consultar el justificativo (motivo + vista previa de Imagen o PDF)
  /// y ofrece un botón opcional para pasar a modo Edición.
  static Future<void> showJustificationViewer({
    required BuildContext context,
    required String studentName,
    required String? classroomName,
    required DateTime date,
    required String status,
    required String? rawNotes,
    bool canEdit = false,
    VoidCallback? onEdit,
  }) async {
    final info = parseNotes(rawNotes);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = AppTheme.getAttendanceColor(status);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 740),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  border: Border(
                    bottom: BorderSide(color: statusColor.withOpacity(0.25)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        AppTheme.getAttendanceIcon(status),
                        color: statusColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status == 'justificado'
                                ? 'Detalle del Justificativo'
                                : 'Detalle de Asistencia',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$studentName${classroomName != null ? " • $classroomName" : ""}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            DateFormat('EEEE, d MMMM yyyy', 'es').format(date),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),

              // Contenido desplazable
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Si el justificativo cubre múltiples días, mostrar todas las fechas cubiertas
                      if (info.coveredDates.length > 1) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.justified.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.justified.withOpacity(0.35)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.date_range_rounded, size: 18, color: AppTheme.justified),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Justificativo válido por ${info.coveredDates.length} días:',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.justified,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: info.coveredDates.map((d) {
                                  final isCurrent = DateUtils.isSameDay(d, date);
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? AppTheme.justified
                                          : AppTheme.justified.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      DateFormat('EEE d MMM', 'es').format(d),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isCurrent ? Colors.white : AppTheme.justified,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Motivo / Observación
                      const Text(
                        'Motivo / Observación:',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Text(
                          info.cleanReason.isNotEmpty
                              ? info.cleanReason
                              : 'Sin motivo escrito especificado.',
                          style: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Documento Adjunto (Imagen o PDF)
                      if (info.hasAttachment) ...[
                        Row(
                          children: [
                            Icon(
                              info.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Soporte adjunto: ${info.attachmentName}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (info.hasViewableData)
                              TextButton.icon(
                                onPressed: () async {
                                  await Printing.sharePdf(
                                    bytes: info.attachmentBytes!,
                                    filename: info.attachmentName ?? 'justificativo',
                                  );
                                },
                                icon: const Icon(Icons.download_rounded, size: 16),
                                label: const Text('Descargar', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (info.hasViewableData && info.isImage)
                          Container(
                            height: 320,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Theme.of(context).dividerColor),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InteractiveViewer(
                              minScale: 0.8,
                              maxScale: 4.0,
                              child: Image.memory(
                                info.attachmentBytes!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          )
                        else if (info.hasViewableData && info.isPdf)
                          Container(
                            height: 360,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Theme.of(context).dividerColor),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: PdfPreview(
                              build: (_) async => info.attachmentBytes!,
                              useActions: true,
                              canChangeOrientation: false,
                              canChangePageFormat: false,
                              canDebug: false,
                              pdfFileName: info.attachmentName ?? 'justificativo.pdf',
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? const Color(0xFFB45309) : const Color(0xFFF59E0B).withValues(alpha: 0.45),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Este archivo fue registrado antes de activar el visor integrado. Si deseas visualizarlo aquí, pulsa "Editar Justificativo" y vuelve a seleccionarlo.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? const Color(0xFFFEF3C7) : const Color(0xFF78350F),
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.attachment_rounded, size: 18, color: AppTheme.textSecondary),
                              SizedBox(width: 8),
                              Text(
                                'Sin archivo PDF o imagen adjunta.',
                                style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Botones inferiores
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cerrar'),
                    ),
                    if (canEdit && onEdit != null) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          onEdit();
                        },
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: const Text('Editar Justificativo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
