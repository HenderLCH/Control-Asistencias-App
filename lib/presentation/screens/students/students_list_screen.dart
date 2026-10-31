import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'package:contro_asistencias/providers/student_provider.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/providers/attendance_provider.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/data/models/student.dart';
import 'package:contro_asistencias/data/models/classroom.dart';
import 'package:contro_asistencias/presentation/widgets/common/logo_loading_indicator.dart';

class StudentsListScreen extends StatefulWidget {
  final String classroomId;

  const StudentsListScreen({super.key, required this.classroomId});

  @override
  State<StudentsListScreen> createState() => _StudentsListScreenState();
}

class _StudentsListScreenState extends State<StudentsListScreen> {
  String _searchQuery = '';
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<StudentProvider>();
      final auth = context.read<AuthProvider>();
      provider.loadStudentsByClassroom(widget.classroomId);
      if (auth.isTeacher && auth.currentUser != null) {
        provider.loadClassroomsForTeacher(auth.currentUser!.id);
      } else {
        provider.loadClassrooms();
      }
    });
  }

  List<Student> get _filteredStudents {
    final provider = context.read<StudentProvider>();
    if (_searchQuery.isEmpty) return provider.students;
    final q = _searchQuery.toLowerCase();
    return provider.students.where((s) {
      return s.fullName.toLowerCase().contains(q) ||
          s.cedula.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentProvider>();
    final auth = context.watch<AuthProvider>();
    final classroom = provider.getClassroom(widget.classroomId);

    return PopScope(
      canPop: !auth.isTeacher,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (auth.isTeacher) {
          context.go('/dashboard');
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (auth.isTeacher) {
                context.go('/dashboard');
              } else {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/classrooms');
                }
              }
            },
          ),
          title: Text(classroom?.displayName ?? 'Estudiantes'),
        actions: [
          if (auth.isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                if (value == 'import') _importCsv(context, classroom);
                if (value == 'clear_all') _confirmClearClassroom(context, classroom);
                if (value == 'add') {
                  context.go(
                    '/classrooms/${widget.classroomId}/students/add',
                  );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'add',
                  child: Row(
                    children: [
                      Icon(Icons.person_add_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('Agregar estudiante'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('Importar CSV'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_rounded, size: 20, color: AppTheme.error),
                      SizedBox(width: 10),
                      Text(
                        'Vaciar salón (Eliminar todos)',
                        style: TextStyle(color: AppTheme.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o cédula...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // Stats bar
          if (provider.students.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${provider.students.length} estudiantes',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => context.go(
                      '/classrooms/${widget.classroomId}/attendance',
                    ),
                    icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                    label: const Text('Pasar Asistencia'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Student list
          Expanded(
            child: _isImporting
                ? const Center(
                    child: LogoLoadingIndicator(
                      size: 52,
                      message: 'Importando estudiantes...',
                    ),
                  )
                : provider.isLoading
                    ? const Center(
                        child: LogoLoadingIndicator(
                          size: 48,
                          message: 'Cargando estudiantes...',
                        ),
                      )
                    : _filteredStudents.isEmpty
                        ? _buildEmpty(context, auth.isAdmin, classroom)
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredStudents.length,
                            itemBuilder: (context, index) {
                              final student = _filteredStudents[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _StudentTile(
                                  student: student,
                                  index: index,
                                  classroomId: widget.classroomId,
                                  isAdmin: auth.isAdmin,
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: auth.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => context.go(
                '/classrooms/${widget.classroomId}/students/add',
              ),
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Agregar'),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
      ),
    );
  }

  Future<void> _confirmClearClassroom(BuildContext context, Classroom? classroom) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.error),
            SizedBox(width: 8),
            Text('Vaciar Salón'),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar TODOS los estudiantes de ${classroom?.displayName ?? 'este salón'}?\n\nEsta opción es ideal para limpiar estudiantes de prueba. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Sí, Eliminar Todos'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await context
          .read<StudentProvider>()
          .deleteAllStudentsInClassroom(widget.classroomId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Todos los estudiantes de este salón fueron eliminados'
                  : 'Error al vaciar el salón',
            ),
            backgroundColor: success ? AppTheme.success : AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _importCsv(BuildContext context, Classroom? classroom) async {
    if (classroom == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    final csvString = utf8.decode(bytes);
    final csvData = const CsvToListConverter().convert(csvString);

    // Show preview dialog
    if (mounted) {
      final confirmed = await _showImportPreviewDialog(context, csvData, classroom);
      if (confirmed == true) {
        setState(() => _isImporting = true);
        final importResult = await context.read<StudentProvider>().importFromCsv(
              csvData: csvData,
              classroomId: classroom.id,
              grade: classroom.grade,
              section: classroom.section,
            );
        setState(() => _isImporting = false);

        if (mounted) {
          _showImportResult(context, importResult);
        }
      }
    }
  }

  Future<bool?> _showImportPreviewDialog(
    BuildContext context,
    List<List<dynamic>> csvData,
    Classroom classroom,
  ) async {
    final rows = csvData.length > 1 ? csvData.sublist(1) : [];
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vista Previa de Importación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Salón: ${classroom.displayName}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${rows.length} estudiante(s) a importar',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            const Text(
              'Formato esperado:\ncédula, nombre, apellido, rep_nombre, rep_teléfono',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            if (csvData.isNotEmpty) ...[
              const Text(
                'Encabezados detectados:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                csvData[0].join(', '),
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
  }

  void _showImportResult(BuildContext context, ImportResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.failed == 0 ? Icons.check_circle_rounded : Icons.warning_rounded,
              color: result.failed == 0 ? AppTheme.success : AppTheme.warning,
            ),
            const SizedBox(width: 10),
            const Text('Resultado de Importación'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResultRow(label: 'Importados exitosamente', value: result.success, color: AppTheme.success),
            _ResultRow(label: 'Con errores', value: result.failed, color: AppTheme.error),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Errores:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              ...result.errors.take(5).map(
                    (e) => Text('• $e', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, bool isAdmin, Classroom? classroom) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline_rounded, size: 72, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          const Text(
            'No hay estudiantes en este salón',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 8),
            const Text(
              'Agrega estudiantes manual o importa un CSV',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => context.go(
                    '/classrooms/${widget.classroomId}/students/add',
                  ),
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text('Agregar'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _importCsv(context, classroom),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Importar CSV'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  final Student student;
  final int index;
  final String classroomId;
  final bool isAdmin;

  const _StudentTile({
    required this.student,
    required this.index,
    required this.classroomId,
    this.isAdmin = false,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Estudiante'),
        content: Text(
          '¿Estás seguro de que deseas eliminar a "${student.fullName}"?\n\nEsta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await context.read<StudentProvider>().deleteStudent(student.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Estudiante "${student.fullName}" eliminado'
                  : 'Error al eliminar estudiante',
            ),
            backgroundColor: success ? AppTheme.success : AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final attendance = context.watch<AttendanceProvider>();
    final lateCount = attendance.getLateCountForStudent(student.id);

    return GestureDetector(
      onTap: () => context.go(
        '/classrooms/$classroomId/students/${student.id}',
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: lateCount >= 3
                ? const Color(0xFFEF4444).withOpacity(0.5)
                : (lateCount == 2
                    ? const Color(0xFFF59E0B).withOpacity(0.4)
                    : Theme.of(context).dividerColor),
            width: lateCount >= 3 ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: lateCount >= 3
                  ? const Color(0xFFEF4444).withOpacity(0.04)
                  : Colors.black.withOpacity(0.03),
              blurRadius: 6,
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: (student.isFemale ? const Color(0xFFE91E63) : AppTheme.primary).withOpacity(0.12),
            backgroundImage: student.photoUrl != null
                ? NetworkImage(student.photoUrl!)
                : null,
            child: student.photoUrl == null
                ? Text(
                    student.initials,
                    style: TextStyle(
                      color: student.isFemale ? const Color(0xFFE91E63) : AppTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  )
                : null,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  student.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (student.isFemale ? const Color(0xFFE91E63) : const Color(0xFF1E88E5))
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  student.genderAbbr == 'F' ? 'Hembra' : 'Varón',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: student.isFemale ? const Color(0xFFE91E63) : const Color(0xFF1E88E5),
                  ),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                student.cedula.isNotEmpty
                    ? 'C.I.: ${student.cedula}'
                    : student.displayGrade,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              if (lateCount >= 3)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFEF4444)),
                      const SizedBox(width: 4),
                      Text(
                        '⚠️ $lateCount tardanzas: Citar representante',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                )
              else if (lateCount == 2)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 12, color: Color(0xFFF59E0B)),
                      SizedBox(width: 4),
                      Text(
                        '⚠️ 2 tardanzas (A 1 de citación)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppTheme.error.withOpacity(0.85),
                  tooltip: 'Eliminar estudiante',
                  onPressed: () => _confirmDelete(context),
                ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ).animate(delay: Duration(milliseconds: 50 * index)).fadeIn().slideX(begin: 0.05),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _ResultRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
