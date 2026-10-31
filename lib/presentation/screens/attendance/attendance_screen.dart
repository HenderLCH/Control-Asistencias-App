import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:contro_asistencias/providers/attendance_provider.dart';
import 'package:contro_asistencias/providers/student_provider.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/utils/justification_helper.dart';
import 'package:contro_asistencias/data/models/student.dart';
import 'package:contro_asistencias/presentation/widgets/common/logo_loading_indicator.dart';
import 'package:contro_asistencias/core/services/notification_service.dart';

class AttendanceScreen extends StatefulWidget {
  final String classroomId;

  const AttendanceScreen({super.key, required this.classroomId});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _hasTriggeredCompletion = false;
  bool _wasAlreadyCompleteOnEntry = false;
  bool _hasMadeChangesInSession = false;
  // Track which specific student is being saved to avoid locking all buttons
  String? _savingStudentId;
  // Sequential mode (student by student) when taking roll call vs List mode when editing
  int _currentStudentIndex = 0;
  bool _isSequentialMode = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final studentProvider = context.read<StudentProvider>();
      final attendanceProvider = context.read<AttendanceProvider>();
      final auth = context.read<AuthProvider>();

      await studentProvider.loadStudentsByClassroom(widget.classroomId);
      if (auth.isTeacher && auth.currentUser != null) {
        studentProvider.loadClassroomsForTeacher(auth.currentUser!.id);
      } else {
        studentProvider.loadClassrooms();
      }
      await attendanceProvider.loadAttendanceForDate(
        classroomId: widget.classroomId,
        date: _selectedDate,
      );

