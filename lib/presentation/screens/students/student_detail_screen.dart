import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:contro_asistencias/providers/student_provider.dart';
import 'package:contro_asistencias/providers/attendance_provider.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/utils/justification_helper.dart';
import 'package:contro_asistencias/data/models/student.dart';
import 'package:contro_asistencias/data/models/attendance_record.dart';

class StudentDetailScreen extends StatefulWidget {
  final String studentId;
  final String classroomId;

  const StudentDetailScreen({
    super.key,
    required this.studentId,
    required this.classroomId,
  });

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final studentProv = context.read<StudentProvider>();
      if (studentProv.students.every((s) => s.id != widget.studentId)) {
        studentProv.loadStudentsByClassroom(widget.classroomId);
      }
      context.read<AttendanceProvider>().loadAttendanceHistory(
            classroomId: widget.classroomId,
            startDate: DateTime.now().subtract(const Duration(days: 180)),
            endDate: DateTime.now().add(const Duration(days: 365)),
            studentId: widget.studentId,
          );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 500,
    );
    if (image == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final bytes = await image.readAsBytes();
      final fileName =
          'students/${widget.studentId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(fileName, bytes);

      final url = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      await context
          .read<StudentProvider>()
          .updateStudentPhoto(widget.studentId, url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto actualizada exitosamente'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir foto: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _confirmDeleteStudent(BuildContext context, Student student) async {
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success =
          await context.read<StudentProvider>().deleteStudent(student.id);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Estudiante "${student.fullName}" eliminado'),
              backgroundColor: AppTheme.success,
            ),
          );
          context.pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al eliminar estudiante'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  static Future<void> _showEditStudentDialog(BuildContext context, Student student) async {
    final firstNameCtrl = TextEditingController(text: student.firstName);
    final lastNameCtrl = TextEditingController(text: student.lastName);
    final cedulaCtrl = TextEditingController(text: student.cedula);
    final parentNameCtrl = TextEditingController(text: student.parentName ?? '');
    final parentPhoneCtrl = TextEditingController(text: student.parentPhone ?? '');
    final parentEmailCtrl = TextEditingController(text: student.parentEmail ?? '');
    String selectedGender = student.gender;
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppTheme.primary, size: 28),
              const SizedBox(width: 8),
              const Text('Editar Estudiante', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Datos del Estudiante', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: firstNameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombres *', prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lastNameCtrl,
                    decoration: const InputDecoration(labelText: 'Apellidos *', prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cedulaCtrl,
                    decoration: const InputDecoration(labelText: 'Cédula / Identificador *', prefixIcon: Icon(Icons.credit_card_rounded)),
                  ),
                  const SizedBox(height: 14),

                  // Selector de Sexo
                  const Text('Sexo *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedGender = 'M'),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedGender == 'M' ? const Color(0xFF1E88E5).withOpacity(0.12) : Theme.of(context).cardColor,
                              border: Border.all(
                                color: selectedGender == 'M' ? const Color(0xFF1E88E5) : Theme.of(context).dividerColor,
                                width: selectedGender == 'M' ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.male_rounded, color: selectedGender == 'M' ? const Color(0xFF1E88E5) : AppTheme.textSecondary, size: 20),
                                const SizedBox(width: 6),
                                Text(
                                  'Varón (V)',
                                  style: TextStyle(
                                    fontWeight: selectedGender == 'M' ? FontWeight.w800 : FontWeight.w500,
                                    color: selectedGender == 'M' ? const Color(0xFF1E88E5) : AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedGender = 'F'),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedGender == 'F' ? const Color(0xFFE91E63).withOpacity(0.12) : Theme.of(context).cardColor,
                              border: Border.all(
                                color: selectedGender == 'F' ? const Color(0xFFE91E63) : Theme.of(context).dividerColor,
                                width: selectedGender == 'F' ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.female_rounded, color: selectedGender == 'F' ? const Color(0xFFE91E63) : AppTheme.textSecondary, size: 20),
                                const SizedBox(width: 6),
                                Text(
                                  'Hembra (H)',
                                  style: TextStyle(
                                    fontWeight: selectedGender == 'F' ? FontWeight.w800 : FontWeight.w500,
                                    color: selectedGender == 'F' ? const Color(0xFFE91E63) : AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Datos del Representante (Opcional)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: parentNameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre del Representante', prefixIcon: Icon(Icons.person_outline_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: parentPhoneCtrl,
                    decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: parentEmailCtrl,
                    decoration: const InputDecoration(labelText: 'Correo Electrónico', prefixIcon: Icon(Icons.email_outlined)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (firstNameCtrl.text.trim().isEmpty || lastNameCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Nombres y apellidos son requeridos'), backgroundColor: AppTheme.error),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      final updated = student.copyWith(
                        firstName: firstNameCtrl.text.trim(),
                        lastName: lastNameCtrl.text.trim(),
                        cedula: cedulaCtrl.text.trim(),
                        gender: selectedGender,
                        parentName: parentNameCtrl.text.trim().isEmpty ? null : parentNameCtrl.text.trim(),
                        parentPhone: parentPhoneCtrl.text.trim().isEmpty ? null : parentPhoneCtrl.text.trim(),
                        parentEmail: parentEmailCtrl.text.trim().isEmpty ? null : parentEmailCtrl.text.trim(),
                      );

                      final ok = await context.read<StudentProvider>().updateStudent(updated);
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok ? 'Estudiante actualizado exitosamente' : 'Error al actualizar estudiante'),
                            backgroundColor: ok ? AppTheme.success : AppTheme.error,
                          ),
                        );
                      }
                    },
              child: isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar Cambios'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentProvider = context.watch<StudentProvider>();
    final auth = context.watch<AuthProvider>();
    Student? studentNullable;
    try {
      studentNullable = studentProvider.students.firstWhere((s) => s.id == widget.studentId);
    } catch (_) {}

    if (studentNullable == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Estudiante no encontrado')),
      );
    }
    final student = studentNullable;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 275,
            pinned: true,
            actions: [
              if (auth.isAdmin || auth.isCoordinator)
                IconButton(
                  icon: const Icon(Icons.edit_rounded, color: Colors.white),
                  tooltip: 'Editar Información',
                  onPressed: () => _showEditStudentDialog(context, student),
                ),
              if (auth.isAdmin)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                  tooltip: 'Eliminar Estudiante',
                  onPressed: () => _confirmDeleteStudent(context, student),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
                padding: const EdgeInsets.only(top: 36, bottom: 50),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      children: [
                        GestureDetector(
                          onTap: auth.isAdmin ? _pickAndUploadPhoto : null,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            backgroundImage: student.photoUrl != null
                                ? NetworkImage(student.photoUrl!)
                                : null,
                            child: student.photoUrl == null
                                ? Text(
                                    student.initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        if (auth.isAdmin)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppTheme.accent,
                                shape: BoxShape.circle,
                              ),
                              child: _isUploadingPhoto
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        student.fullName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      student.displayGrade,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.accent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              tabs: const [
                Tab(text: 'Información'),
                Tab(text: 'Asistencia'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _InfoTab(student: student),
            _AttendanceTab(
              student: student,
              classroomId: widget.classroomId,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  final Student student;

  const _InfoTab({required this.student});

  @override
  Widget build(BuildContext context) {
    final attendance = context.watch<AttendanceProvider>();
    final auth = context.watch<AuthProvider>();
    final lateCount = attendance.getLateCountForStudent(student.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (lateCount >= 3)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '🚨 Citar al Representante ($lateCount tardanzas)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Este estudiante ha acumulado 3 o más tardanzas. Se requiere citar formalmente a su representante.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.9)
                          : null,
                    ),
                  ),
                ],
              ),
            ).animate().shake(duration: 400.ms)
          else if (lateCount == 2)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 24),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '⚠️ Alerta Preventiva (2 tardanzas)',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'El estudiante lleva 2 tardanzas registradas. Está a 1 tardanza de que se le deba citar el representante.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.9)
                          : null,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(),

          _InfoCard(
            title: 'Datos Personales',
            icon: Icons.person_rounded,
            children: [
              _InfoRow(label: 'C.I.', value: student.cedula.isNotEmpty ? student.cedula : 'No registrada'),
              _InfoRow(label: 'Nombre', value: student.firstName),
              _InfoRow(label: 'Apellido', value: student.lastName),
              _InfoRow(label: 'Sexo', value: '${student.genderLabel} (${student.genderAbbr == "F" ? "Hembra" : "Varón"})'),
              if (student.birthDate != null)
                _InfoRow(
                  label: 'Fecha de Nac.',
                  value:
                      '${student.birthDate!.day}/${student.birthDate!.month}/${student.birthDate!.year}',
                ),
            ],
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1),

          const SizedBox(height: 16),

          if (student.parentName != null || student.parentPhone != null)
            _InfoCard(
              title: 'Representante',
              icon: Icons.family_restroom_rounded,
              children: [
                if (student.parentName != null)
                  _InfoRow(label: 'Nombre', value: student.parentName!),
                if (student.parentEmail != null)
                  _InfoRow(label: 'Correo', value: student.parentEmail!),
              ],
            ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.1),

          if (auth.isAdmin || auth.isCoordinator) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _StudentDetailScreenState._showEditStudentDialog(context, student),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Editar Información'),
              ),
            ),
          ],

          if (auth.isAdmin) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.error,
                          ),
                          child: const Text('Eliminar'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && context.mounted) {
                    final success =
                        await context.read<StudentProvider>().deleteStudent(student.id);
                    if (context.mounted) {
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Estudiante "${student.fullName}" eliminado'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                        context.pop();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Error al eliminar estudiante'),
                            backgroundColor: AppTheme.error,
                          ),
                        );
                      }
                    }
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                label: const Text(
                  'Eliminar Estudiante',
                  style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : AppTheme.onBackground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 0),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceTab extends StatelessWidget {
  final Student student;
  final String classroomId;

  const _AttendanceTab({
    required this.student,
    required this.classroomId,
  });

  Future<void> _showEditOrJustifyModal({
    required BuildContext context,
    required DateTime date,
    required String initialStatus,
    String? initialNotes,
    List<AttendanceRecord>? allStudentRecords,
  }) async {
    final attendanceProvider = context.read<AttendanceProvider>();
    final auth = context.read<AuthProvider>();
    final canEditPastDays = auth.isAdmin || auth.isCoordinator;

    final parsedExisting = JustificationHelper.parseNotes(initialNotes);
    final reasonCtrl = TextEditingController(text: parsedExisting.cleanReason);
    String selectedStatus = initialStatus.isNotEmpty ? initialStatus : 'justificado';
    PlatformFile? attachedFile;
    String? existingAttachmentName = parsedExisting.attachmentName;
    final existingAttachmentBytes = parsedExisting.attachmentBytes;
    bool keepExistingAttachment = parsedExisting.hasAttachment;
    String? fileError;
    bool isSaving = false;

    // Conjunto de fechas seleccionadas para justificar de una sola vez
    final List<DateTime> selectedDates = parsedExisting.coveredDates.isNotEmpty
        ? List<DateTime>.from(parsedExisting.coveredDates)
        : [DateTime(date.year, date.month, date.day)];

    bool containsDate(List<DateTime> list, DateTime target) {
      return list.any((d) => DateUtils.isSameDay(d, target));
    }

    void toggleDate(List<DateTime> list, DateTime target) {
      final idx = list.indexWhere((d) => DateUtils.isSameDay(d, target));
      if (idx >= 0) {
        if (list.length > 1) {
          list.removeAt(idx);
        }
      } else {
        list.add(DateTime(target.year, target.month, target.day));
        list.sort((a, b) => a.compareTo(b));
      }
    }

    final studentRecords = allStudentRecords ??
        attendanceProvider.attendanceHistory
            .where((r) => r.studentId == student.id)
            .toList();
    final absentRecords = studentRecords.where((r) => r.isAbsent).toList();

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
              constraints: const BoxConstraints(maxWidth: 520),
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
                      // Encabezado
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.getAttendanceColor(selectedStatus).withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              AppTheme.getAttendanceIcon(selectedStatus),
                              color: AppTheme.getAttendanceColor(selectedStatus),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedStatus == 'justificado'
                                      ? (selectedDates.length > 1
                                          ? 'Justificar ${selectedDates.length} Días'
                                          : 'Justificar Inasistencia')
                                      : 'Editar Asistencia',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  student.fullName,
                                  style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 22),
                            onPressed: isSaving ? null : () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 14),

                      // Selector de estado
                      const Text(
                        'Estado de asistencia:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StatusOptionChip(
                            label: 'Justificado',
                            value: 'justificado',
                            selectedValue: selectedStatus,
                            color: AppTheme.justified,
                            icon: Icons.assignment_turned_in_rounded,
                            onSelected: (v) => setModalState(() => selectedStatus = v),
                          ),
                          _StatusOptionChip(
                            label: 'Presente',
                            value: 'presente',
                            selectedValue: selectedStatus,
                            color: AppTheme.present,
                            icon: Icons.check_circle_rounded,
                            onSelected: (v) => setModalState(() => selectedStatus = v),
                          ),
                          _StatusOptionChip(
                            label: 'Tardanza',
                            value: 'tardanza',
                            selectedValue: selectedStatus,
                            color: AppTheme.late,
                            icon: Icons.access_time_filled_rounded,
                            onSelected: (v) => setModalState(() => selectedStatus = v),
                          ),
                          _StatusOptionChip(
                            label: 'Ausente',
                            value: 'ausente',
                            selectedValue: selectedStatus,
                            color: AppTheme.absent,
                            icon: Icons.cancel_rounded,
                            onSelected: (v) => setModalState(() => selectedStatus = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Selección de 1 o múltiples fechas (para justificar varios días con un solo justificativo)
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
                            Row(
                              children: [
                                const Icon(Icons.date_range_rounded, size: 17, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Fechas a aplicar (${selectedDates.length} ${selectedDates.length == 1 ? "día seleccionado" : "días seleccionados"}):',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: selectedDates.map((d) {
                                final now = DateTime.now();
                                final todayNorm = DateTime(now.year, now.month, now.day);
                                final isFuture = DateTime(d.year, d.month, d.day).isAfter(todayNorm);
                                return Chip(
                                  label: Text(
                                    isFuture
                                        ? '${DateFormat('EEE d MMM', 'es').format(d)} (Futuro)'
                                        : DateFormat('EEE d MMM', 'es').format(d),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  backgroundColor: isFuture
                                      ? const Color(0xFF1D4ED8)
                                      : AppTheme.primary,
                                  deleteIconColor: Colors.white,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onDeleted: selectedDates.length > 1
                                      ? () => setModalState(() => toggleDate(selectedDates, d))
                                      : null,
                                );
                              }).toList(),
                            ),
                            if (canEditPastDays && absentRecords.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Inasistencias registradas del alumno (toca para incluir):',
                                      style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (absentRecords.length > 1)
                                    TextButton(
                                      onPressed: () {
                                        setModalState(() {
                                          selectedDates.clear();
                                          for (final r in absentRecords) {
                                            if (!containsDate(selectedDates, r.date)) {
                                              selectedDates.add(DateTime(r.date.year, r.date.month, r.date.day));
                                            }
                                          }
                                          selectedDates.sort((a, b) => a.compareTo(b));
                                        });
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('Marcar todas', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: absentRecords.map((r) {
                                  final isSelected = containsDate(selectedDates, r.date);
                                  return FilterChip(
                                    selected: isSelected,
                                    label: Text(
                                      DateFormat('EEE d MMM', 'es').format(r.date),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected ? Colors.white : AppTheme.absent,
                                      ),
                                    ),
                                    selectedColor: AppTheme.justified,
                                    checkmarkColor: Colors.white,
                                    backgroundColor: AppTheme.absent.withOpacity(0.10),
                                    side: BorderSide(
                                      color: isSelected ? AppTheme.justified : AppTheme.absent.withOpacity(0.35),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onSelected: (_) => setModalState(() => toggleDate(selectedDates, r.date)),
                                  );
                                }).toList(),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final now = DateTime.now();
                                    final todayNorm = DateTime(now.year, now.month, now.day);
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: selectedDates.last,
                                      firstDate: canEditPastDays ? DateTime(2024) : todayNorm,
                                      lastDate: todayNorm.add(const Duration(days: 365)),
                                      helpText: canEditPastDays
                                          ? 'Selecciona la fecha (pasada, hoy o futura)'
                                          : 'Selecciona la fecha (hoy o futura)',
                                    );
                                    if (picked != null) {
                                      setModalState(() {
                                        selectedDates
                                          ..clear()
                                          ..add(DateTime(picked.year, picked.month, picked.day));
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.event_rounded, size: 15),
                                  label: const Text('Elegir 1 fecha (pasada o futura)', style: TextStyle(fontSize: 11.5)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final now = DateTime.now();
                                    final todayNorm = DateTime(now.year, now.month, now.day);
                                    final range = await showDateRangePicker(
                                      context: context,
                                      firstDate: canEditPastDays ? DateTime(2024) : todayNorm,
                                      lastDate: todayNorm.add(const Duration(days: 365)),
                                      helpText: 'Selecciona el rango de días (pasados o futuros)',
                                      saveText: 'Aplicar rango',
                                    );
                                    if (range != null) {
                                      setModalState(() {
                                        selectedDates.clear();
                                        DateTime cur = DateTime(range.start.year, range.start.month, range.start.day);
                                        final end = DateTime(range.end.year, range.end.month, range.end.day);
                                        while (!cur.isAfter(end)) {
                                          // Excluir sábados y domingos automáticamente
                                          if (cur.weekday != DateTime.saturday && cur.weekday != DateTime.sunday) {
                                            selectedDates.add(cur);
                                          }
                                          cur = cur.add(const Duration(days: 1));
                                        }
                                        if (selectedDates.isEmpty) {
                                          selectedDates.add(DateTime(range.start.year, range.start.month, range.start.day));
                                        }
                                        selectedDates.sort((a, b) => a.compareTo(b));
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.date_range_rounded, size: 15),
                                  label: const Text('Rango de días (pasado o futuro)', style: TextStyle(fontSize: 11.5)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final now = DateTime.now();
                                    final todayNorm = DateTime(now.year, now.month, now.day);
                                    final extraDate = await showDatePicker(
                                      context: context,
                                      initialDate: selectedDates.last,
                                      firstDate: canEditPastDays ? DateTime(2024) : todayNorm,
                                      lastDate: todayNorm.add(const Duration(days: 365)),
                                      helpText: 'Agregar otra fecha al justificativo',
                                    );
                                    if (extraDate != null) {
                                      setModalState(() {
                                        if (!containsDate(selectedDates, extraDate)) {
                                          selectedDates.add(DateTime(extraDate.year, extraDate.month, extraDate.day));
                                          selectedDates.sort((a, b) => a.compareTo(b));
                                        }
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
                                  label: const Text('Agregar otra fecha', style: TextStyle(fontSize: 11.5)),
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

                      // Campo de motivo / justificativo
                      Text(
                        selectedStatus == 'justificado'
                            ? 'Motivo del justificativo *:'
                            : 'Observación / Nota (Opcional):',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: reasonCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: selectedStatus == 'justificado'
                              ? 'Ej. Reposo médico por 5 días, constancia odontológica, permiso familiar...'
                              : 'Observación adicional...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Adjuntar comprobante
                      const Text(
                        'Comprobante adjunto (Foto o PDF - máx. 1 MB):',
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
                                        ? (existingAttachmentName?.toLowerCase().endsWith('.pdf') == true
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
                                          ? 'Adjunto actual: $existingAttachmentName (toca para cambiar)'
                                          : 'Seleccionar foto o PDF del justificativo (máx. 1MB)'),
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

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSaving ? null : () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check_rounded, size: 18),
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final reason = reasonCtrl.text.trim();
                                    if (selectedStatus == 'justificado' && reason.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Por favor indica el motivo del justificativo'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }

                                    setModalState(() => isSaving = true);
                                    final finalFileName = attachedFile != null
                                        ? attachedFile!.name
                                        : (keepExistingAttachment ? existingAttachmentName : null);
                                    final finalFileBytes = attachedFile != null
                                        ? attachedFile!.bytes
                                        : (keepExistingAttachment ? existingAttachmentBytes : null);

                                    final fullNote = JustificationHelper.buildNotes(
                                      reason: reason,
                                      attachmentName: finalFileName,
                                      attachmentBytes: finalFileBytes,
                                      coveredDates: selectedStatus == 'justificado' ? selectedDates : null,
                                    );

                                    final ok = await attendanceProvider.markMultipleDatesAttendance(
                                      studentId: student.id,
                                      classroomId: classroomId,
                                      status: selectedStatus,
                                      dates: selectedDates,
                                      notes: fullNote,
                                      markedById: auth.currentUser?.id,
                                    );

                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            ok
                                                ? (selectedDates.length > 1
                                                    ? 'Justificativo aplicado exitosamente a ${selectedDates.length} días'
                                                    : (selectedStatus == 'justificado'
                                                        ? 'Justificativo guardado exitosamente'
                                                        : 'Asistencia actualizada exitosamente'))
                                                : 'Error al actualizar la asistencia',
                                          ),
                                          backgroundColor: ok ? AppTheme.success : AppTheme.error,
                                        ),
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.getAttendanceColor(selectedStatus),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            label: Text(
                              selectedStatus == 'justificado'
                                  ? (selectedDates.length > 1
                                      ? 'Guardar en ${selectedDates.length} Días'
                                      : 'Guardar Justificativo')
                                  : 'Guardar Cambios',
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
  }

  Future<void> _pickDateAndEdit(BuildContext context, List<AttendanceRecord> records, {required bool canEditPastDays}) async {
    final absentRecords = records.where((r) => r.isAbsent).toList();
    final initialDate = (canEditPastDays && absentRecords.isNotEmpty)
        ? absentRecords.first.date
        : DateTime.now();

    AttendanceRecord? existing;
    try {
      existing = records.firstWhere((r) => DateUtils.isSameDay(r.date, initialDate));
    } catch (_) {}

    await _showEditOrJustifyModal(
      context: context,
      date: initialDate,
      initialStatus: 'justificado',
      initialNotes: existing?.notes,
      allStudentRecords: records,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AttendanceProvider>();
    final auth = context.watch<AuthProvider>();
    final canEditPastDays = auth.isAdmin || auth.isCoordinator;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final todayNorm = DateTime(now.year, now.month, now.day);

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final records = provider.attendanceHistory
        .where((r) => r.studentId == student.id)
        .toList();

    // Summary
    final present = records.where((r) => r.isPresent).length;
    final absent = records.where((r) => r.isAbsent).length;
    final late = records.where((r) => r.isLate).length;
    final justified = records.where((r) => r.isJustified).length;

    return Column(
      children: [
        // Summary bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              _AttendanceBadge(label: 'Presente', count: present, color: AppTheme.present),
              const SizedBox(width: 6),
              _AttendanceBadge(label: 'Ausente', count: absent, color: AppTheme.absent),
              const SizedBox(width: 6),
              _AttendanceBadge(label: 'Tardanza', count: late, color: AppTheme.late),
              const SizedBox(width: 6),
              _AttendanceBadge(label: 'Justificado', count: justified, color: AppTheme.justified),
            ],
          ),
        ),

        // Botón para cargar justificativo (fechas pasadas para Coord/Admin, o fechas de hoy/futuras)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _pickDateAndEdit(context, records, canEditPastDays: canEditPastDays),
              icon: const Icon(Icons.date_range_rounded, size: 18),
              label: Text(
                canEditPastDays
                    ? 'Cargar justificativo (días pasados, hoy o futuros)'
                    : 'Cargar justificativo (hoy o fechas futuras)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: BorderSide(color: AppTheme.primary.withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        if (!canEditPastDays)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.warning.withOpacity(0.35)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_clock_rounded, size: 16, color: AppTheme.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Los días anteriores solo pueden ser editados por Coordinadores o Administrador.',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.warning, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

        if (records.isEmpty)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy_rounded, size: 56, color: AppTheme.textSecondary),
                  SizedBox(height: 12),
                  Text('No hay registros de asistencia'),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                final recNorm = DateTime(record.date.year, record.date.month, record.date.day);
                final isRecordFuture = recNorm.isAfter(todayNorm);
                final isRecordTodayOrFuture = !recNorm.isBefore(todayNorm);
                final canEditThisRecord = isRecordTodayOrFuture || canEditPastDays;
                final statusColor = AppTheme.getAttendanceColor(record.status);
                final justInfo = JustificationHelper.parseNotes(record.notes);
                final hasNotes = justInfo.cleanReason.isNotEmpty || justInfo.hasAttachment;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: record.isAbsent
                          ? AppTheme.absent.withOpacity(0.35)
                          : (record.isJustified
                              ? AppTheme.justified.withOpacity(0.35)
                              : Theme.of(context).dividerColor),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      // Si está justificado o tiene nota/adjunto, primero abrimos el VISOR para ver el PDF o imagen
                      if (record.isJustified || hasNotes) {
                        JustificationHelper.showJustificationViewer(
                          context: context,
                          studentName: student.fullName,
                          classroomName: student.displayGrade,
                          date: record.date,
                          status: record.status,
                          rawNotes: record.notes,
                          canEdit: canEditThisRecord,
                          onEdit: canEditThisRecord
                              ? () => _showEditOrJustifyModal(
                                    context: context,
                                    date: record.date,
                                    initialStatus: record.status,
                                    initialNotes: record.notes,
                                    allStudentRecords: records,
                                  )
                              : null,
                        );
                      } else if (canEditThisRecord) {
                        _showEditOrJustifyModal(
                          context: context,
                          date: record.date,
                          initialStatus: record.isAbsent ? 'justificado' : record.status,
                          initialNotes: record.notes,
                          allStudentRecords: records,
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  AppTheme.getAttendanceIcon(record.status),
                                  color: statusColor,
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
                                        Flexible(
                                          child: Text(
                                            _formatStatus(record.status),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: statusColor,
                                            ),
                                          ),
                                        ),
                                        if (isRecordFuture) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDBEAFE),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFF93C5FD)),
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
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatDate(record.date),
                                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (record.isJustified || hasNotes) ...[
                                OutlinedButton.icon(
                                  onPressed: () => JustificationHelper.showJustificationViewer(
                                    context: context,
                                    studentName: student.fullName,
                                    classroomName: student.displayGrade,
                                    date: record.date,
                                    status: record.status,
                                    rawNotes: record.notes,
                                    canEdit: canEditThisRecord,
                                    onEdit: canEditThisRecord
                                        ? () => _showEditOrJustifyModal(
                                              context: context,
                                              date: record.date,
                                              initialStatus: record.status,
                                              initialNotes: record.notes,
                                              allStudentRecords: records,
                                            )
                                        : null,
                                  ),
                                  icon: Icon(
                                    justInfo.hasAttachment
                                        ? (justInfo.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded)
                                        : Icons.visibility_rounded,
                                    size: 15,
                                  ),
                                  label: Text(
                                    justInfo.hasAttachment ? 'Ver Adjunto' : 'Ver Detalle',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.justified,
                                    side: BorderSide(color: AppTheme.justified.withOpacity(0.5)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                                if (canEditThisRecord)
                                  IconButton(
                                    icon: const Icon(Icons.edit_note_rounded, color: AppTheme.primary, size: 20),
                                    tooltip: 'Editar justificativo',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _showEditOrJustifyModal(
                                      context: context,
                                      date: record.date,
                                      initialStatus: record.status,
                                      initialNotes: record.notes,
                                      allStudentRecords: records,
                                    ),
                                  ),
                              ] else if (canEditThisRecord && record.isAbsent)
                                ElevatedButton.icon(
                                  onPressed: () => _showEditOrJustifyModal(
                                    context: context,
                                    date: record.date,
                                    initialStatus: 'justificado',
                                    initialNotes: record.notes,
                                    allStudentRecords: records,
                                  ),
                                  icon: const Icon(Icons.assignment_turned_in_rounded, size: 15),
                                  label: const Text(
                                    'Justificar',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.justified,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                )
                              else if (canEditThisRecord)
                                IconButton(
                                  icon: const Icon(Icons.edit_note_rounded, color: AppTheme.primary),
                                  tooltip: 'Editar asistencia',
                                  onPressed: () => _showEditOrJustifyModal(
                                    context: context,
                                    date: record.date,
                                    initialStatus: record.status,
                                    initialNotes: record.notes,
                                    allStudentRecords: records,
                                  ),
                                ),
                            ],
                          ),
                          if (hasNotes) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Theme.of(context).dividerColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (justInfo.cleanReason.isNotEmpty)
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.notes_rounded, size: 15, color: AppTheme.justified),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            justInfo.cleanReason,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark ? Colors.white70 : Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (justInfo.hasAttachment || justInfo.coveredDates.length > 1) ...[
                                    if (justInfo.cleanReason.isNotEmpty) const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        if (justInfo.hasAttachment)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                justInfo.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                                                size: 13,
                                                color: AppTheme.primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                justInfo.attachmentName!,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        if (justInfo.coveredDates.length > 1)
                                          Text(
                                            '• Cubre ${justInfo.coveredDates.length} días',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.justified,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'presente':
        return 'Presente';
      case 'ausente':
        return 'Ausente (Inasistencia)';
      case 'tardanza':
        return 'Tardanza';
      case 'justificado':
        return 'Justificado';
      default:
        return status;
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('EEEE, d MMM yyyy', 'es').format(date);
  }
}

class _StatusOptionChip extends StatelessWidget {
  final String label;
  final String value;
  final String selectedValue;
  final Color color;
  final IconData icon;
  final ValueChanged<String> onSelected;

  const _StatusOptionChip({
    required this.label,
    required this.value,
    required this.selectedValue,
    required this.color,
    required this.icon,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selectedValue;
    return InkWell(
      onTap: () => onSelected(value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.35),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _AttendanceBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

