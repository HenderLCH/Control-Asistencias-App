import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:contro_asistencias/providers/student_provider.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/utils/validators.dart';
import 'package:contro_asistencias/data/models/student.dart';

class AddStudentScreen extends StatefulWidget {
  final String classroomId;

  const AddStudentScreen({super.key, required this.classroomId});

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cedulaCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _parentNameCtrl = TextEditingController();
  final _parentPhoneCtrl = TextEditingController();
  final _parentEmailCtrl = TextEditingController();
  String _phonePrefix = '0414';
  String _gender = 'M';
  bool _isSaving = false;

  @override
  void dispose() {
    _cedulaCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _parentNameCtrl.dispose();
    _parentPhoneCtrl.dispose();
    _parentEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final provider = context.read<StudentProvider>();
    final classroom = provider.getClassroom(widget.classroomId);

    if (classroom == null) {
      setState(() => _isSaving = false);
      return;
    }

    String? fullPhone;
    if (_parentPhoneCtrl.text.trim().isNotEmpty) {
      final raw = _parentPhoneCtrl.text.trim();
      final clean = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
      final combined = clean.length == 7 ? '$_phonePrefix$clean' : raw;
      fullPhone = Validators.formatPhone(combined);
    }

    final student = Student(
      id: '',
      cedula: _cedulaCtrl.text.trim(),
      firstName: _firstNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      gender: _gender,
      classroomId: widget.classroomId,
      grade: classroom.grade,
      section: classroom.section,
      parentName: _parentNameCtrl.text.trim().isNotEmpty
          ? _parentNameCtrl.text.trim()
          : null,
      parentPhone: fullPhone,
      parentEmail: _parentEmailCtrl.text.trim().isNotEmpty
          ? _parentEmailCtrl.text.trim().toLowerCase()
          : null,
      createdAt: DateTime.now(),
    );

    final success = await provider.addStudent(student);
    setState(() => _isSaving = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Estudiante agregado exitosamente'),
            backgroundColor: AppTheme.success,
          ),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error ?? 'Error al agregar estudiante'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentProvider>();
    final classroom = provider.getClassroom(widget.classroomId);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Agregar Estudiante'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Classroom info
              if (classroom != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.class_rounded, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        classroom.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              _SectionHeader(title: 'Datos del Estudiante'),
              const SizedBox(height: 12),

              TextFormField(
                controller: _cedulaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cédula Escolar (opcional)',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Requerido' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Apellido *',
                      ),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Requerido' : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Selector de Sexo (Masculino / Femenino)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sexo del Estudiante *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _gender = 'M'),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _gender == 'M'
                                  ? const Color(0xFF1E88E5).withOpacity(0.15)
                                  : Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _gender == 'M'
                                    ? const Color(0xFF1E88E5)
                                    : Theme.of(context).dividerColor,
                                width: _gender == 'M' ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.male_rounded,
                                  color: _gender == 'M'
                                      ? const Color(0xFF1E88E5)
                                      : AppTheme.textSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Masculino (V)',
                                  style: TextStyle(
                                    fontWeight: _gender == 'M'
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _gender == 'M'
                                        ? const Color(0xFF1E88E5)
                                        : Theme.of(context).textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _gender = 'F'),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _gender == 'F'
                                  ? const Color(0xFFE91E63).withOpacity(0.15)
                                  : Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _gender == 'F'
                                    ? const Color(0xFFE91E63)
                                    : Theme.of(context).dividerColor,
                                width: _gender == 'F' ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.female_rounded,
                                  color: _gender == 'F'
                                      ? const Color(0xFFE91E63)
                                      : AppTheme.textSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Femenino (H)',
                                  style: TextStyle(
                                    fontWeight: _gender == 'F'
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: _gender == 'F'
                                        ? const Color(0xFFE91E63)
                                        : Theme.of(context).textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _SectionHeader(title: 'Datos del Representante (opcional)'),
              const SizedBox(height: 12),

              TextFormField(
                controller: _parentNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Representante',
                  prefixIcon: Icon(Icons.family_restroom_rounded),
                ),
              ),

              const SizedBox(height: 12),

              // Teléfono con prefijo venezolano
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 105,
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _phonePrefix,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(12),
                        icon: const Icon(Icons.arrow_drop_down, size: 20),
                        items: Validators.venezuelanPhonePrefixes.map((p) {
                          return DropdownMenuItem(
                            value: p,
                            child: Text(
                              p,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _phonePrefix = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _parentPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono (opcional)',
                        hintText: '1234567',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final clean = value.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
                        final full = clean.length == 7 ? '$_phonePrefix$clean' : clean;
                        return Validators.validateVenezuelanPhone(full);
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _parentEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico (opcional)',
                  hintText: 'ejemplo@correo.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) => Validators.validateEmail(value, required: false),
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Guardar Estudiante'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppTheme.primary,
        letterSpacing: 0.3,
      ),
    );
  }
}