      final students = studentProvider.students;
      final totalStudents = students.length;
      final markedCount = attendanceProvider.todayAttendance.keys.length;
      if (mounted) {
        setState(() {
          if (totalStudents > 0 && markedCount >= totalStudents) {
            _wasAlreadyCompleteOnEntry = true;
            _hasTriggeredCompletion = true;
            _isSequentialMode = false; // Modo edición: mostrar lista completa
          } else {
            _wasAlreadyCompleteOnEntry = false;
            _isSequentialMode = true; // Modo pasar lista: estudiante por estudiante
            _currentStudentIndex = _findFirstUnmarkedIndex(students, attendanceProvider);
          }
        });
      }
    });
  }

  int _findFirstUnmarkedIndex(List<Student> students, AttendanceProvider provider) {
    for (int i = 0; i < students.length; i++) {
      if (!provider.hasMarked(students[i].id)) {
        return i;
      }
    }
    return 0;
  }

  Future<void> _changeDate(DateTime newDate) async {
    final attendanceProv = context.read<AttendanceProvider>();
    final isTargetToday = DateUtils.isSameDay(newDate, DateTime.now());
    setState(() {
      _selectedDate = newDate;
      _hasTriggeredCompletion = false;
      _wasAlreadyCompleteOnEntry = false;
      _hasMadeChangesInSession = false;
    });
    await attendanceProv.loadAttendanceForDate(
      classroomId: widget.classroomId,
      date: newDate,
    );
    if (!mounted) return;
    final students = context.read<StudentProvider>().students;
    final total = students.length;
    final marked = attendanceProv.todayAttendance.keys.length;
    setState(() {
      if (total > 0 && marked >= total) {
        _wasAlreadyCompleteOnEntry = true;
        _hasTriggeredCompletion = true;
        _isSequentialMode = false;
      } else if (!isTargetToday) {
        // En días anteriores se muestra la lista directamente para facilitar la edición y el orden
        _wasAlreadyCompleteOnEntry = marked > 0;
        _isSequentialMode = false;
      } else {
        _wasAlreadyCompleteOnEntry = false;
        _isSequentialMode = true;
        _currentStudentIndex = _findFirstUnmarkedIndex(students, attendanceProv);
      }
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
            secondary: AppTheme.accent,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null && !DateUtils.isSameDay(picked, _selectedDate)) {
      await _changeDate(picked);
    }
  }

  Future<void> _markAll(String status) async {
    final attendanceProvider = context.read<AttendanceProvider>();
    final studentProvider = context.read<StudentProvider>();
    final auth = context.read<AuthProvider>();

    if (status == 'presente') {
      _hasMadeChangesInSession = true;
      await runWithLoading(
        context,
        () async {
          await attendanceProvider.markAllPresent(
            students: studentProvider.students,
            classroomId: widget.classroomId,
            markedById: auth.currentUser?.id,
          );
        },
        message: 'Registrando asistencias...',
      );
      if (mounted) {
        setState(() => _isSequentialMode = false);
      }
      await _checkCompletionAndNotify(
        attendanceProvider: attendanceProvider,
        totalStudents: studentProvider.students.length,
        classroomName: studentProvider.getClassroom(widget.classroomId)?.displayName,
      );
    }
  }

  void _advanceToNextStudent(List<Student> students, AttendanceProvider attendanceProvider) {
    if (!mounted || students.isEmpty) return;
    // Buscar el siguiente estudiante sin marcar después del índice actual
    for (int offset = 1; offset <= students.length; offset++) {
      final candidateIdx = (_currentStudentIndex + offset) % students.length;
      if (!attendanceProvider.hasMarked(students[candidateIdx].id)) {
        setState(() => _currentStudentIndex = candidateIdx);
        return;
      }
    }
    // Si todos están marcados, cambiar al modo lista de edición
    setState(() => _isSequentialMode = false);
  }

  Future<void> _handleStudentStatusChange({
    required Student student,
    required String currentStatus,
    required String newStatus,
    required List<Student> students,
    required AttendanceProvider attendanceProvider,
    required AuthProvider auth,
    required String? classroomName,
    required bool advanceOnMark,
  }) async {
    if (_savingStudentId != null) return;
    setState(() {
      _savingStudentId = student.id;
      _hasMadeChangesInSession = true;
    });
    try {
      if (currentStatus == newStatus && !advanceOnMark) {
        // En modo lista, tocar el estado activo lo desmarca
        await attendanceProvider.removeAttendance(studentId: student.id);
      } else if (newStatus == 'justificado') {
        if (mounted) setState(() => _savingStudentId = null);
        final saved = await _showJustificationDialog(
          context: context,
          student: student,
          attendanceProvider: attendanceProvider,
          markedById: auth.currentUser?.id,
          classroomId: widget.classroomId,
        );
        if (saved && mounted) {
          if (advanceOnMark) {
            _advanceToNextStudent(students, attendanceProvider);
          }
          await _checkCompletionAndNotify(
            attendanceProvider: attendanceProvider,
            totalStudents: students.length,
            classroomName: classroomName,
          );
        }
        return;
      } else {
        await attendanceProvider.markAttendance(
          studentId: student.id,
          classroomId: widget.classroomId,
          status: newStatus,
          markedById: auth.currentUser?.id,
        );
        if (mounted) {
          if (advanceOnMark) {
            _advanceToNextStudent(students, attendanceProvider);
          }
          await _checkCompletionAndNotify(
            attendanceProvider: attendanceProvider,
            totalStudents: students.length,
            classroomName: classroomName,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _savingStudentId = null);
    }
  }

  Future<void> _checkCompletionAndNotify({
    required AttendanceProvider attendanceProvider,
    required int totalStudents,
    required String? classroomName,
  }) async {
    final markedCount = attendanceProvider.todayAttendance.keys.length;
    if (totalStudents > 0 && markedCount >= totalStudents) {
      if (mounted && _isSequentialMode) {
        setState(() => _isSequentialMode = false);
      }
      final name = classroomName ?? 'el salón';
      final auth = context.read<AuthProvider>();
      final teacherName = auth.currentUser?.fullName ?? 'Profesor';
      final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

      if (isToday) {
        attendanceProvider.markClassroomCompleted(name);
      }

      if (!_hasTriggeredCompletion) {
        _hasTriggeredCompletion = true;
        final isMod = _wasAlreadyCompleteOnEntry;

        // Disparar la notificación INMEDIATAMENTE al terminar de pasar la lista
        await attendanceProvider.notifyAttendanceAction(
          classroomName: name,
          teacherName: teacherName,
          isModification: isMod,
        );

        // Si quien pasa la lista es Admin o Coordinador, notificar en su teléfono también
        // (Al profesor NUNCA se le notifica en su dispositivo: "Al profesor no le debe mostrar ninguna notificación de esas")
        if (auth.isAdmin || auth.isCoordinator) {
          if (isMod) {
            NotificationService().showAttendanceModifiedNotification(
              classroomName: name,
              teacherName: teacherName,
            );
          } else {
            NotificationService().showAttendanceCompletedNotification(
              classroomName: name,
              teacherName: teacherName,
            );
          }
        }

        if (mounted && !_wasAlreadyCompleteOnEntry) {
          await _showCompletionDialog(totalStudents, name, auth);
        }
      } else if (_wasAlreadyCompleteOnEntry && _hasMadeChangesInSession) {
        // En caso de sufrir modificaciones después, notificar de inmediato
        await attendanceProvider.notifyAttendanceAction(
          classroomName: name,
          teacherName: teacherName,
          isModification: true,
        );

        if (auth.isAdmin || auth.isCoordinator) {
          NotificationService().showAttendanceModifiedNotification(
            classroomName: name,
            teacherName: teacherName,
          );
        }
      }
    }
  }

  Future<void> _showCompletionDialog(int totalStudents, String name, AuthProvider auth) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF162032) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '¡Asistencia Finalizada!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Has registrado con éxito la asistencia de los $totalStudents alumnos de $name.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.home_rounded, size: 20),
                    label: const Text(
                      'Salir al Inicio',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.of(dialogCtx).pop();
                      if (mounted) {
                        _navigateBack(context, auth);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    if (mounted) {
                      setState(() => _isSequentialMode = false);
                    }
                  },
                  child: const Text('Quedarme a revisar / Editar lista'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleExit({
    required BuildContext context,
    required bool isComplete,
    required bool canMark,
    required bool isToday,
    required int unmarkedCount,
    required int totalStudents,
    required AuthProvider auth,
  }) async {
    // Si la lista ya está completa al 100%, o no es fecha de hoy, salir directamente
    if (!canMark || !isToday || isComplete || totalStudents == 0) {
      _navigateBack(context, auth);
      return;
    }

    // Modal de comprobación cuando la asistencia no se ha terminado
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF162032) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Asistencia incompleta',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            'Aún no has terminado de pasar la asistencia en este salón.\n\n'
            'Faltan $unmarkedCount estudiante${unmarkedCount == 1 ? '' : 's'} por registrar.\n\n'
            '¿Seguro que deseas salir?',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'Continuar pasando lista',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Salir de todas formas'),
            ),
          ],
        );
      },
    );

    if (shouldExit == true && context.mounted) {
      _navigateBack(context, auth);
    }
  }

  void _navigateBack(BuildContext context, AuthProvider auth) {
    if (auth.isTeacher) {
      context.go('/dashboard');
    } else {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/classrooms');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final attendanceProvider = context.watch<AttendanceProvider>();
    final studentProvider = context.watch<StudentProvider>();
    final auth = context.watch<AuthProvider>();
    final classroom = studentProvider.getClassroom(widget.classroomId);
    final students = studentProvider.students;

    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    // Los días anteriores SOLO los pueden editar coordinadores y administrador
    final canMark = isToday || auth.isAdmin || auth.isCoordinator;
    final totalStudents = students.length;
    final markedStudents = attendanceProvider.todayAttendance.keys.length;
    final isComplete = totalStudents > 0 && markedStudents >= totalStudents;
    final unmarkedCount = totalStudents - markedStudents;
    final isAttendanceIncomplete = canMark && isToday && !isComplete && totalStudents > 0;
    final showSequentialRollCall = _isSequentialMode && canMark && !isComplete && students.isNotEmpty;

    return PopScope(
      canPop: !isAttendanceIncomplete,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleExit(
          context: context,
          isComplete: isComplete,
          canMark: canMark,
          isToday: isToday,
          unmarkedCount: unmarkedCount,
          totalStudents: totalStudents,
          auth: auth,
        );
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _handleExit(
              context: context,
              isComplete: isComplete,
              canMark: canMark,
              isToday: isToday,
              unmarkedCount: unmarkedCount,
              totalStudents: totalStudents,
              auth: auth,
            ),
          ),
          title: Text(
            classroom != null
                ? (!canMark
                    ? 'Asistencia - ${classroom.displayName}'
                    : (!showSequentialRollCall && (isComplete || !isToday)
                        ? 'Editar Asistencia - ${classroom.displayName}'
                        : 'Pasar Lista - ${classroom.displayName}'))
                : 'Asistencia',
          ),
          actions: [
            if (canMark && !isToday && !isComplete && students.isNotEmpty)
              IconButton(
                tooltip: _isSequentialMode ? 'Ver lista completa' : 'Pasar uno por uno',
                icon: Icon(_isSequentialMode ? Icons.format_list_bulleted_rounded : Icons.person_pin_rounded),
                onPressed: () {
                  setState(() {
                    _isSequentialMode = !_isSequentialMode;
                    if (_isSequentialMode) {
                      _currentStudentIndex = _findFirstUnmarkedIndex(students, attendanceProvider);
                    }
                  });
                },
              ),
            if (canMark)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) => _markAll(value),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'presente',
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppTheme.present, size: 20),
                        SizedBox(width: 10),
                        Text('Marcar todos presentes'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: Column(
          children: [
            // Date selector con navegación rápida de días anteriores
            Container(
              color: Theme.of(context).cardColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Día anterior',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left_rounded, color: AppTheme.primary),
                    onPressed: () {
                      final prevDay = _selectedDate.subtract(const Duration(days: 1));
                      if (!prevDay.isBefore(DateTime(2024))) {
                        _changeDate(prevDay);
                      }
                    },
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: isToday
                              ? AppTheme.primary.withOpacity(0.08)
                              : const Color(0xFF0284C7).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isToday
                                ? AppTheme.primary.withOpacity(0.25)
                                : const Color(0xFF0284C7).withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isToday ? Icons.calendar_today_rounded : Icons.history_edu_rounded,
                              size: 17,
                              color: isToday ? AppTheme.primary : const Color(0xFF0284C7),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                DateFormat('EEE, d MMM yyyy', 'es').format(_selectedDate),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isToday ? AppTheme.primary : const Color(0xFF0284C7),
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 20,
                              color: isToday ? AppTheme.primary : const Color(0xFF0284C7),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Día siguiente',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.chevron_right_rounded,
                      color: isToday ? AppTheme.textSecondary.withOpacity(0.35) : AppTheme.primary,
                    ),
                    onPressed: isToday
                        ? null
                        : () {
                            final nextDay = _selectedDate.add(const Duration(days: 1));
                            if (!nextDay.isAfter(DateTime.now())) {
                              _changeDate(nextDay);
                            }
                          },
                  ),
                  if (!isToday)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: TextButton.icon(
                        onPressed: () => _changeDate(DateTime.now()),
                        icon: const Icon(Icons.today_rounded, size: 15),
                        label: const Text('Hoy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          backgroundColor: AppTheme.primary.withOpacity(0.1),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Banner de Solo lectura cuando un Profesor consulta un día anterior
            if (!canMark)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_clock_rounded, color: AppTheme.warning, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Solo lectura: Los días anteriores solo pueden ser editados por Coordinadores o Administrador.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Banner de progreso o completado
            if (students.isNotEmpty && canMark)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isComplete
                      ? const Color(0xFF10B981).withOpacity(0.12)
                      : const Color(0xFFF59E0B).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isComplete
                        ? const Color(0xFF10B981).withOpacity(0.4)
                        : const Color(0xFFF59E0B).withOpacity(0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isComplete ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                      color: isComplete ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isComplete
                            ? (isToday
                                ? '✅ Lista de asistencia completada'
                                : '✅ Asistencia registrada (${DateFormat('dd/MM/yyyy').format(_selectedDate)})')
                            : 'Progreso: $markedStudents de $totalStudents registrados (faltan $unmarkedCount por marcar)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isComplete ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Banner explicativo si está en modo edición (lista completa o día anterior para Coord/Admin)
            if (canMark && !showSequentialRollCall && (isComplete || !isToday))
              Container(
                margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_note_rounded, color: Color(0xFF0284C7), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        !isToday
                            ? 'Modo edición de fecha anterior (Coord./Admin): Puedes registrar o corregir la asistencia de cualquier estudiante.'
                            : 'Modo edición: Puedes modificar cualquier alumno de la lista (si llegó tarde o justificó).',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Stats bar
            if (students.isNotEmpty)
              Container(
                color: Theme.of(context).cardColor,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Row(
                  children: [
                    _QuickStat(
                      label: 'Marcados',
                      value: attendanceProvider.markedCount,
                      total: students.length,
                      color: AppTheme.primary,
                    ),
                    _QuickStat(
                      label: 'Presentes',
                      value: attendanceProvider.presentCount,
                      total: students.length,
                      color: AppTheme.present,
                    ),
                    _QuickStat(
                      label: 'Ausentes',
                      value: attendanceProvider.absentCount,
                      total: students.length,
                      color: AppTheme.absent,
                    ),
                    _QuickStat(
                      label: 'Tardanzas',
                      value: attendanceProvider.lateCount,
                      total: students.length,
                      color: AppTheme.late,
                    ),
                  ],
                ),
              ),

            // Contenido principal: Estudiante por estudiante (Pasar lista) vs Lista completa (Editar asistencia)
            Expanded(
              child: attendanceProvider.isLoading || studentProvider.isLoading
                  ? const Center(
                      child: LogoLoadingIndicator(
                        size: 46,
                        message: 'Cargando lista de estudiantes...',
                      ),
                    )
                  : students.isEmpty
                      ? const Center(
                          child: Text('No hay estudiantes en este salón'),
                        )
                      : showSequentialRollCall
                          ? _buildSequentialStudentView(
                              context: context,
                              students: students,
                              attendanceProvider: attendanceProvider,
                              auth: auth,
                              classroomName: classroom?.displayName,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: students.length,
                              itemBuilder: (context, index) {
                                final student = students[index];
                                final status = attendanceProvider.getStatusForStudent(student.id);
                                final notes = attendanceProvider.todayAttendance[student.id]?.notes;
                                final isThisStudentSaving = _savingStudentId == student.id;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _AttendanceTile(
                                    student: student,
                                    currentStatus: status,
                                    notes: notes,
                                    canMark: canMark,
                                    isSaving: isThisStudentSaving,
                                    onTapStudent: () => context.push(
                                      '/classrooms/${widget.classroomId}/students/${student.id}',
                                    ),
                                    onStatusChanged: (newStatus) => _handleStudentStatusChange(
                                      student: student,
                                      currentStatus: status,
                                      newStatus: newStatus,
                                      students: students,
                                      attendanceProvider: attendanceProvider,
                                      auth: auth,
                                      classroomName: classroom?.displayName,
                                      advanceOnMark: false,
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
        bottomNavigationBar: (!showSequentialRollCall && (isComplete || (!isToday && _hasMadeChangesInSession)) && canMark)
            ? SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 6,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                    label: const Text(
                      'Listo — Salir al Inicio',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _navigateBack(context, auth),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  /// Vista secuencial estudiante por estudiante para leer claramente el nombre completo y asignar estado
  Widget _buildSequentialStudentView({
    required BuildContext context,
    required List<Student> students,
    required AttendanceProvider attendanceProvider,
    required AuthProvider auth,
    required String? classroomName,
  }) {
    final safeIndex = _currentStudentIndex.clamp(0, students.length - 1);
    final student = students[safeIndex];
    final currentStatus = attendanceProvider.getStatusForStudent(student.id);
    final isSaving = _savingStudentId == student.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasStatus = currentStatus.isNotEmpty;
    final statusColor = hasStatus ? AppTheme.getAttendanceColor(currentStatus) : AppTheme.primary;
    final genderColor = student.isFemale ? const Color(0xFFE91E63) : const Color(0xFF1E88E5);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            children: [
              // Barra de navegación entre estudiantes (Anterior / Contador / Siguiente)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: safeIndex > 0 && !isSaving
                          ? () => setState(() => _currentStudentIndex = safeIndex - 1)
                          : null,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 15),
                      label: const Text('Anterior', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Estudiante ${safeIndex + 1} de ${students.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: safeIndex < students.length - 1 && !isSaving
                          ? () => setState(() => _currentStudentIndex = safeIndex + 1)
                          : null,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Siguiente', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios_rounded, size: 15),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Tarjeta principal del estudiante actual
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.97, end: 1.0).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  key: ValueKey(student.id),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: hasStatus
                          ? statusColor.withOpacity(0.55)
                          : Theme.of(context).dividerColor,
                      width: hasStatus ? 2 : 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Fila superior: Número de lista y Sexo
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'N° ${safeIndex + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: genderColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  student.isFemale ? Icons.female_rounded : Icons.male_rounded,
                                  size: 15,
                                  color: genderColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  student.isFemale ? 'Hembra (H)' : 'Varón (V)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: genderColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Avatar del estudiante
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: genderColor.withOpacity(0.14),
                        backgroundImage: student.photoUrl != null
                            ? NetworkImage(student.photoUrl!)
                            : null,
                        child: student.photoUrl == null
                            ? Text(
                                student.initials,
                                style: TextStyle(
                                  color: genderColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 26,
                                ),
                              )
                            : null,
                      ),

                      const SizedBox(height: 16),

                      // Nombre completo bien grande y legible
                      Text(
                        student.fullName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: isDark ? Colors.white : AppTheme.onBackground,
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Desglose Nombres / Apellidos y Cédula para lectura inequívoca
                      Text(
                        student.cedula.isNotEmpty
                            ? 'C.I.: ${student.cedula}  •  ${student.displayGrade}'
                            : student.displayGrade,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Indicador de estado actual del alumno
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: hasStatus
                              ? statusColor.withOpacity(0.12)
                              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: hasStatus
                                ? statusColor.withOpacity(0.4)
                                : Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSaving) ...[
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Guardando...',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ] else ...[
                              Icon(
                                hasStatus
                                    ? AppTheme.getAttendanceIcon(currentStatus)
                                    : Icons.radio_button_unchecked_rounded,
                                size: 16,
                                color: hasStatus ? statusColor : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                hasStatus
                                    ? 'Estado: ${_statusLabelText(currentStatus)}'
                                    : 'Pendiente por registrar',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: hasStatus ? statusColor : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        'Selecciona el estado de asistencia:',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Botones grandes de estado (2x2)
                      Row(
                        children: [
                          Expanded(
                            child: _LargeStatusButton(
                              label: 'Presente',
                              icon: Icons.check_circle_rounded,
                              color: AppTheme.present,
                              isActive: currentStatus == 'presente',
                              isDisabled: isSaving,
                              onTap: () => _handleStudentStatusChange(
                                student: student,
                                currentStatus: currentStatus,
                                newStatus: 'presente',
                                students: students,
                                attendanceProvider: attendanceProvider,
                                auth: auth,
                                classroomName: classroomName,
                                advanceOnMark: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _LargeStatusButton(
                              label: 'Ausente',
                              icon: Icons.cancel_rounded,
                              color: AppTheme.absent,
                              isActive: currentStatus == 'ausente',
                              isDisabled: isSaving,
                              onTap: () => _handleStudentStatusChange(
                                student: student,
                                currentStatus: currentStatus,
                                newStatus: 'ausente',
                                students: students,
                                attendanceProvider: attendanceProvider,
                                auth: auth,
                                classroomName: classroomName,
                                advanceOnMark: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _LargeStatusButton(
                              label: 'Tardanza',
                              icon: Icons.access_time_filled_rounded,
                              color: AppTheme.late,
                              isActive: currentStatus == 'tardanza',
                              isDisabled: isSaving,
                              onTap: () => _handleStudentStatusChange(
                                student: student,
                                currentStatus: currentStatus,
                                newStatus: 'tardanza',
                                students: students,
                                attendanceProvider: attendanceProvider,
                                auth: auth,
                                classroomName: classroomName,
                                advanceOnMark: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _LargeStatusButton(
                              label: 'Justificado',
                              icon: Icons.assignment_turned_in_rounded,
                              color: AppTheme.justified,
                              isActive: currentStatus == 'justificado',
                              isDisabled: isSaving,
                              onTap: () => _handleStudentStatusChange(
                                student: student,
                                currentStatus: currentStatus,
                                newStatus: 'justificado',
                                students: students,
                                attendanceProvider: attendanceProvider,
                                auth: auth,
                                classroomName: classroomName,
                                advanceOnMark: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabelText(String status) {
    switch (status) {
      case 'presente':
        return 'Presente';
      case 'ausente':
        return 'Ausente';
      case 'tardanza':
        return 'Tardanza';
      case 'justificado':
        return 'Justificado';
      default:
        return status;
    }
  }

  /// Diálogo modal para justificar inasistencia con razón y comprobante opcional (<= 1MB)
  Future<bool> _showJustificationDialog({
    required BuildContext context,
    required Student student,
    required AttendanceProvider attendanceProvider,
    required String? markedById,
    required String classroomId,
  }) async {
    final auth = context.read<AuthProvider>();
    final canEditPastDays = auth.isAdmin || auth.isCoordinator;
    final existingNotes = attendanceProvider.todayAttendance[student.id]?.notes;
    final parsedExisting = JustificationHelper.parseNotes(existingNotes);
    final reasonCtrl = TextEditingController(text: parsedExisting.cleanReason);
    PlatformFile? attachedFile;
    bool keepExistingAttachment = parsedExisting.hasAttachment;
    String? fileError;
    bool wasSaved = false;

    final now = DateTime.now();
    final todayNorm = DateTime(now.year, now.month, now.day);
    final baseDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final earliestAllowed = canEditPastDays ? DateTime(2024) : todayNorm;
    final latestAllowed = todayNorm.add(const Duration(days: 365));

    final List<DateTime> selectedDates = parsedExisting.coveredDates.isNotEmpty
        ? parsedExisting.coveredDates
            .map((d) => DateTime(d.year, d.month, d.day))
            .toList()
        : [baseDate];

    bool containsDate(DateTime d) =>
        selectedDates.any((s) => DateUtils.isSameDay(s, d));

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final viewInsets = MediaQuery.of(context).viewInsets;

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: viewInsets.bottom > 0 ? 10 : 0),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Encabezado con Icono, Título, Estudiante y Botón de cierre
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.justified.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.assignment_turned_in_rounded, color: AppTheme.justified, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedDates.length > 1
                                      ? 'Justificar ${selectedDates.length} Días'
                                      : 'Justificar Inasistencia',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  student.fullName,
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 22),
                            onPressed: () => Navigator.pop(ctx),
                            tooltip: 'Cerrar',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),

                      // Fechas cubiertas por el justificativo (hoy, pasadas o futuras)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fechas cubiertas (${selectedDates.length} ${selectedDates.length == 1 ? 'día' : 'días'}):',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: selectedDates.map((d) {
                                final isFuture = d.isAfter(todayNorm);
                                return Chip(
                                  label: Text(
                                    isFuture
                                        ? '${DateFormat('EEE d MMM', 'es').format(d)} (Futuro)'
                                        : DateFormat('EEE d MMM', 'es').format(d),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  backgroundColor: isFuture
                                      ? const Color(0xFF1D4ED8)
                                      : AppTheme.primary,
                                  deleteIconColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onDeleted: selectedDates.length > 1 && !DateUtils.isSameDay(d, baseDate)
                                      ? () => setModalState(() {
                                            selectedDates.removeWhere(
                                                (s) => DateUtils.isSameDay(s, d));
                                          })
                                      : null,
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final range = await showDateRangePicker(
                                      context: context,
                                      firstDate: earliestAllowed,
                                      lastDate: latestAllowed,
                                      helpText: 'Selecciona el rango de días (hoy, pasados o futuros)',
                                      saveText: 'Aplicar rango',
                                    );
                                    if (range != null) {
                                      setModalState(() {
                                        DateTime cur = DateTime(range.start.year, range.start.month, range.start.day);
                                        final end = DateTime(range.end.year, range.end.month, range.end.day);
                                        while (!cur.isAfter(end)) {
                                          if (cur.weekday != DateTime.saturday && cur.weekday != DateTime.sunday) {
                                            if (!containsDate(cur)) {
                                              selectedDates.add(cur);
                                            }
                                          }
                                          cur = cur.add(const Duration(days: 1));
                                        }
                                        if (!containsDate(baseDate)) {
                                          selectedDates.add(baseDate);
                                        }
                                        selectedDates.sort((a, b) => a.compareTo(b));
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.date_range_rounded, size: 15),
                                  label: const Text('Incluir días futuros / rango', style: TextStyle(fontSize: 11.5)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final extra = await showDatePicker(
                                      context: context,
                                      initialDate: selectedDates.last,
                                      firstDate: earliestAllowed,
                                      lastDate: latestAllowed,
                                      helpText: 'Agregar fecha futura o adicional',
                                    );
                                    if (extra != null) {
                                      setModalState(() {
                                        final norm = DateTime(extra.year, extra.month, extra.day);
                                        if (!containsDate(norm)) {
                                          selectedDates.add(norm);
                                          selectedDates.sort((a, b) => a.compareTo(b));
                                        }
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
                                  label: const Text('Agregar fecha', style: TextStyle(fontSize: 11.5)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Campo de texto de la razón
                      const Text(
                        'Coloque la razón de la falta:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: reasonCtrl,
                        minLines: 2,
                        maxLines: 4,
                        scrollPadding: const EdgeInsets.all(24),
                        decoration: InputDecoration(
                          hintText: 'Ej. Reposo médico, evento deportivo en próximos días, permiso familiar...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Adjuntar comprobante
                      const Text(
                        'Comprobante adjunto (Opcional - máx. 1 MB):',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          try {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                              withData: true,
                            );
                            if (result != null && result.files.isNotEmpty) {
                              final file = result.files.first;
                              if (file.size > 1024 * 1024) {
                                setModalState(() {
                                  fileError = 'El archivo supera el límite de 1 MB (${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB)';
                                  attachedFile = null;
                                });
                              } else {
                                setModalState(() {
                                  attachedFile = file;
                                  keepExistingAttachment = false;
                                  fileError = null;
                                });
                              }
                            }
                          } catch (e) {
                            setModalState(() {
                              fileError = 'Error al seleccionar archivo: $e';
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: fileError != null
                                  ? Colors.red
                                  : ((attachedFile != null || keepExistingAttachment)
                                      ? AppTheme.justified
                                      : Theme.of(context).dividerColor),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                attachedFile != null
                                    ? (attachedFile!.extension?.toLowerCase() == 'pdf'
                                        ? Icons.picture_as_pdf_rounded
                                        : Icons.image_rounded)
                                    : (keepExistingAttachment
                                        ? (parsedExisting.isPdf
                                            ? Icons.picture_as_pdf_rounded
                                            : Icons.image_rounded)
                                        : Icons.attach_file_rounded),
                                color: (attachedFile != null || keepExistingAttachment)
                                    ? AppTheme.justified
                                    : AppTheme.textSecondary,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  attachedFile != null
                                      ? '${attachedFile!.name} (${(attachedFile!.size / 1024).toStringAsFixed(0)} KB)'
                                      : (keepExistingAttachment
                                          ? 'Adjunto actual: ${parsedExisting.attachmentName}'
                                          : 'Seleccionar foto o PDF (máx. 1MB)'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: (attachedFile != null || keepExistingAttachment)
                                        ? (isDark ? Colors.white : Colors.black87)
                                        : AppTheme.textSecondary,
                                    fontWeight: (attachedFile != null || keepExistingAttachment)
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (attachedFile != null || keepExistingAttachment)
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () => setModalState(() {
                                    attachedFile = null;
                                    keepExistingAttachment = false;
                                  }),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (fileError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(
                            fileError!,
                            style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w500),
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Botones de acción siempre visibles y dentro del scroll
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.check_rounded, size: 18),
                            onPressed: () async {
                              final reason = reasonCtrl.text.trim();
                              if (reason.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Por favor coloca la razón de la falta'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }
                              wasSaved = true;
                              Navigator.pop(ctx);
                              final fullNote = JustificationHelper.buildNotes(
                                reason: reason,
                                attachmentName: attachedFile != null
                                    ? attachedFile!.name
                                    : (keepExistingAttachment ? parsedExisting.attachmentName : null),
                                attachmentBytes: attachedFile != null
                                    ? attachedFile!.bytes
                                    : (keepExistingAttachment ? parsedExisting.attachmentBytes : null),
                                coveredDates: selectedDates,
                              );
                              await attendanceProvider.markMultipleDatesAttendance(
                                studentId: student.id,
                                classroomId: classroomId,
                                status: 'justificado',
                                dates: selectedDates,
                                notes: fullNote,
                                markedById: markedById,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.justified,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            label: Text(
                              selectedDates.length > 1
                                  ? 'Guardar en ${selectedDates.length} Días'
                                  : 'Guardar Justificación',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    return wasSaved;
  }
}

class _QuickStat extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;

  const _QuickStat({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _AttendanceTile extends StatelessWidget {
  final Student student;
  final String currentStatus;
  final String? notes;
  final bool canMark;
  final bool isSaving; // true only when THIS student is being saved
  final VoidCallback? onTapStudent;
  final Function(String) onStatusChanged;

  const _AttendanceTile({
    required this.student,
    required this.currentStatus,
    this.notes,
    required this.canMark,
    required this.isSaving,
    this.onTapStudent,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasStatus = currentStatus.isNotEmpty;
    final statusColor = hasStatus
        ? AppTheme.getAttendanceColor(currentStatus)
        : AppTheme.textSecondary;
    final justInfo = JustificationHelper.parseNotes(notes);
    final hasCleanNotes = justInfo.cleanReason.isNotEmpty || justInfo.hasAttachment;

    return Container(
      decoration: BoxDecoration(
        color: hasStatus
            ? AppTheme.getAttendanceColor(currentStatus).withOpacity(0.08)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasStatus
              ? AppTheme.getAttendanceColor(currentStatus).withOpacity(0.3)
              : Theme.of(context).dividerColor,
          width: hasStatus ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTapStudent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.primary.withOpacity(0.1),
              backgroundImage: student.photoUrl != null
                  ? NetworkImage(student.photoUrl!)
                  : null,
              child: student.photoUrl == null
                  ? Text(
                      student.initials,
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
            if (hasStatus)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          student.fullName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            hasStatus
                ? Text(
                    _statusLabel(currentStatus),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
                  )
                : const Text(
                    'Sin marcar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
            if (hasCleanNotes)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: InkWell(
                  onTap: () {
                    JustificationHelper.showJustificationViewer(
                      context: context,
                      studentName: student.fullName,
                      classroomName: student.displayGrade,
                      date: context.read<AttendanceProvider>().selectedDate,
                      status: currentStatus,
                      rawNotes: notes,
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        justInfo.hasAttachment
                            ? (justInfo.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded)
                            : Icons.notes_rounded,
                        size: 13,
                        color: AppTheme.justified,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          justInfo.hasAttachment
                              ? '${justInfo.cleanReason} (Ver ${justInfo.attachmentName})'
                              : justInfo.cleanReason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.justified,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        trailing: canMark
            ? _StatusButtonRow(
                currentStatus: currentStatus,
                onStatusChanged: onStatusChanged,
                isSaving: isSaving,
              )
            : hasStatus
                ? Icon(AppTheme.getAttendanceIcon(currentStatus), color: statusColor)
                : const Icon(Icons.remove_rounded, color: AppTheme.textSecondary),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'presente': return '✓ Presente';
      case 'ausente': return '✗ Ausente';
      case 'tardanza': return '⏰ Tardanza';
      case 'justificado': return '📋 Justificado';
      default: return status;
    }
  }
}

class _StatusButtonRow extends StatelessWidget {
  final String currentStatus;
  final Function(String) onStatusChanged;
  final bool isSaving;

  const _StatusButtonRow({
    required this.currentStatus,
    required this.onStatusChanged,
    required this.isSaving,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBtn(
          icon: Icons.check_rounded,
          color: AppTheme.present,
          isActive: currentStatus == 'presente',
          tooltip: 'Presente',
          onTap: isSaving ? null : () => onStatusChanged('presente'),
        ),
        const SizedBox(width: 4),
        _StatusBtn(
          icon: Icons.close_rounded,
          color: AppTheme.absent,
          isActive: currentStatus == 'ausente',
          tooltip: 'Ausente',
          onTap: isSaving ? null : () => onStatusChanged('ausente'),
        ),
        const SizedBox(width: 4),
        _StatusBtn(
          icon: Icons.access_time_rounded,
          color: AppTheme.late,
          isActive: currentStatus == 'tardanza',
          tooltip: 'Tardanza',
          onTap: isSaving ? null : () => onStatusChanged('tardanza'),
        ),
        const SizedBox(width: 4),
        _StatusBtn(
          icon: Icons.assignment_turned_in_rounded,
          color: AppTheme.justified,
          isActive: currentStatus == 'justificado',
          tooltip: 'Justificado',
          onTap: isSaving ? null : () => onStatusChanged('justificado'),
        ),
      ],
    );
  }
}

class _StatusBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isActive;
  final String tooltip;
  final VoidCallback? onTap;

  const _StatusBtn({
    required this.icon,
    required this.color,
    required this.isActive,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isActive ? color : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: isActive ? Colors.white : color,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _LargeStatusButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isActive;
  final bool isDisabled;
  final VoidCallback onTap;

  const _LargeStatusButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isActive,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: isActive ? color : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? color : color.withOpacity(0.35),
              width: isActive ? 2 : 1.2,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive ? Colors.white : color,
                size: 22,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

