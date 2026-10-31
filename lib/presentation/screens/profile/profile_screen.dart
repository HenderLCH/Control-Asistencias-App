import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/providers/student_provider.dart';
import 'package:contro_asistencias/providers/theme_provider.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/utils/validators.dart';
import 'package:contro_asistencias/core/constants/app_constants.dart';
import 'package:contro_asistencias/presentation/widgets/auth/change_password_dialog.dart';
import 'package:contro_asistencias/presentation/widgets/legal/legal_documents_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isUploadingPhoto = false;
  bool _isEditing = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    _nameCtrl = TextEditingController(text: user?.fullName ?? '');
    _phoneCtrl = TextEditingController(text: user?.cleanPhone ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 400,
    );
    if (image == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final auth = context.read<AuthProvider>();
      final bytes = await image.readAsBytes();
      final fileName =
          'profiles/${auth.currentUser!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(fileName, bytes);

      final url = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      await auth.updateProfile(avatarUrl: url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto de perfil actualizada'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _saveProfile() async {
    final phoneText = _phoneCtrl.text.trim();
    if (phoneText.isNotEmpty) {
      final phoneError = Validators.validateVenezuelanPhone(phoneText);
      if (phoneError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(phoneError), backgroundColor: AppTheme.error),
        );
        return;
      }
    }

    final formattedPhone = phoneText.isNotEmpty ? Validators.formatPhone(phoneText) : '';

    final auth = context.read<AuthProvider>();
    final success = await auth.updateProfile(
      fullName: _nameCtrl.text.trim(),
      phone: formattedPhone,
    );

    if (mounted) {
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Perfil actualizado' : 'Error al actualizar'),
          backgroundColor: success ? AppTheme.success : AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        actions: [
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return IconButton(
                icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                tooltip: isDark ? 'Cambiar a Modo Claro' : 'Cambiar a Modo Oscuro',
                onPressed: () => themeProvider.toggleTheme(),
              );
            },
          ),
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => setState(() => _isEditing = true),
            )
          else
            TextButton(
              onPressed: _saveProfile,
              child: const Text('Guardar'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
              child: Column(
                children: [
                  Stack(
                    children: [
                      GestureDetector(
                        onTap: _pickAndUploadAvatar,
                        child: CircleAvatar(
                          radius: 52,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          backgroundImage: user?.avatarUrl != null
                              ? NetworkImage(user!.avatarUrl!)
                              : null,
                          child: user?.avatarUrl == null
                              ? Text(
                                  user?.fullName.isNotEmpty == true
                                      ? user!.fullName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _pickAndUploadAvatar,
                          child: Container(
                            padding: const EdgeInsets.all(6),
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.fullName ?? 'Usuario',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getRoleLabel(user?.role ?? ''),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Info card
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Información Personal',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (_isEditing) ...[
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nombre completo',
                              prefixIcon: Icon(Icons.person_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            decoration: const InputDecoration(
                              labelText: 'Teléfono (Venezuela)',
                              hintText: 'Ej: 0414-1234567',
                              prefixIcon: Icon(Icons.phone_rounded),
                            ),
                            validator: (v) => Validators.validateVenezuelanPhone(v, required: false),
                          ),
                        ] else ...[
                          _ProfileRow(
                            icon: Icons.email_outlined,
                            label: 'Correo',
                            value: user?.email ?? '-',
                          ),
                          _ProfileRow(
                            icon: Icons.person_rounded,
                            label: 'Nombre',
                            value: user?.fullName ?? '-',
                          ),
                          _ProfileRow(
                            icon: Icons.phone_rounded,
                            label: 'Teléfono',
                            value: user?.cleanPhone ?? 'No registrado',
                          ),
                          _ProfileRow(
                            icon: Icons.badge_rounded,
                            label: 'Rol',
                            value: _getRoleLabel(user?.role ?? ''),
                          ),
                        ],
                      ],
                    ),
                  ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1),

                  const SizedBox(height: 16),

                  // Theme Mode Card
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.palette_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tema y Apariencia',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Elige entre modo claro, oscuro o automático',
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
                        Consumer<ThemeProvider>(
                          builder: (context, themeProvider, _) {
                            final currentMode = themeProvider.themeMode;
                            return Row(
                              children: [
                                _ThemeOptionTile(
                                  label: 'Claro',
                                  icon: Icons.light_mode_rounded,
                                  isSelected: currentMode == ThemeMode.light,
                                  onTap: () => themeProvider.setThemeMode(ThemeMode.light),
                                ),
                                const SizedBox(width: 10),
                                _ThemeOptionTile(
                                  label: 'Oscuro',
                                  icon: Icons.dark_mode_rounded,
                                  isSelected: currentMode == ThemeMode.dark,
                                  onTap: () => themeProvider.setThemeMode(ThemeMode.dark),
                                ),
                                const SizedBox(width: 10),
                                _ThemeOptionTile(
                                  label: 'Sistema',
                                  icon: Icons.brightness_auto_rounded,
                                  isSelected: currentMode == ThemeMode.system,
                                  onTap: () => themeProvider.setThemeMode(ThemeMode.system),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.1),

                  const SizedBox(height: 16),

                  // Seguridad y Contraseña
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => ChangePasswordDialog.show(context, isForced: false),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.lock_reset_rounded,
                                color: AppTheme.accent,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Seguridad y Contraseña',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Cambiar contraseña personal de acceso',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate(delay: 265.ms).fadeIn().slideY(begin: 0.1),

                  const SizedBox(height: 16),

                  // Privacidad, Términos y Eliminación de Cuenta
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => LegalDocumentsDialog.show(
                        context,
                        initialTab: LegalDocType.privacy,
                        userEmail: user?.email,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.policy_rounded,
                                color: AppTheme.primary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Privacidad, Términos y Cuenta',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Política de datos, condiciones y solicitud de baja',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).animate(delay: 272.ms).fadeIn().slideY(begin: 0.1),

                  const SizedBox(height: 16),

                  if (auth.isAdmin) ...[
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => context.go('/users'),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6B35).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.people_rounded,
                                  color: Color(0xFFFF6B35),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Gestión de Usuarios',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      'Crear y gestionar profesores y coordinadores',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppTheme.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).animate(delay: 280.ms).fadeIn().slideY(begin: 0.1),
                    const SizedBox(height: 16),
                  ],

                  // Institution card
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.school_rounded, color: AppTheme.primary, size: 32),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                AppConstants.institutionName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppTheme.primary,
                                ),
                              ),
                              Text(
                                'Sistema de Control de Asistencias v1.2',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.primary.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.1),

                  const SizedBox(height: 24),

                  // Logout button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Cerrar Sesión'),
                            content: const Text('¿Estás seguro que deseas cerrar sesión?'),
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
                                child: const Text('Cerrar Sesión'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && mounted) {
                          context.read<StudentProvider>().resetTeacherContext();
                          await context.read<AuthProvider>().signOut();
                        }
                      },
                      icon: const Icon(Icons.logout_rounded, color: AppTheme.error),
                      label: const Text(
                        'Cerrar Sesión',
                        style: TextStyle(color: AppTheme.error),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ).animate(delay: 400.ms).fadeIn(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'administrador': return 'Administrador';
      case 'coordinador': return 'Coordinador';
      case 'profesor': return 'Profesor';
      default: return role;
    }
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOptionTile({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withOpacity(0.12)
                  : (Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1E2D42).withOpacity(0.5)
                      : AppTheme.surfaceVariant),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? activeColor : Theme.of(context).dividerColor,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: isSelected ? activeColor : AppTheme.textSecondary,
                  size: 22,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? activeColor
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
