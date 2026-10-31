import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:contro_asistencias/core/constants/app_constants.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/utils/justification_helper.dart';
import 'package:contro_asistencias/data/models/attendance_record.dart';
import 'package:contro_asistencias/data/models/classroom.dart';
import 'package:contro_asistencias/data/models/student.dart';
import 'package:contro_asistencias/providers/attendance_provider.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/providers/student_provider.dart';

class JustificationsScreen extends StatefulWidget {
  const JustificationsScreen({super.key});

  @override
  State<JustificationsScreen> createState() => _JustificationsScreenState();
}

class _JustificationsScreenState extends State<JustificationsScreen> {
  String? _selectedClassroomId; // null = Todos los salones
  String _dateFilterMode = 'all'; // 'all', '30d', 'single', 'range'
  DateTime _singleDate = DateTime.now();
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  String _searchQuery = '';

  bool _isLoading = true;
  List<Map<String, dynamic>> _rawRecords = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      final studentProvider = context.read<StudentProvider>();
      if (studentProvider.classrooms.isEmpty) {
        if (auth.isTeacher && auth.currentUser?.id != null) {
          await studentProvider.loadClassroomsForTeacher(auth.currentUser!.id);
        } else {
          await studentProvider.loadClassrooms();
        }
      }
      if (auth.isTeacher && studentProvider.classrooms.isNotEmpty) {
        _selectedClassroomId = studentProvider.classrooms.first.id;
      }
      await _loadJustifications();
    });
  }

  DateTime? get _effectiveFromDate {
    final now = DateTime.now();
    final todayNorm = DateTime(now.year, now.month, now.day);
    switch (_dateFilterMode) {
      case 'all':
        return null;
      case 'future':
        return todayNorm.add(const Duration(days: 1));
      case '30d':
        return todayNorm.subtract(const Duration(days: 30));
      case 'single':
        return DateTime(_singleDate.year, _singleDate.month, _singleDate.day);
      case 'range':
        return _dateRange.start;
      default:
        return null;
    }
  }

  DateTime? get _effectiveToDate {
    switch (_dateFilterMode) {
      case 'all':
      case 'future':
      case '30d':
        return null;
      case 'single':
        return DateTime(_singleDate.year, _singleDate.month, _singleDate.day);
      case 'range':
        return _dateRange.end;
      default:
        return null;
    }
  }

  Future<void> _loadJustifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final attendanceProvider = context.read<AttendanceProvider>();
    final records = await attendanceProvider.fetchJustifiedRecords(
      classroomId: _selectedClassroomId,
      startDate: _effectiveFromDate,
      endDate: _effectiveToDate,
    );

    if (!mounted) return;
    setState(() {
      _rawRecords = records;
      _isLoading = false;
    });
  }

  /// Agrupa los registros de justificativos que pertenecen a un mismo estudiante y mismo justificativo
  /// (por ejemplo, cuando faltó 5 días y trajo un solo justificativo para esos 5 días).
  List<_GroupedJustification> _buildGroupedJustifications(List<Classroom> classrooms) {
    final Map<String, _GroupedJustification> groups = {};

    for (final row in _rawRecords) {
      final studentMap = row['students'] as Map<String, dynamic>?;
      if (studentMap == null) continue;

      final studentId = row['student_id']?.toString() ?? '';
      final firstName = studentMap['first_name']?.toString() ?? '';
      final lastName = studentMap['last_name']?.toString() ?? '';
      final fullName = '$firstName $lastName'.trim();

      if (_searchQuery.trim().isNotEmpty &&
          !fullName.toLowerCase().contains(_searchQuery.trim().toLowerCase())) {
        continue;
      }

      final classroomId = row['classroom_id']?.toString() ??
          studentMap['classroom_id']?.toString() ??
          '';
      String grade = studentMap['grade']?.toString() ?? '';
      String section = studentMap['section']?.toString() ?? '';
      if (grade.isEmpty && classroomId.isNotEmpty) {
        final match = classrooms.where((c) => c.id == classroomId).firstOrNull;
        if (match != null) {
          grade = match.grade;
          section = match.section;
        }
      }
      final classroomName =
          grade.isNotEmpty ? '$grade - Sección $section' : 'Salón';

      final dateStr = row['date']?.toString() ?? '';
      final date = DateTime.tryParse(dateStr) ?? DateTime.now();
      final rawNotes = row['notes']?.toString();
      final info = JustificationHelper.parseNotes(rawNotes);

      final covKey = info.coveredDates
          .map((d) => DateFormat('yyyy-MM-dd').format(d))
          .join(',');

      // Clave de agrupación: mismo estudiante + mismo motivo limpio + mismo nombre de adjunto
      final groupKey =
          '$studentId|${info.cleanReason}|${info.attachmentName ?? ''}|$covKey';

      if (groups.containsKey(groupKey)) {
        final existing = groups[groupKey]!;
        if (!existing.dates.any((d) =>
            d.year == date.year && d.month == date.month && d.day == date.day)) {
          existing.dates.add(date);
          existing.dates.sort((a, b) => a.compareTo(b));
        }
      } else {
        final initialDates = <DateTime>[date];
        for (final covDate in info.coveredDates) {
          if (!initialDates.any((d) =>
              d.year == covDate.year &&
              d.month == covDate.month &&
              d.day == covDate.day)) {
            initialDates.add(covDate);
          }
        }
        initialDates.sort((a, b) => a.compareTo(b));

        groups[groupKey] = _GroupedJustification(
          studentId: studentId,
          studentName: fullName,
          classroomId: classroomId,
          classroomName: classroomName,
          grade: grade,
          section: section,
          dates: initialDates,
          rawNotes: rawNotes,
          info: info,
        );
      }
    }

    final list = groups.values.toList();
    // Ordenar por la fecha más reciente descendente
    list.sort((a, b) => b.latestDate.compareTo(a.latestDate));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final studentProvider = context.watch<StudentProvider>();
    final classrooms = studentProvider.classrooms;
    final grouped = _buildGroupedJustifications(classrooms);

    // Agrupar por salón para mostrar secciones claras por aula
    final Map<String, List<_GroupedJustification>> byClassroom = {};
    for (final item in grouped) {
      byClassroom.putIfAbsent(item.classroomName, () => []).add(item);
    }

    final totalJustifications = grouped.length;
    final totalDaysJustified =
        grouped.fold<int>(0, (sum, item) => sum + item.dates.length);
    final withAttachments =
        grouped.where((item) => item.info.hasAttachment).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Justificativos Médicos y Escolares', style: TextStyle(fontSize: 16)),
            Text(
              'Control por salón, fecha y soportes adjuntos',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadJustifications,
            tooltip: 'Actualizar lista',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewJustificationModal(context),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.note_add_rounded),
        label: const Text(
          'Cargar Justificativo',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // Panel de filtros por Salón, Fecha y Búsqueda
          Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Selector de Salón
                    Expanded(
                      flex: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedClassroomId,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                            hint: const Text(
                              'Todos los salones',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            items: [
                              if (!auth.isTeacher)
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(
                                    '🏫 Todos los salones',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ...classrooms.map(
                                (c) => DropdownMenuItem<String?>(
                                  value: c.id,
                                  child: Text(
                                    c.displayName,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: auth.isTeacher
                                ? null
                                : (val) {
                                    setState(() => _selectedClassroomId = val);
                                    _loadJustifications();
                                  },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Buscador por nombre de estudiante
                    Expanded(
                      flex: 5,
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Buscar estudiante...',
                          hintStyle: const TextStyle(fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppTheme.divider),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Filtros de Fecha
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChipButton(
                        label: 'Todos los justificativos',
                        icon: Icons.history_rounded,
                        isSelected: _dateFilterMode == 'all',
                        onTap: () {
                          setState(() => _dateFilterMode = 'all');
                          _loadJustifications();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChipButton(
                        label: 'Próximos / Futuros',
                        icon: Icons.upcoming_rounded,
                        isSelected: _dateFilterMode == 'future',
                        onTap: () {
                          setState(() => _dateFilterMode = 'future');
                          _loadJustifications();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChipButton(
                        label: 'Últimos 30 días',
                        icon: Icons.calendar_month_rounded,
                        isSelected: _dateFilterMode == '30d',
                        onTap: () {
                          setState(() => _dateFilterMode = '30d');
                          _loadJustifications();
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChipButton(
                        label: _dateFilterMode == 'single'
                            ? 'Fecha: ${DateFormat('dd/MM/yyyy').format(_singleDate)}'
                            : 'Por fecha exacta',
                        icon: Icons.today_rounded,
                        isSelected: _dateFilterMode == 'single',
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _singleDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() {
                              _singleDate = picked;
                              _dateFilterMode = 'single';
                            });
                            _loadJustifications();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChipButton(
                        label: _dateFilterMode == 'range'
                            ? '${DateFormat('dd/MM').format(_dateRange.start)} - ${DateFormat('dd/MM').format(_dateRange.end)}'
                            : 'Rango de fechas',
                        icon: Icons.date_range_rounded,
                        isSelected: _dateFilterMode == 'range',
                        onTap: () async {
                          final pickedRange = await showDateRangePicker(
                            context: context,
                            initialDateRange: _dateRange,
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (pickedRange != null) {
                            setState(() {
                              _dateRange = pickedRange;
                              _dateFilterMode = 'range';
                            });
                            _loadJustifications();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Resumen estadístico rápido
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFF1F5F9),
            child: Row(
              children: [
                _MiniStatBadge(
                  icon: Icons.assignment_turned_in_rounded,
                  label: 'Justificativos',
                  value: '$totalJustifications',
                  color: const Color(0xFF1D4ED8),
                ),
                const SizedBox(width: 12),
                _MiniStatBadge(
                  icon: Icons.event_available_rounded,
                  label: 'Días cubiertos',
                  value: '$totalDaysJustified',
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 12),
                _MiniStatBadge(
                  icon: Icons.attach_file_rounded,
                  label: 'Con PDF / Imagen',
                  value: '$withAttachments',
                  color: const Color(0xFF047857),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Contenido principal agrupado por Salón
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : grouped.isEmpty
                    ? _EmptyJustificationsState(
                        onAddTap: () => _showNewJustificationModal(context),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                        itemCount: byClassroom.entries.length,
                        itemBuilder: (context, sectionIndex) {
                          final entry = byClassroom.entries.elementAt(sectionIndex);
                          final classroomTitle = entry.key;
                          final items = entry.value;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Encabezado del Salón
                              Padding(
                                padding: const EdgeInsets.only(top: 6, bottom: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.class_rounded,
                                              size: 14, color: Colors.white),
                                          const SizedBox(width: 6),
                                          Text(
                                            classroomTitle,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${items.length} ${items.length == 1 ? 'registro' : 'registros'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Tarjetas de estudiantes con justificativo en este salón
                              ...items.asMap().entries.map((itemEntry) {
                                final idx = itemEntry.key;
                                final item = itemEntry.value;
                                return _JustificationCard(
                                  item: item,
                                  onViewTap: () {
                                    final canEdit = auth.isAdmin ||
                                        auth.isCoordinator ||
                                        item.dates.every(_isTodayOrFutureDate);
                                    JustificationHelper.showJustificationViewer(
                                      context: context,
                                      studentName: item.studentName,
                                      classroomName: item.classroomName,
                                      date: item.latestDate,
                                      status: AppConstants.statusJustified,
                                      rawNotes: item.rawNotes,
                                      canEdit: canEdit,
                                      onEdit: canEdit
                                          ? () => _showNewJustificationModal(
                                                context,
                                                preselectedClassroomId:
                                                    item.classroomId,
                                                preselectedStudentId:
                                                    item.studentId,
                                                initialDates: item.dates,
                                                initialRawNotes: item.rawNotes,
                                              )
                                          : null,
                                    );
                                  },
                                  onProfileTap: () {
                                    if (item.classroomId.isNotEmpty &&
                                        item.studentId.isNotEmpty) {
                                      context.push(
                                          '/classrooms/${item.classroomId}/students/${item.studentId}');
                                    }
                                  },
                                ).animate(delay: Duration(milliseconds: 40 * idx)).fadeIn();
                              }),
                              const SizedBox(height: 12),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  bool _isTodayOrFutureDate(DateTime d) {
    final now = DateTime.now();
    final todayNorm = DateTime(now.year, now.month, now.day);
    final dNorm = DateTime(d.year, d.month, d.day);
    return !dNorm.isBefore(todayNorm);
  }

  /// Modal para registrar o editar un justificativo para 1 o múltiples fechas (pasadas, hoy o futuras)
  void _showNewJustificationModal(
    BuildContext context, {
    String? preselectedClassroomId,
    String? preselectedStudentId,
    List<DateTime>? initialDates,
    String? initialRawNotes,
  }) async {
    final auth = context.read<AuthProvider>();
    final canEditPastDays = auth.isAdmin || auth.isCoordinator;
    final studentProvider = context.read<StudentProvider>();
    final attendanceProvider = context.read<AttendanceProvider>();
    final classrooms = studentProvider.classrooms;

    String? selectedClassroomId = preselectedClassroomId ??
        _selectedClassroomId ??
        (classrooms.isNotEmpty ? classrooms.first.id : null);

    List<Student> classroomStudents = [];
    String? selectedStudentId = preselectedStudentId;
    List<AttendanceRecord> studentHistory = [];
    bool loadingModalData = true;

    final parsedInitial = JustificationHelper.parseNotes(initialRawNotes);
    final notesCtrl = TextEditingController(text: parsedInitial.cleanReason);
    String? attachedFileName = parsedInitial.attachmentName;
    Uint8List? attachedBytes = parsedInitial.attachmentBytes;

    final now = DateTime.now();
    final todayNorm = DateTime(now.year, now.month, now.day);
    final earliestAllowedDate = canEditPastDays ? DateTime(2024) : todayNorm;
    final latestAllowedDate = todayNorm.add(const Duration(days: 365));

    final List<DateTime> selectedDates = initialDates != null && initialDates.isNotEmpty
        ? initialDates
            .map((d) => DateTime(d.year, d.month, d.day))
            .toList()
        : [todayNorm];

    bool isSaving = false;

    Future<void> loadStudentsForClassroom(
      String cId,
      void Function(void Function()) setModalState,
    ) async {
      setModalState(() => loadingModalData = true);
      await studentProvider.loadStudentsByClassroom(cId);
      classroomStudents = List<Student>.from(studentProvider.students);
      if (selectedStudentId == null ||
          !classroomStudents.any((s) => s.id == selectedStudentId)) {
        selectedStudentId =
            classroomStudents.isNotEmpty ? classroomStudents.first.id : null;
      }
      if (selectedStudentId != null) {
        await attendanceProvider.loadAttendanceHistory(
          classroomId: cId,
          startDate: DateTime.now().subtract(const Duration(days: 180)),
          endDate: DateTime.now().add(const Duration(days: 365)),
          studentId: selectedStudentId,
        );
        studentHistory = List<AttendanceRecord>.from(attendanceProvider.attendanceHistory);
      } else {
        studentHistory = [];
      }
      setModalState(() => loadingModalData = false);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        bool initialized = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (!initialized && selectedClassroomId != null) {
              initialized = true;
              Future.microtask(
                  () => loadStudentsForClassroom(selectedClassroomId!, setModalState));
            }

            // Fechas donde el estudiante seleccionado figura como Ausente
            final absentRecords = studentHistory
                .where((r) => r.status == AppConstants.statusAbsent)
                .toList();

            bool isDateSelected(DateTime d) {
              return selectedDates.any(
                  (s) => s.year == d.year && s.month == d.month && s.day == d.day);
            }

            void toggleDate(DateTime d) {
              final norm = DateTime(d.year, d.month, d.day);
              setModalState(() {
                final idx = selectedDates.indexWhere((s) =>
                    s.year == norm.year &&
                    s.month == norm.month &&
                    s.day == norm.day);
                if (idx >= 0) {
                  if (selectedDates.length > 1) {
                    selectedDates.removeAt(idx);
                  }
                } else {
                  selectedDates.add(norm);
                  selectedDates.sort((a, b) => a.compareTo(b));
                }
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.note_add_rounded,
                              color: Color(0xFF1D4ED8), size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cargar Justificativo',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Justifica días pasados, de hoy o fechas futuras (eventos, viajes, citas)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 1. Selección de Salón
                    const Text(
                      '1. Salón de clases',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedClassroomId,
                          isExpanded: true,
                          items: classrooms
                              .map((Classroom c) => DropdownMenuItem<String>(
                                    value: c.id,
                                    child: Text(c.displayName,
                                        style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600)),
                                  ))
                              .toList(),
                          onChanged: auth.isTeacher
                              ? null
                              : (val) {
                                  if (val != null && val != selectedClassroomId) {
                                    selectedClassroomId = val;
                                    selectedStudentId = null;
                                    loadStudentsForClassroom(val, setModalState);
                                  }
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Selección de Estudiante
                    const Text(
                      '2. Estudiante',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (loadingModalData)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedStudentId,
                            isExpanded: true,
                            hint: const Text('Seleccionar estudiante'),
                            items: classroomStudents
                                .map((Student s) => DropdownMenuItem<String>(
                                      value: s.id,
                                      child: Text(s.fullName,
                                          style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600)),
                                    ))
                                .toList(),
                            onChanged: (val) async {
                              if (val != null &&
                                  val != selectedStudentId &&
                                  selectedClassroomId != null) {
                                setModalState(() {
                                  selectedStudentId = val;
                                  loadingModalData = true;
                                });
                                await attendanceProvider.loadAttendanceHistory(
                                  classroomId: selectedClassroomId!,
                                  startDate: DateTime.now()
                                      .subtract(const Duration(days: 180)),
                                  endDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                  studentId: val,
                                );
                                studentHistory = List<AttendanceRecord>.from(
                                    attendanceProvider.attendanceHistory);
                                setModalState(() => loadingModalData = false);
                              }
                            },
                          ),
                        ),
                      ),

                    const SizedBox(height: 14),

                    // 3. Selección de Fechas a justificar (pasadas, hoy o futuras)
                    Text(
                      '3. Fechas a justificar (${selectedDates.length} ${selectedDates.length == 1 ? 'día' : 'días'})',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Botones rápidos para elegir fecha única (pasada/futura) o un rango de días (pasado/futuro)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDates.last,
                              firstDate: earliestAllowedDate,
                              lastDate: latestAllowedDate,
                              helpText: canEditPastDays
                                  ? 'Selecciona la fecha (pasada, hoy o futura)'
                                  : 'Selecciona la fecha (hoy o futura)',
                            );
                            if (picked != null) {
                              setModalState(() {
                                selectedDates
                                  ..clear()
                                  ..add(DateTime(
                                      picked.year, picked.month, picked.day));
                              });
                            }
                          },
                          icon: const Icon(Icons.event_rounded, size: 15),
                          label: const Text('Elegir 1 fecha (pasada o futura)',
                              style: TextStyle(fontSize: 11.5)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final range = await showDateRangePicker(
                              context: ctx,
                              firstDate: earliestAllowedDate,
                              lastDate: latestAllowedDate,
                              helpText: canEditPastDays
                                  ? 'Selecciona el rango de días (pasados o futuros)'
                                  : 'Selecciona el rango de días (hoy o futuros)',
                              saveText: 'Aplicar rango',
                            );
                            if (range != null) {
                              setModalState(() {
                                selectedDates.clear();
                                DateTime cursor = DateTime(range.start.year,
                                    range.start.month, range.start.day);
                                final end = DateTime(range.end.year,
                                    range.end.month, range.end.day);
                                while (!cursor.isAfter(end)) {
                                  if (cursor.weekday != DateTime.saturday &&
                                      cursor.weekday != DateTime.sunday) {
                                    selectedDates.add(cursor);
                                  }
                                  cursor = cursor.add(const Duration(days: 1));
                                }
                                if (selectedDates.isEmpty) {
                                  selectedDates.add(DateTime(range.start.year,
                                      range.start.month, range.start.day));
                                }
                                selectedDates.sort((a, b) => a.compareTo(b));
                              });
                            }
                          },
                          icon: const Icon(Icons.date_range_rounded, size: 15),
                          label: const Text('Rango de días (ej. varios días)',
                              style: TextStyle(fontSize: 11.5)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Inasistencias detectadas del estudiante para marcar con 1 toque
                    if (canEditPastDays && absentRecords.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppTheme.error.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.cancel_outlined,
                                    size: 14, color: AppTheme.error),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'Inasistencias sin justificar de este estudiante:',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.error,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    setModalState(() {
                                      selectedDates.clear();
                                      for (final r in absentRecords) {
                                        final norm = DateTime(r.date.year,
                                            r.date.month, r.date.day);
                                        if (!isDateSelected(norm)) {
                                          selectedDates.add(norm);
                                        }
                                      }
                                      selectedDates
                                          .sort((a, b) => a.compareTo(b));
                                    });
                                  },
                                  child: const Text('Seleccionar todas',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: absentRecords.take(12).map((r) {
                                final selected = isDateSelected(r.date);
                                return FilterChip(
                                  selected: selected,
                                  label: Text(
                                    DateFormat('dd MMM', 'es_ES').format(r.date),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? Colors.white
                                          : AppTheme.onBackground,
                                    ),
                                  ),
                                  selectedColor: AppTheme.primary,
                                  checkmarkColor: Colors.white,
                                  onSelected: (_) => toggleDate(r.date),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Chips de fechas seleccionadas actualmente
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...selectedDates.map((d) {
                          final isFuture = d.isAfter(todayNorm);
                          return Chip(
                            label: Text(
                              isFuture
                                  ? '${DateFormat('dd/MM/yyyy').format(d)} (Futuro)'
                                  : DateFormat('dd/MM/yyyy').format(d),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: isFuture
                                    ? const Color(0xFF1D4ED8)
                                    : AppTheme.primary,
                              ),
                            ),
                            backgroundColor: isFuture
                                ? const Color(0xFFDBEAFE)
                                : AppTheme.primary.withValues(alpha: 0.1),
                            deleteIcon: selectedDates.length > 1
                                ? const Icon(Icons.close_rounded, size: 15)
                                : null,
                            onDeleted: selectedDates.length > 1
                                ? () => toggleDate(d)
                                : null,
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(Icons.add_rounded,
                              size: 16, color: AppTheme.primary),
                          label: const Text(
                            'Agregar otra fecha',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDates.last,
                              firstDate: earliestAllowedDate,
                              lastDate: latestAllowedDate,
                              helpText: 'Agregar otra fecha al justificativo',
                            );
                            if (picked != null && !isDateSelected(picked)) {
                              toggleDate(picked);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 4. Motivo y Soporte Adjunto (PDF o Imagen)
                    const Text(
                      '4. Motivo y Soporte Adjunto (PDF o Imagen)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText:
                            'Ej: Reposo médico por 5 días tras consulta pediátrica...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                          withData: true,
                        );
                        if (result != null && result.files.isNotEmpty) {
                          final file = result.files.first;
                          if (file.size > 1024 * 1024) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'El archivo supera 1 MB. Selecciona un PDF o imagen más liviana.'),
                                  backgroundColor: AppTheme.error,
                                ),
                              );
                            }
                            return;
                          }
                          setModalState(() {
                            attachedFileName = file.name;
                            attachedBytes = file.bytes;
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: attachedFileName != null
                              ? const Color(0xFFECFDF5)
                              : AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: attachedFileName != null
                                ? const Color(0xFF059669)
                                : AppTheme.divider,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              attachedFileName != null
                                  ? Icons.check_circle_rounded
                                  : Icons.upload_file_rounded,
                              color: attachedFileName != null
                                  ? const Color(0xFF047857)
                                  : AppTheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                attachedFileName ??
                                    'Subir Constancia PDF o Foto (Opcional)',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: attachedFileName != null
                                      ? const Color(0xFF065F46)
                                      : AppTheme.onBackground,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (attachedFileName != null)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => setModalState(() {
                                  attachedFileName = null;
                                  attachedBytes = null;
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ||
                                selectedClassroomId == null ||
                                selectedStudentId == null
                            ? null
                            : () async {
                                setModalState(() => isSaving = true);
                                final encodedNotes =
                                    JustificationHelper.buildNotes(
                                  reason: notesCtrl.text.trim().isEmpty
                                      ? 'Inasistencia justificada'
                                      : notesCtrl.text.trim(),
                                  attachmentName: attachedFileName,
                                  attachmentBytes: attachedBytes,
                                  coveredDates: selectedDates,
                                );

                                final ok = await attendanceProvider
                                    .markMultipleDatesAttendance(
                                  studentId: selectedStudentId!,
                                  classroomId: selectedClassroomId!,
                                  dates: selectedDates,
                                  status: AppConstants.statusJustified,
                                  markedById: auth.currentUser?.id,
                                  notes: encodedNotes,
                                );

                                if (modalCtx.mounted) {
                                  Navigator.pop(modalCtx);
                                }
                                if (mounted) {
                                  await _loadJustifications();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? selectedDates.length > 1
                                                ? 'Justificativo aplicado a ${selectedDates.length} días exitosamente'
                                                : 'Justificativo guardado exitosamente'
                                            : 'Error al guardar justificativo',
                                      ),
                                      backgroundColor: ok
                                          ? const Color(0xFF047857)
                                          : AppTheme.error,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        icon: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          selectedDates.length > 1
                              ? 'Guardar Justificativo en ${selectedDates.length} fechas'
                              : 'Guardar Justificativo',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GroupedJustification {
  final String studentId;
  final String studentName;
  final String classroomId;
  final String classroomName;
  final String grade;
  final String section;
  final List<DateTime> dates;
  final String? rawNotes;
  final JustificationInfo info;

  _GroupedJustification({
    required this.studentId,
    required this.studentName,
    required this.classroomId,
    required this.classroomName,
    required this.grade,
    required this.section,
    required this.dates,
    required this.rawNotes,
    required this.info,
  });

  DateTime get latestDate => dates.isNotEmpty ? dates.last : DateTime.now();
}

class _JustificationCard extends StatelessWidget {
  final _GroupedJustification item;
  final VoidCallback onViewTap;
  final VoidCallback onProfileTap;

  const _JustificationCard({
    required this.item,
    required this.onViewTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMultiDay = item.dates.length > 1;
    final hasFile = item.info.hasAttachment;
    final now = DateTime.now();
    final todayNorm = DateTime(now.year, now.month, now.day);
    final hasFutureDates = item.dates.any(
      (d) => DateTime(d.year, d.month, d.day).isAfter(todayNorm),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(
          color: Color(0xFFCBD5E1),
        ),
      ),
      child: InkWell(
        onTap: onViewTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(
                      Icons.assignment_ind_rounded,
                      color: Color(0xFF1D4ED8),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.studentName,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.onBackground,
                                ),
                              ),
                            ),
                            if (hasFutureDates)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDBEAFE),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFF93C5FD)),
                                ),
                                child: const Text(
                                  'Próximo',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E40AF),
                                  ),
                                ),
                              ),
                            InkWell(
                              onTap: onProfileTap,
                              borderRadius: BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person_search_rounded,
                                        size: 14, color: AppTheme.primary),
                                    SizedBox(width: 3),
                                    Text(
                                      'Perfil',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.info.cleanReason.isNotEmpty
                              ? item.info.cleanReason
                              : 'Inasistencia justificada',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Fechas cubiertas por este justificativo
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isMultiDay
                              ? Icons.date_range_rounded
                              : Icons.event_rounded,
                          size: 14,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isMultiDay
                                ? '${item.dates.length} días cubiertos por este justificativo:'
                                : 'Fecha justificada: ${DateFormat("EEEE d 'de' MMMM yyyy", 'es_ES').format(item.latestDate)}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isMultiDay) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: item.dates.map((d) {
                          final isFuture = DateTime(d.year, d.month, d.day)
                              .isAfter(todayNorm);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isFuture
                                  ? const Color(0xFFEFF6FF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isFuture
                                    ? const Color(0xFF60A5FA)
                                    : AppTheme.primary.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              DateFormat('dd MMM yyyy', 'es_ES').format(d),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isFuture
                                    ? const Color(0xFF1E40AF)
                                    : AppTheme.onBackground,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Barra inferior con estado de adjunto y botón Ver Justificativo
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (hasFile)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF6EE7B7)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item.info.isPdf
                                  ? Icons.picture_as_pdf_rounded
                                  : Icons.image_rounded,
                              size: 14,
                              color: const Color(0xFF047857),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                item.info.attachmentName ?? 'Soporte adjunto',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF065F46),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Expanded(
                      child: Text(
                        'Sin archivo adjunto',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onViewTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.visibility_rounded, size: 15),
                    label: Text(
                      hasFile ? 'Ver Justificativo' : 'Ver Detalle',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.onBackground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniStatBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyJustificationsState extends StatelessWidget {
  final VoidCallback onAddTap;

  const _EmptyJustificationsState({required this.onAddTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_special_rounded,
                size: 44,
                color: Color(0xFF1D4ED8),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No hay justificativos en este filtro',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.onBackground,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Puedes cambiar el filtro de salón o rango de fechas, o cargar un nuevo justificativo para uno o varios días.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onAddTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.note_add_rounded, size: 18),
              label: const Text('Cargar Justificativo'),
            ),
          ],
        ),
      ),
    );
  }
}
