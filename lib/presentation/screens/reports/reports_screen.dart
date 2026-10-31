import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:csv/csv.dart';
import 'package:contro_asistencias/core/utils/file_downloader.dart';
import 'package:contro_asistencias/providers/attendance_provider.dart';
import 'package:contro_asistencias/providers/student_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:contro_asistencias/presentation/widgets/common/logo_loading_indicator.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/constants/app_constants.dart';
import 'package:contro_asistencias/data/models/classroom.dart';
import 'package:contro_asistencias/data/models/attendance_record.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // Modalidad: true = Consolidado de los 12 salones, false = Por Salón
  bool _isInstitutional = true;
  String _selectedReportType = AppConstants.reportDaily;
  DateTime _selectedDailyDate = DateTime.now();
  Classroom? _selectedClassroom;
  bool _showAbsentStudentNames = false; // Opción: visualizar nombres de estudiantes inasistentes

  bool _isGenerating = false;
  bool _hasGenerated = false;

  // Datos de reportes
  List<ClassroomAttendanceSummary> _institutionalData = [];
  List<AttendanceSummary> _classroomData = [];

  String _getHeaderDateTitle() {
    final dayNames = ['LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES', 'SÁBADO', 'DOMINGO'];
    if (_selectedReportType == AppConstants.reportDaily) {
      final dayName = dayNames[_selectedDailyDate.weekday - 1];
      final d = _selectedDailyDate.day.toString().padLeft(2, '0');
      final m = _selectedDailyDate.month.toString().padLeft(2, '0');
      final y = _selectedDailyDate.year.toString();
      return '$dayName $d-$m-$y';
    } else {
      final range = _getDateRange();
      final d1 = range.start.day.toString().padLeft(2, '0');
      final m1 = range.start.month.toString().padLeft(2, '0');
      final y1 = range.start.year.toString();
      final d2 = range.end.day.toString().padLeft(2, '0');
      final m2 = range.end.month.toString().padLeft(2, '0');
      final y2 = range.end.year.toString();
      return '${_reportTypeLabel(_selectedReportType).toUpperCase()} ($d1-$m1-$y1 AL $d2-$m2-$y2)';
    }
  }

  DateTimeRange _getDateRange() {
    final now = DateTime.now();
    switch (_selectedReportType) {
      case AppConstants.reportDaily:
        final start = DateTime(_selectedDailyDate.year, _selectedDailyDate.month, _selectedDailyDate.day);
        final end = DateTime(_selectedDailyDate.year, _selectedDailyDate.month, _selectedDailyDate.day, 23, 59, 59);
        return DateTimeRange(start: start, end: end);
      case AppConstants.reportWeekly:
        final start = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(start: DateTime(start.year, start.month, start.day), end: now);
      case AppConstants.reportBiweekly:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 14)),
          end: now,
        );
      case AppConstants.reportMonthly:
      default:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: now,
        );
    }
  }

  String _reportTypeLabel(String type) {
    switch (type) {
      case AppConstants.reportDaily:
        return 'Diario';
      case AppConstants.reportWeekly:
        return 'Semanal';
      case AppConstants.reportBiweekly:
        return 'Quincenal';
      case AppConstants.reportMonthly:
        return 'Mensual';
      default:
        return type;
    }
  }

  Future<void> _pickDailyDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDailyDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Seleccionar fecha para el reporte diario',
      cancelText: 'Cancelar',
      confirmText: 'Seleccionar',
    );
    if (picked != null && picked != _selectedDailyDate) {
      setState(() {
        _selectedDailyDate = picked;
        _hasGenerated = false;
      });
    }
  }

  Future<void> _generateReport() async {
    final studentProvider = context.read<StudentProvider>();
    final attendanceProvider = context.read<AttendanceProvider>();
    final dateRange = _getDateRange();

    if (!_isInstitutional && _selectedClassroom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecciona un salón para el reporte'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    await runWithLoading(
      context,
      () async {
        setState(() {
          _isGenerating = true;
          _hasGenerated = false;
        });

        if (_isInstitutional) {
          if (studentProvider.classrooms.isEmpty) {
            await studentProvider.loadClassrooms();
          }
          final summaries = await attendanceProvider.generateInstitutionalReport(
            classrooms: studentProvider.classrooms,
            startDate: dateRange.start,
            endDate: dateRange.end,
          );
          if (mounted) {
            setState(() {
              _institutionalData = summaries;
              _isGenerating = false;
              _hasGenerated = true;
            });
          }
        } else {
          final summaries = await attendanceProvider.generateReport(
            classroomId: _selectedClassroom!.id,
            startDate: dateRange.start,
            endDate: dateRange.end,
          );
          if (mounted) {
            setState(() {
              _classroomData = summaries;
              _isGenerating = false;
              _hasGenerated = true;
            });
          }
        }
      },
      message: _isInstitutional
          ? 'Generando reporte institucional (12 salones)...'
          : 'Generando reporte de ${_selectedClassroom?.displayName}...',
    );
  }

  // ==========================================
  // DESCARGA CSV INSTITUCIONAL (12 SALONES)
  // ==========================================
  Future<void> _exportInstitutionalCsv() async {
    if (_institutionalData.isEmpty) return;

    await runWithLoading(
      context,
      () async {
        final headerDate = _getHeaderDateTitle();
    final dateRange = _getDateRange();
    final periodName = _selectedReportType == AppConstants.reportDaily
        ? 'Diario_${DateFormat('yyyyMMdd').format(_selectedDailyDate)}'
        : '${_reportTypeLabel(_selectedReportType)}_${DateFormat('yyyyMMdd').format(dateRange.start)}_al_${DateFormat('yyyyMMdd').format(dateRange.end)}';

    final List<List<dynamic>> rows = [
      ['COLEGIO NUESTRA SEÑORA DE LA CONSOLACIÓN DE TÁRIBA'],
      ['REPORTE GENERAL DE ASISTENCIA CONSOLIDADA - 12 SALONES'],
      ['Fecha / Período:', headerDate],
      ['Criterio de Cálculo:', 'Solo "Ausente" cuenta como Inasistencia (Faltó). Tardanzas y Justificados NO son inasistencias.'],
      [],
    ];

    final headers = [
      'Salón',
      'Profesor Titular',
      'Matrícula Total',
      'Matrícula V',
      'Matrícula H',
      'Presentes',
      'Asistió V',
      'Asistió H',
      'Inasistencias (FALTÓ)',
      'Falta V',
      'Falta H',
      'Tardanzas (No faltó)',
      'Justificados (No faltó)',
      '% Inasistencia',
      '% Asistencia',
    ];
    if (_showAbsentStudentNames) {
      headers.add('Estudiantes Inasistentes (Nombres)');
    }
    rows.add(headers);

    int totEnrolled = 0;
    int totMale = 0;
    int totFemale = 0;
    int totPresent = 0;
    int totPresentMale = 0;
    int totPresentFemale = 0;
    int totAbsent = 0;
    int totAbsentMale = 0;
    int totAbsentFemale = 0;
    int totLate = 0;
    int totJustified = 0;

    for (final s in _institutionalData) {
      totEnrolled += s.totalEnrolled;
      totMale += s.maleEnrolled;
      totFemale += s.femaleEnrolled;
      totPresent += s.presentDays;
      totPresentMale += s.presentMaleDays;
      totPresentFemale += s.presentFemaleDays;
      totAbsent += s.absentDays;
      totAbsentMale += s.absentMaleDays;
      totAbsentFemale += s.absentFemaleDays;
      totLate += s.lateDays;
      totJustified += s.justifiedDays;

      final row = <dynamic>[
        s.displayName,
        s.teacherName ?? 'Sin asignar',
        s.totalEnrolled,
        s.maleEnrolled,
        s.femaleEnrolled,
        s.presentDays,
        s.presentMaleDays,
        s.presentFemaleDays,
        s.absentDays,
        s.absentMaleDays,
        s.absentFemaleDays,
        s.lateDays,
        s.justifiedDays,
        '${s.absenceRate.toStringAsFixed(1)}%',
        '${s.attendanceRate.toStringAsFixed(1)}%',
      ];

      if (_showAbsentStudentNames) {
        if (s.absentStudents.isNotEmpty) {
          final names = s.absentStudents
              .map((st) => '${st.studentName} (${st.genderBadge})')
              .join('; ');
          row.add(names);
        } else {
          row.add('Ninguno');
        }
      }

      rows.add(row);
    }

    final totalRecords = totPresent + totAbsent + totLate + totJustified;
    final totalAbsRate = totalRecords > 0 ? (totAbsent / totalRecords * 100) : 0;
    final totalAttRate = totalRecords > 0 ? ((totPresent + totLate) / totalRecords * 100) : 0;

    final totalRow = <dynamic>[
      'TOTAL INSTITUCIÓN (12 SALONES)',
      '--',
      totEnrolled,
      totMale,
      totFemale,
      totPresent,
      totPresentMale,
      totPresentFemale,
      totAbsent,
      totAbsentMale,
      totAbsentFemale,
      totLate,
      totJustified,
      '${totalAbsRate.toStringAsFixed(1)}%',
      '${totalAttRate.toStringAsFixed(1)}%',
    ];
    if (_showAbsentStudentNames) {
      totalRow.add('--');
    }
    rows.add(totalRow);

    // Si tiene activa la opción de ver estudiantes inasistentes, agregar una tabla detallada al final
    if (_showAbsentStudentNames) {
      rows.add([]);
      rows.add(['DETALLE DE ESTUDIANTES INASISTENTES POR SALÓN']);
      rows.add(['Salón', 'Profesor Titular', 'Estudiante', 'Cédula', 'Sexo', 'Inasistencias en Período']);
      for (final s in _institutionalData) {
        for (final st in s.absentStudents) {
          rows.add([
            s.displayName,
            s.teacherName ?? 'Sin asignar',
            st.studentName,
            st.cedula.isNotEmpty ? st.cedula : 'S/C',
            st.isMale ? 'Varón (V)' : 'Hembra (H)',
            st.count,
          ]);
        }
      }
    }

    final csvString = const ListToCsvConverter().convert(rows);
    final bom = [0xEF, 0xBB, 0xBF];
    final bytes = [...bom, ...utf8.encode(csvString)];
    downloadFileBytes(bytes, 'Reporte_Asistencia_$periodName.csv');

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Descargando archivo CSV...'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  },
  message: 'Exportando reporte a Excel (CSV)...',
);
}

  // ==========================================
  // DESCARGA CSV POR SALÓN ESPECÍFICO
  // ==========================================
  Future<void> _exportClassroomCsv() async {
    if (_classroomData.isEmpty || _selectedClassroom == null) return;

    await runWithLoading(
      context,
      () async {
        final dateRange = _getDateRange();
        final dateStr = DateFormat('dd/MM/yyyy').format(dateRange.start);
        final dateEndStr = DateFormat('dd/MM/yyyy').format(dateRange.end);
        final periodName = _selectedReportType == AppConstants.reportDaily
            ? 'Diario_${DateFormat('yyyyMMdd').format(_selectedDailyDate)}'
            : '${_reportTypeLabel(_selectedReportType)}_${DateFormat('yyyyMMdd').format(dateRange.start)}_al_${DateFormat('yyyyMMdd').format(dateRange.end)}';

        final List<List<dynamic>> rows = [
          ['COLEGIO NUESTRA SEÑORA DE LA CONSOLACIÓN DE TÁRIBA'],
          ['REPORTE DE ASISTENCIA - ${_selectedClassroom!.displayName.toUpperCase()}'],
          ['Tipo de Reporte:', _reportTypeLabel(_selectedReportType)],
          ['Rango de Fechas:', _selectedReportType == AppConstants.reportDaily ? dateStr : '$dateStr al $dateEndStr'],
          ['Criterio de Cálculo:', 'Solo "Ausente" cuenta como Inasistencia (Faltó). Tardanzas y Justificados NO son inasistencias.'],
          [],
          [
            '#',
            'Cédula',
            'Estudiante',
            'Sexo',
            'Presentes',
            'Inasistencias (FALTÓ)',
            'Tardanzas (No faltó)',
            'Justificados (No faltó)',
            'Total Evaluados',
            '% Inasistencia',
            '% Asistencia',
          ],
        ];

        int i = 1;
        for (final s in _classroomData) {
          rows.add([
            i++,
            s.cedula.isNotEmpty ? s.cedula : 'S/C',
            s.studentName,
            s.genderLabel,
            s.presentDays,
            s.absentDays,
            s.lateDays,
            s.justifiedDays,
            s.totalDays,
            '${s.absenceRate.toStringAsFixed(1)}%',
            '${s.attendanceRate.toStringAsFixed(1)}%',
          ]);
        }

        final csvString = const ListToCsvConverter().convert(rows);
        final bom = [0xEF, 0xBB, 0xBF];
        final bytes = [...bom, ...utf8.encode(csvString)];
        final safeName = _selectedClassroom!.displayName.replaceAll(' ', '_');
        downloadFileBytes(bytes, 'Reporte_${safeName}_$periodName.csv');

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Descargando CSV de ${_selectedClassroom!.displayName}...'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      },
      message: 'Exportando CSV de ${_selectedClassroom!.displayName}...',
    );
  }

  // ==========================================
  // EXPORTAR PDF
  // ==========================================
  Future<void> _exportPdf() async {
    await runWithLoading(
      context,
      () async {
        final dateRange = _getDateRange();
        final pdf = pw.Document();

        // Cargar logo para el PDF
        Uint8List? logoBytes;
        try {
          final byteData = await rootBundle.load(AppConstants.logoAsset);
          logoBytes = byteData.buffer.asUint8List();
        } catch (_) {}

        if (_isInstitutional) {
          if (_institutionalData.isEmpty) return;
          final headerDate = _getHeaderDateTitle();

          int totEnrolled = 0;
          int totMale = 0;
          int totFemale = 0;
          int totPresent = 0;
          int totPresentMale = 0;
          int totPresentFemale = 0;
          int totAbsent = 0;
          int totAbsentMale = 0;
          int totAbsentFemale = 0;
          int totLate = 0;
          int totJustified = 0;

          for (final s in _institutionalData) {
            totEnrolled += s.totalEnrolled;
            totMale += s.maleEnrolled;
            totFemale += s.femaleEnrolled;
            totPresent += s.presentDays;
            totPresentMale += s.presentMaleDays;
            totPresentFemale += s.presentFemaleDays;
            totAbsent += s.absentDays;
            totAbsentMale += s.absentMaleDays;
            totAbsentFemale += s.absentFemaleDays;
            totLate += s.lateDays;
            totJustified += s.justifiedDays;
          }

          final totalRecords = totPresent + totAbsent + totLate + totJustified;
          final totalAbsRate = totalRecords > 0 ? (totAbsent / totalRecords * 100) : 0;
          final totalAttRate = totalRecords > 0 ? ((totPresent + totLate) / totalRecords * 100) : 0;

          pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4.landscape,
              margin: const pw.EdgeInsets.all(24),
              header: (context) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Row(
                        children: [
                          if (logoBytes != null) ...[
                            pw.Image(pw.MemoryImage(logoBytes), width: 34, height: 34),
                            pw.SizedBox(width: 8),
                          ],
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                AppConstants.institutionName,
                                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                              ),
                              pw.Text(
                                AppConstants.institutionLocation,
                                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                              ),
                            ],
                          ),
                        ],
                      ),
                      pw.Text(
                        headerDate,
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Reporte General de Asistencia - 12 Salones (${_reportTypeLabel(_selectedReportType)})',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'Criterio: Solo "Ausente" cuenta como falta. Tardanzas y Justificados NO son inasistencias.',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                  ),
                  pw.Divider(),
                ],
              ),
          build: (context) => [
            pw.Table.fromTextArray(
              headers: [
                'Salón',
                'Profesor',
                'Matrícula',
                'V/H',
                'Presentes',
                'Asist. V/H',
                'Inasist. (Faltó)',
                'Falta V/H',
                'Tardanzas',
                'Justif.',
                '% Inasist.',
                '% Asist.',
                if (_showAbsentStudentNames) 'Inasistentes',
              ],
              data: [
                ..._institutionalData.map((s) {
                  return [
                    s.displayName,
                    s.teacherName ?? 'Sin asignar',
                    '${s.totalEnrolled}',
                    '${s.maleEnrolled}/${s.femaleEnrolled}',
                    '${s.presentDays}',
                    '${s.presentMaleDays}V/${s.presentFemaleDays}H',
                    '${s.absentDays}',
                    '${s.absentMaleDays}V/${s.absentFemaleDays}H',
                    '${s.lateDays}',
                    '${s.justifiedDays}',
                    '${s.absenceRate.toStringAsFixed(1)}%',
                    '${s.attendanceRate.toStringAsFixed(1)}%',
                    if (_showAbsentStudentNames)
                      s.absentStudents.isNotEmpty
                          ? s.absentStudents.map((st) => '${st.studentName} (${st.genderBadge})').join(', ')
                          : 'Ninguno',
                  ];
                }),
                // Total
                [
                  'TOTAL',
                  '--',
                  '$totEnrolled',
                  '$totMale/$totFemale',
                  '$totPresent',
                  '${totPresentMale}V/${totPresentFemale}H',
                  '$totAbsent',
                  '${totAbsentMale}V/${totAbsentFemale}H',
                  '$totLate',
                  '$totJustified',
                  '${totalAbsRate.toStringAsFixed(1)}%',
                  '${totalAttRate.toStringAsFixed(1)}%',
                  if (_showAbsentStudentNames) '--',
                ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
              border: pw.TableBorder.all(color: PdfColors.grey300),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) => pdf.save(),
        name: 'Reporte_General_12_Salones.pdf',
      );
    } else {
      if (_classroomData.isEmpty || _selectedClassroom == null) return;
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                AppConstants.institutionName,
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Reporte de Asistencia - ${_selectedClassroom!.displayName}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Período: ${DateFormat('dd/MM/yyyy').format(dateRange.start)} al ${DateFormat('dd/MM/yyyy').format(dateRange.end)} (${_reportTypeLabel(_selectedReportType)})',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Divider(),
            ],
          ),
          build: (context) => [
            pw.Table.fromTextArray(
              headers: ['#', 'Estudiante', 'Sexo', 'Presentes', 'Inasistencias (FALTÓ)', 'Tardanzas', 'Justificados', '% Asist.'],
              data: _classroomData.asMap().entries.map((entry) {
                final i = entry.key + 1;
                final s = entry.value;
                return [
                  '$i',
                  s.studentName,
                  s.genderLabel,
                  '${s.presentDays}',
                  '${s.absentDays}',
                  '${s.lateDays}',
                  '${s.justifiedDays}',
                  '${s.attendanceRate.toStringAsFixed(1)}%',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
              border: pw.TableBorder.all(color: PdfColors.grey300),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) => pdf.save(),
        name: 'Reporte_${_selectedClassroom!.displayName.replaceAll(' ', '_')}.pdf',
      );
    }
  },
  message: 'Generando documento PDF oficial...',
);
}

  @override
  Widget build(BuildContext context) {
    final studentProvider = context.watch<StudentProvider>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Reportes de Asistencia'),
        actions: [
          if (_hasGenerated && (_institutionalData.isNotEmpty || _classroomData.isNotEmpty)) ...[
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Descargar CSV',
              onPressed: _isInstitutional ? _exportInstitutionalCsv : _exportClassroomCsv,
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded),
              tooltip: 'Exportar PDF',
              onPressed: _exportPdf,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modalidad: Consolidado General vs Por Salón
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        _isInstitutional = true;
                        _hasGenerated = false;
                      }),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _isInstitutional ? AppTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.school_rounded,
                              size: 18,
                              color: _isInstitutional ? Colors.white : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Consolidado (12 Salones)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _isInstitutional ? Colors.white : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        _isInstitutional = false;
                        _hasGenerated = false;
                      }),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_isInstitutional ? AppTheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.class_rounded,
                              size: 18,
                              color: !_isInstitutional ? Colors.white : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Por Salón',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: !_isInstitutional ? Colors.white : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Tarjeta de Configuración
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Período del Reporte',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),

                  // Frecuencia: Diario, Semanal, Quincenal, Mensual
                  Row(
                    children: [
                      AppConstants.reportDaily,
                      AppConstants.reportWeekly,
                      AppConstants.reportBiweekly,
                      AppConstants.reportMonthly,
                    ].map((type) {
                      final isSelected = _selectedReportType == type;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: InkWell(
                            onTap: () => setState(() {
                              _selectedReportType = type;
                              _hasGenerated = false;
                            }),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primary : AppTheme.surfaceVariant.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _reportTypeLabel(type),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // Si es diario, botón selector de fecha
                  if (_selectedReportType == AppConstants.reportDaily) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _pickDailyDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 18, color: AppTheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Fecha: ${DateFormat('EEEE d MMMM yyyy', 'es').format(_selectedDailyDate)}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Cambiar',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Selector de salón si no es institucional
                  if (!_isInstitutional) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<Classroom>(
                      value: _selectedClassroom,
                      decoration: const InputDecoration(
                        labelText: 'Selecciona el Salón',
                        prefixIcon: Icon(Icons.class_rounded),
                      ),
                      items: studentProvider.classrooms
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c.displayName),
                              ))
                          .toList(),
                      onChanged: (c) => setState(() {
                        _selectedClassroom = c;
                        _hasGenerated = false;
                      }),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Botón Generar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generateReport,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.analytics_rounded),
                      label: Text(_isGenerating
                          ? 'Generando...'
                          : _isInstitutional
                              ? 'Generar Reporte de los 12 Salones'
                              : 'Generar Reporte del Salón'),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms),

            const SizedBox(height: 20),

            // Contenido de los resultados
            if (_hasGenerated) ...[
              // Banner de cálculo y botones de descarga rápida
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Regla de Inasistencia: Solo cuenta "Ausente" como falta del estudiante. Las Tardanzas (llegó tarde) y los Justificados NO se consideran inasistencias.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981), // Verde descarga CSV
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: _isInstitutional ? _exportInstitutionalCsv : _exportClassroomCsv,
                            icon: const Icon(Icons.table_view_rounded, size: 18),
                            label: const Text(
                              'Descargar CSV',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: _exportPdf,
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                            label: const Text('Exportar PDF'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // RENDER DE RESULTADOS
              if (_isInstitutional)
                _buildInstitutionalView()
              else
                _buildClassroomView(),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================
  // VISTA TABLA INSTITUCIONAL (12 SALONES)
  // ==========================================
  Widget _buildInstitutionalView() {
    if (_institutionalData.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: const Center(
          child: Text(
            'No se encontraron registros de salones para este período.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    int totEnrolled = 0;
    int totMale = 0;
    int totFemale = 0;
    int totPresent = 0;
    int totPresentMale = 0;
    int totPresentFemale = 0;
    int totAbsent = 0;
    int totAbsentMale = 0;
    int totAbsentFemale = 0;
    int totLate = 0;
    int totJustified = 0;

    for (final s in _institutionalData) {
      totEnrolled += s.totalEnrolled;
      totMale += s.maleEnrolled;
      totFemale += s.femaleEnrolled;
      totPresent += s.presentDays;
      totPresentMale += s.presentMaleDays;
      totPresentFemale += s.presentFemaleDays;
      totAbsent += s.absentDays;
      totAbsentMale += s.absentMaleDays;
      totAbsentFemale += s.absentFemaleDays;
      totLate += s.lateDays;
      totJustified += s.justifiedDays;
    }

    final totalRecords = totPresent + totAbsent + totLate + totJustified;
    final totalAbsRate = totalRecords > 0 ? (totAbsent / totalRecords * 100) : 0.0;
    final totalAttRate = totalRecords > 0 ? ((totPresent + totLate) / totalRecords * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Encabezado de Fecha / Período del Reporte
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primary,
                AppTheme.primary.withOpacity(0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getHeaderDateTitle(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Text(
                      'Reporte General de Asistencia Consolidada (12 Salones)',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_institutionalData.length} Salones',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Opción: Visualizar nombres de estudiantes inasistentes (Checkbox interactivo)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _showAbsentStudentNames
                  ? AppTheme.primary
                  : Theme.of(context).dividerColor,
              width: _showAbsentStudentNames ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: _showAbsentStudentNames,
                activeColor: AppTheme.primary,
                onChanged: (val) {
                  setState(() {
                    _showAbsentStudentNames = val ?? false;
                  });
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _showAbsentStudentNames = !_showAbsentStudentNames;
                    });
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Visualizar nombres de estudiantes inasistentes',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _showAbsentStudentNames
                            ? 'Activado: muestra los nombres de los estudiantes ausentes por cada salón'
                            : 'Desactivado: muestra únicamente el contador numérico de inasistencias',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              Icon(
                _showAbsentStudentNames ? Icons.visibility_rounded : Icons.visibility_off_outlined,
                color: _showAbsentStudentNames ? AppTheme.primary : AppTheme.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Tarjetas Resumen Institucional
        Row(
          children: [
            _KpiCard(
              title: 'Matrícula Total',
              value: '$totEnrolled',
              subtitle: 'V: $totMale • H: $totFemale',
              color: AppTheme.primary,
              icon: Icons.groups_rounded,
            ),
            const SizedBox(width: 10),
            _KpiCard(
              title: 'Inasistencias',
              value: '$totAbsent',
              subtitle: 'Faltó (V: $totAbsentMale, H: $totAbsentFemale)',
              color: const Color(0xFFEF4444),
              icon: Icons.cancel_outlined,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _KpiCard(
              title: 'Presentes',
              value: '$totPresent',
              subtitle: 'Asistió (V: $totPresentMale, H: $totPresentFemale)',
              color: AppTheme.present,
              icon: Icons.check_circle_outline_rounded,
            ),
            const SizedBox(width: 8),
            _KpiCard(
              title: 'Tardanzas',
              value: '$totLate',
              subtitle: 'Llegó tarde (No faltó)',
              color: AppTheme.late,
              icon: Icons.watch_later_outlined,
            ),
            const SizedBox(width: 8),
            _KpiCard(
              title: 'Justificados',
              value: '$totJustified',
              subtitle: 'Con justificativo',
              color: AppTheme.justified,
              icon: Icons.assignment_outlined,
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Encabezado de la tabla
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Tabla de los 12 Salones',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              '${_institutionalData.length} salones',
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Tabla con Scroll Horizontal
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  AppTheme.primary.withOpacity(0.08),
                ),
                columnSpacing: 18,
                columns: [
                  const DataColumn(label: Text('Salón', style: TextStyle(fontWeight: FontWeight.w800))),
                  const DataColumn(label: Text('Profesor Titular', style: TextStyle(fontWeight: FontWeight.w800))),
                  const DataColumn(label: Text('Matrícula', style: TextStyle(fontWeight: FontWeight.w800))),
                  const DataColumn(label: Text('V / H', style: TextStyle(fontWeight: FontWeight.w800))),
                  const DataColumn(label: Text('Presentes', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.present))),
                  const DataColumn(label: Text('Asist. V/H', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2563EB)))),
                  const DataColumn(
                    label: Text(
                      'Inasistencias (FALTÓ)',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFEF4444)),
                    ),
                  ),
                  const DataColumn(label: Text('Falta V/H', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFDC2626)))),
                  const DataColumn(label: Text('Tardanzas', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.late))),
                  const DataColumn(label: Text('Justificados', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.justified))),
                  const DataColumn(label: Text('% Inasist.', style: TextStyle(fontWeight: FontWeight.w800))),
                  const DataColumn(label: Text('% Asist.', style: TextStyle(fontWeight: FontWeight.w800))),
                  if (_showAbsentStudentNames)
                    const DataColumn(
                      label: Text(
                        'Estudiantes Inasistentes',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFEF4444)),
                      ),
                    ),
                ],
                rows: [
                  ..._institutionalData.map((s) {
                    return DataRow(
                      cells: [
                        DataCell(Text(s.displayName, style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text(s.teacherName ?? 'Sin asignar', style: const TextStyle(fontSize: 12))),
                        DataCell(Text('${s.totalEnrolled}')),
                        DataCell(Text('${s.maleEnrolled} / ${s.femaleEnrolled}')),
                        DataCell(Text('${s.presentDays}', style: const TextStyle(color: AppTheme.present, fontWeight: FontWeight.w700))),
                        DataCell(
                          Text(
                            '${s.presentMaleDays}V / ${s.presentFemaleDays}H',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: s.absentDays > 0 ? const Color(0xFFEF4444).withOpacity(0.12) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${s.absentDays}',
                              style: TextStyle(
                                color: s.absentDays > 0 ? const Color(0xFFEF4444) : null,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${s.absentMaleDays}V / ${s.absentFemaleDays}H',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: s.absentDays > 0 ? const Color(0xFFDC2626) : null,
                            ),
                          ),
                        ),
                        DataCell(Text('${s.lateDays}', style: const TextStyle(color: AppTheme.late))),
                        DataCell(Text('${s.justifiedDays}', style: const TextStyle(color: AppTheme.justified))),
                        DataCell(Text('${s.absenceRate.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text('${s.attendanceRate.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (_showAbsentStudentNames)
                          DataCell(
                            s.absentStudents.isEmpty
                                ? const Text(
                                    'Todos asistieron ✓',
                                    style: TextStyle(color: AppTheme.present, fontSize: 11, fontWeight: FontWeight.w600),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      ...s.absentStudents.take(3).map((st) {
                                        return Container(
                                          margin: const EdgeInsets.only(right: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: st.isMale
                                                ? const Color(0xFF3B82F6).withOpacity(0.15)
                                                : const Color(0xFFEC4899).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${st.studentName} (${st.genderBadge})',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: st.isMale ? const Color(0xFF1D4ED8) : const Color(0xFFBE185D),
                                            ),
                                          ),
                                        );
                                      }),
                                      if (s.absentStudents.length > 3)
                                        Text(
                                          '+${s.absentStudents.length - 3} más',
                                          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                        ),
                                    ],
                                  ),
                          ),
                      ],
                    );
                  }),
                  // Fila de TOTAL INSTITUCIONAL
                  DataRow(
                    color: WidgetStateProperty.all(AppTheme.primary.withOpacity(0.15)),
                    cells: [
                      const DataCell(Text('TOTAL INSTITUCIÓN', style: TextStyle(fontWeight: FontWeight.w900))),
                      const DataCell(Text('--')),
                      DataCell(Text('$totEnrolled', style: const TextStyle(fontWeight: FontWeight.w900))),
                      DataCell(Text('$totMale / $totFemale', style: const TextStyle(fontWeight: FontWeight.w900))),
                      DataCell(Text('$totPresent', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.present))),
                      DataCell(Text('${totPresentMale}V / ${totPresentFemale}H', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2563EB)))),
                      DataCell(
                        Text(
                          '$totAbsent',
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFEF4444)),
                        ),
                      ),
                      DataCell(Text('${totAbsentMale}V / ${totAbsentFemale}H', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFDC2626)))),
                      DataCell(Text('$totLate', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.late))),
                      DataCell(Text('$totJustified', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.justified))),
                      DataCell(
                        Text(
                          '${totalAbsRate.toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${totalAttRate.toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (_showAbsentStudentNames)
                        const DataCell(Text('--')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // SECCIÓN EXPANDIDA: Desglose completo de Estudiantes Inasistentes por Salón
        if (_showAbsentStudentNames) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(Icons.people_outline_rounded, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Detalle de Estudiantes Inasistentes por Salón',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$totAbsent inasistencias en total',
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._institutionalData.map((s) {
            if (s.absentStudents.isEmpty) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    Text(
                      s.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      s.teacherName != null ? '(${s.teacherName})' : '(Sin asignar)',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const Spacer(),
                    const Icon(Icons.check_circle_rounded, color: AppTheme.present, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      '100% Asistencia (0 inasistencias)',
                      style: TextStyle(color: AppTheme.present, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          s.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.teacherName != null ? 'Prof. ${s.teacherName}' : 'Sin asignar',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      const Spacer(),
                      Text(
                        '${s.absentDays} inasistente(s) (${s.absentMaleDays}V / ${s.absentFemaleDays}H)',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: s.absentStudents.map((st) {
                      final isM = st.isMale;
                      final chipBg = isM ? const Color(0xFF3B82F6).withOpacity(0.12) : const Color(0xFFEC4899).withOpacity(0.12);
                      final chipColor = isM ? const Color(0xFF1D4ED8) : const Color(0xFFBE185D);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: chipColor.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isM ? Icons.boy_rounded : Icons.girl_rounded,
                              size: 16,
                              color: chipColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              st.studentName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: chipColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: chipColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                st.genderBadge,
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (st.cedula.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(${st.cedula})',
                                style: TextStyle(fontSize: 10, color: chipColor.withOpacity(0.8)),
                              ),
                            ],
                            if (st.count > 1) ...[
                              const SizedBox(width: 4),
                              Text(
                                '• ${st.count} faltas',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: chipColor),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  // ==========================================
  // VISTA POR SALÓN ESPECÍFICO
  // ==========================================
  Widget _buildClassroomView() {
    if (_classroomData.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: const Center(
          child: Text(
            'No hay datos de asistencia para este salón en este período.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    final totalStudents = _classroomData.length;
    final totalMales = _classroomData.where((s) => s.isMale).length;
    final totalFemales = _classroomData.where((s) => s.isFemale).length;
    final totalAbsents = _classroomData.fold<int>(0, (prev, s) => prev + s.absentDays);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header de datos del salón
        Row(
          children: [
            _KpiCard(
              title: _selectedClassroom?.displayName ?? 'Salón',
              value: '$totalStudents alumnos',
              subtitle: 'Varones: $totalMales • Hembras: $totalFemales',
              color: AppTheme.primary,
              icon: Icons.class_rounded,
            ),
            const SizedBox(width: 10),
            _KpiCard(
              title: 'Total Inasistencias',
              value: '$totalAbsents',
              subtitle: 'Faltas acumuladas en el período',
              color: const Color(0xFFEF4444),
              icon: Icons.person_off_rounded,
            ),
          ],
        ),

        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Estudiantes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              '$totalStudents alumnos evaluados',
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),

        const SizedBox(height: 12),

        ..._classroomData.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReportStudentCard(
                  summary: entry.value,
                  index: entry.key,
                ),
              ),
            ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportStudentCard extends StatelessWidget {
  final AttendanceSummary summary;
  final int index;

  const _ReportStudentCard({required this.summary, required this.index});

  @override
  Widget build(BuildContext context) {
    final rate = summary.attendanceRate;
    final rateColor = rate >= 80
        ? AppTheme.success
        : rate >= 60
            ? AppTheme.warning
            : AppTheme.error;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: summary.absentDays > 0
              ? const Color(0xFFEF4444).withOpacity(0.3)
              : Theme.of(context).dividerColor,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: (summary.isFemale ? const Color(0xFFE91E63) : AppTheme.primary).withOpacity(0.12),
                child: Text(
                  summary.studentName.isNotEmpty ? summary.studentName[0] : '?',
                  style: TextStyle(
                    color: summary.isFemale ? const Color(0xFFE91E63) : AppTheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.studentName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Row(
                      children: [
                        if (summary.cedula.isNotEmpty)
                          Text(
                            'C.I: ${summary.cedula} • ',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: (summary.isFemale ? const Color(0xFFE91E63) : const Color(0xFF1E88E5)).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            summary.genderLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: summary.isFemale ? const Color(0xFFE91E63) : const Color(0xFF1E88E5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: rateColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${rate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: rateColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniStat(label: 'Presentes', value: summary.presentDays, color: AppTheme.present),
              _MiniStat(label: 'Inasistencias', value: summary.absentDays, color: const Color(0xFFEF4444), isHighlighted: true),
              _MiniStat(label: 'Tardanzas', value: summary.lateDays, color: AppTheme.late),
              _MiniStat(label: 'Justificados', value: summary.justifiedDays, color: AppTheme.justified),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate / 100,
              backgroundColor: AppTheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(rateColor),
              minHeight: 6,
            ),
          ),
        ],
      ),
    ).animate(delay: Duration(milliseconds: 40 * index)).fadeIn().slideY(begin: 0.05);
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool isHighlighted;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: isHighlighted ? const EdgeInsets.symmetric(vertical: 4) : EdgeInsets.zero,
        decoration: isHighlighted && value > 0
            ? BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500,
                color: isHighlighted ? color : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
