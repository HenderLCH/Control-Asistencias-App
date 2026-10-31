import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:contro_asistencias/providers/student_provider.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/providers/user_provider.dart';
import 'package:contro_asistencias/providers/attendance_provider.dart';
import 'package:contro_asistencias/presentation/widgets/attendance/tardiness_notification_badge.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/constants/app_constants.dart';
import 'package:contro_asistencias/data/models/classroom.dart';
import 'package:contro_asistencias/data/models/user_profile.dart';
import 'package:contro_asistencias/presentation/widgets/common/logo_loading_indicator.dart';

class ClassroomsScreen extends StatefulWidget {
  const ClassroomsScreen({super.key});

  @override
  State<ClassroomsScreen> createState() => _ClassroomsScreenState();
}

class _ClassroomsScreenState extends State<ClassroomsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sProv = context.read<StudentProvider>();
      final aProv = context.read<AttendanceProvider>();
      final auth = context.read<AuthProvider>();
      // Cargar según el rol del usuario autenticado
      if (auth.isTeacher && auth.currentUser != null) {
        await sProv.loadClassroomsForTeacher(auth.currentUser!.id);
      } else {
        await sProv.loadClassrooms();
      }
      context.read<UserProvider>().loadUsers();
      await aProv.loadTardinessAlerts();
      if (mounted) {
        await aProv.checkCompletedClassroomsForToday(sProv.classrooms);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentProvider>();
    final auth = context.watch<AuthProvider>();
    // Solo el Administrador puede asignar o cambiar profesores a los salones.
    // El Coordinador supervisa todos los salones, estudiantes y asistencias pero no asigna docentes.
    final canAssign = auth.isAdmin;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Salones y Secciones'),
        actions: [
          const TardinessNotificationBadge(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: () async {
              final authP = context.read<AuthProvider>();
              if (authP.isTeacher && authP.currentUser != null) {
                await context.read<StudentProvider>().loadClassroomsForTeacher(authP.currentUser!.id);
              } else {
                context.read<StudentProvider>().loadClassrooms();
              }
              context.read<UserProvider>().loadUsers();
              context.read<AttendanceProvider>().loadTardinessAlerts();
            },
          ),
          // Solo el Admin puede crear nuevos salones
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Agregar Salón',
              onPressed: () => _showAddClassroomDialog(context),
            ),
        ],
      ),
      body: provider.isLoading
          ? const Center(
              child: LogoLoadingIndicator(
                size: 48,
                message: 'Cargando salones...',
              ),
            )
          : provider.classrooms.isEmpty
              ? _buildEmpty(context, auth.isAdmin, auth.isTeacher)
              : _buildList(context, provider.classrooms, auth.isAdmin, canAssign),
    );
  }

  Widget _buildEmpty(BuildContext context, bool isAdmin, bool isTeacher) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.class_outlined, size: 72, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            isTeacher
                ? 'No tienes salones asignados'
                : 'No hay salones configurados',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 8),
            const Text(
              'Agrega un salón para comenzar',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddClassroomDialog(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar Salón'),
            ),
          ] else if (isTeacher) ...[
            const SizedBox(height: 8),
            const Text(
              'Contacta al administrador para que te asigne tus salones de clase',
              style: TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Contacta al administrador para configurar los salones del colegio',
              style: TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<Classroom> classrooms,
    bool isAdmin,
    bool canAssign,
  ) {
    // Group by grade
    final Map<String, List<Classroom>> grouped = {};
    for (final c in classrooms) {
      grouped.putIfAbsent(c.grade, () => []).add(c);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: grouped.length + (canAssign ? 1 : 0),
      itemBuilder: (context, index) {
        if (canAssign && index == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.accent.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.assignment_ind_rounded, color: AppTheme.accent, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Asignación de Profesores',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Toca el botón de asignación en cada sección para asignar o cambiar el profesor titular.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: -0.1);
        }

        final groupIndex = canAssign ? index - 1 : index;
        final grade = grouped.keys.elementAt(groupIndex);
        final gradeClassrooms = grouped[grade]!;
        final attendance = context.watch<AttendanceProvider>();

        int gradeCitations = 0;
        int gradeWarnings = 0;
        for (final c in gradeClassrooms) {
          gradeCitations += attendance.getCitationsCountForClassroom(c.id);
          gradeWarnings += attendance.getWarningsCountForClassroom(c.id);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 4),
              child: Row(
                children: [
                  Text(
                    grade,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onBackground,
                    ),
                  ),
                  if (gradeCitations > 0) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF87171)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB91C1C)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '$gradeCitations por citar rep.',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB91C1C),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (gradeWarnings > 0) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB45309)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '$gradeWarnings ${gradeWarnings == 1 ? 'alerta' : 'alertas'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF92400E),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ...gradeClassrooms.map(
              (classroom) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ClassroomTile(
                  classroom: classroom,
                  isAdmin: isAdmin,
                  canAssign: canAssign,
                  allClassrooms: classrooms,
                  onAssignTeacher: () => _showAssignTeacherSheet(context, classroom, classrooms),
                ),
              ),
            ),
            if (groupIndex < grouped.length - 1) const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  void _showAddClassroomDialog(BuildContext context) {
    String? selectedGrade;
    String? selectedSection;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Agregar Salón'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedGrade,
                decoration: const InputDecoration(labelText: 'Grado'),
                items: AppConstants.grades
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setS(() => selectedGrade = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedSection,
                decoration: const InputDecoration(labelText: 'Sección'),
                items: AppConstants.sections
                    .map((s) => DropdownMenuItem(value: s, child: Text('Sección $s')))
                    .toList(),
                onChanged: (v) => setS(() => selectedSection = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: selectedGrade != null && selectedSection != null
                  ? () async {
                      Navigator.pop(ctx);
                      // TODO: Create classroom via Supabase
                    }
                  : null,
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignTeacherSheet(
    BuildContext context,
    Classroom classroom,
    List<Classroom> allClassrooms,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AssignTeacherModal(
        classroom: classroom,
        allClassrooms: allClassrooms,
      ),
    );
    // Recargar la lista de salones al cerrar el modal para reflejar la nueva asignación
    if (mounted) {
      context.read<StudentProvider>().loadClassrooms();
    }
  }
}

class _ClassroomTile extends StatelessWidget {
  final Classroom classroom;
  final bool isAdmin;
  final bool canAssign;
  final List<Classroom> allClassrooms;
  final VoidCallback onAssignTeacher;

  const _ClassroomTile({
    required this.classroom,
    required this.isAdmin,
    required this.canAssign,
    required this.allClassrooms,
    required this.onAssignTeacher,
  });

  @override
  Widget build(BuildContext context) {
    final hasTeacher = classroom.teacherName != null && classroom.teacherName!.isNotEmpty;
    final attendance = context.watch<AttendanceProvider>();
    final citationsCount = attendance.getCitationsCountForClassroom(classroom.id);
    final warningsCount = attendance.getWarningsCountForClassroom(classroom.id);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: citationsCount > 0
              ? const Color(0xFFEF4444).withOpacity(0.5)
              : hasTeacher
                  ? Theme.of(context).dividerColor
                  : AppTheme.warning.withOpacity(0.35),
          width: citationsCount > 0 ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: citationsCount > 0
                ? const Color(0xFFEF4444).withOpacity(0.04)
                : Colors.black.withOpacity(0.03),
            blurRadius: 6,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: citationsCount > 0
                      ? const LinearGradient(
                          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(
                    classroom.section,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${classroom.grade} - Sección ${classroom.section}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    InkWell(
                      onTap: canAssign ? onAssignTeacher : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasTeacher ? Icons.person_rounded : Icons.person_off_outlined,
                            size: 14,
                            color: hasTeacher ? AppTheme.accent : AppTheme.warning,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              hasTeacher
                                  ? 'Prof. ${classroom.teacherName}'
                                  : 'Sin profesor asignado',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: hasTeacher ? FontWeight.w600 : FontWeight.w500,
                                color: hasTeacher
                                    ? Theme.of(context).textTheme.bodyMedium?.color
                                    : AppTheme.warning,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (canAssign) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.edit_outlined, size: 12, color: AppTheme.textSecondary),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canAssign)
                    IconButton(
                      icon: const Icon(Icons.assignment_ind_rounded, color: AppTheme.primary, size: 21),
                      tooltip: 'Asignar / Cambiar Profesor',
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      onPressed: onAssignTeacher,
                    ),
                  IconButton(
                    icon: const Icon(Icons.how_to_reg_rounded, color: AppTheme.accent, size: 21),
                    tooltip: 'Asistencia',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    onPressed: () =>
                        context.go('/classrooms/${classroom.id}/attendance'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.people_rounded, color: AppTheme.textSecondary, size: 21),
                    tooltip: 'Estudiantes',
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    onPressed: () =>
                        context.go('/classrooms/${classroom.id}/students'),
                  ),
                ],
              ),
            ],
          ),
          if (citationsCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 58),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF87171)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB91C1C)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$citationsCount estudiante(s) con 3 tardanzas (Citar Rep.)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (warningsCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 58),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB45309)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$warningsCount en alerta (2 tardanzas)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ).animate().fadeIn().slideX(begin: 0.05);
  }
}

class _AssignTeacherModal extends StatefulWidget {
  final Classroom classroom;
  final List<Classroom> allClassrooms;

  const _AssignTeacherModal({
    required this.classroom,
    required this.allClassrooms,
  });

  @override
  State<_AssignTeacherModal> createState() => _AssignTeacherModalState();
}

class _AssignTeacherModalState extends State<_AssignTeacherModal> {
  String _searchQuery = '';
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final studentProvider = context.read<StudentProvider>();
    final auth = context.read<AuthProvider>();

    // Solo profesores pueden ser asignados a un salón.
    // Coordinadores y administradores supervisan toda la institución y no se asignan a salones específicos.
    final potentialTeachers = userProvider.users
        .where((u) => u.isActive && u.role == 'profesor')
        .toList();

    final filteredTeachers = _searchQuery.trim().isEmpty
        ? potentialTeachers
        : potentialTeachers.where((u) {
            final q = _searchQuery.toLowerCase();
            return u.fullName.toLowerCase().contains(q) ||
                u.email.toLowerCase().contains(q);
          }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.assignment_ind_rounded, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Asignar Profesor',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${widget.classroom.grade} - Sección ${widget.classroom.section}',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Current assigned teacher card
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.classroom.teacherName != null
                      ? AppTheme.accent.withOpacity(0.08)
                      : Colors.grey.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.classroom.teacherName != null
                        ? AppTheme.accent.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.classroom.teacherName != null
                          ? Icons.school_rounded
                          : Icons.person_outline_rounded,
                      color: widget.classroom.teacherName != null
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Profesor Asignado Actual:',
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                          Text(
                            widget.classroom.teacherName ?? 'Ninguno (Sin asignar)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: widget.classroom.teacherName != null
                                  ? AppTheme.accent
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.classroom.teacherId != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.warning,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        onPressed: _isSaving
                            ? null
                            : () async {
                                setState(() => _isSaving = true);
                                final success = await studentProvider.assignTeacherToClassroom(
                                  widget.classroom.id,
                                  null,
                                );
                                if (!mounted) return;
                                setState(() => _isSaving = false);
                                if (success) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Profesor desasignado de ${widget.classroom.displayName}',
                                      ),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppTheme.warning,
                                      content: Text(
                                        studentProvider.error ?? 'Error al desasignar profesor',
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.person_remove_rounded, size: 16),
                        label: const Text('Quitar', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar profesor por nombre o correo...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),

            const SizedBox(height: 12),

            // Teacher list header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Seleccionar Profesor:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${filteredTeachers.length} disponible(s)',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // List of teachers
            Expanded(
              child: _isSaving
                  ? const Center(
                      child: LogoLoadingIndicator(
                        size: 42,
                        message: 'Asignando docente...',
                      ),
                    )
                  : filteredTeachers.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.person_search_outlined,
                                  size: 48,
                                  color: AppTheme.textSecondary,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No se encontraron profesores',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Verifica que existan usuarios activos con rol profesor.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                if (auth.isAdmin) ...[
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      context.push('/users');
                                    },
                                    icon: const Icon(Icons.person_add_rounded, size: 18),
                                    label: const Text('Crear Usuario Profesor'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filteredTeachers.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final teacher = filteredTeachers[index];
                            final isCurrent = widget.classroom.teacherId == teacher.id;

                            // Other classrooms assigned to this teacher
                            final otherAssigned = widget.allClassrooms
                                .where((c) =>
                                    c.teacherId == teacher.id &&
                                    c.id != widget.classroom.id)
                                .map((c) => c.shortName)
                                .toList();

                            return Container(
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? AppTheme.accent.withOpacity(0.08)
                                    : Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isCurrent
                                      ? AppTheme.accent
                                      : Theme.of(context).dividerColor,
                                  width: isCurrent ? 1.5 : 1,
                                ),
                              ),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: isCurrent
                                      ? AppTheme.accent
                                      : AppTheme.primary.withOpacity(0.15),
                                  foregroundColor: isCurrent ? Colors.white : AppTheme.primary,
                                  child: Text(
                                    teacher.fullName.isNotEmpty
                                        ? teacher.fullName[0].toUpperCase()
                                        : 'P',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        teacher.fullName,
                                        style: TextStyle(
                                          fontWeight:
                                              isCurrent ? FontWeight.w700 : FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (teacher.role == 'coordinador')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.secondary.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'Coord.',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.secondary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      teacher.email,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    if (otherAssigned.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'También en: ${otherAssigned.join(', ')}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.accent,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: isCurrent
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.accent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_circle_rounded,
                                              size: 16,
                                              color: AppTheme.accent,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Asignado',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.accent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onPressed: () => _assignTeacher(
                                          teacher,
                                          studentProvider,
                                        ),
                                        child: const Text('Asignar'),
                                      ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assignTeacher(
    UserProfile teacher,
    StudentProvider studentProvider,
  ) async {
    setState(() => _isSaving = true);
    final success = await studentProvider.assignTeacherToClassroom(
      widget.classroom.id,
      teacher.id,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.accent,
          content: Text(
            'Profesor "${teacher.fullName}" asignado a ${widget.classroom.displayName}',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.warning,
          content: Text(
            studentProvider.error ?? 'Error al asignar profesor',
          ),
        ),
      );
    }
  }
}

