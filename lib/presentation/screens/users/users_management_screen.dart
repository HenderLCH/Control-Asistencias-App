import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/utils/validators.dart';
import 'package:contro_asistencias/data/models/user_profile.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/providers/user_provider.dart';
import 'package:contro_asistencias/providers/student_provider.dart';
import 'package:contro_asistencias/core/services/password_management_service.dart';

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadUsers();
      context.read<StudentProvider>().loadClassrooms();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<UserProfile> _filterUsers(List<UserProfile> allUsers, int tabIndex) {
    var filtered = allUsers;

    if (tabIndex == 1) {
      filtered = filtered.where((u) => u.role == 'profesor').toList();
    } else if (tabIndex == 2) {
      filtered = filtered.where((u) => u.role == 'coordinador').toList();
    } else if (tabIndex == 3) {
      filtered = filtered.where((u) => u.role == 'administrador').toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((u) {
        return u.fullName.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            (u.phone?.contains(q) ?? false);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final auth = context.watch<AuthProvider>();

    if (!auth.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Acceso Restringido')),
        body: const Center(
          child: Text('Solo el Administrador tiene acceso a la gestión de usuarios.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: () => userProvider.loadUsers(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accent,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF94A3B8)
              : AppTheme.textSecondary,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'Todos'),
            Tab(text: 'Profesores'),
            Tab(text: 'Coord.'),
            Tab(text: 'Admin'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, correo o teléfono...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // Banner de solicitudes de restablecimiento de contraseña
          Consumer<UserProvider>(
            builder: (context, uProv, _) {
              final pendingUsers = uProv.users.where((u) =>
                  u.hasResetRequest ||
                  uProv.pendingResetEmails.contains(u.email.toLowerCase())
              ).toList();

              if (pendingUsers.isEmpty) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.6)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFF59E0B),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${pendingUsers.length} Solicitud(es) de Cambio de Clave',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                          Text(
                            pendingUsers.map((u) => u.fullName).join(', '),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFFE2E8F0)
                                  : AppTheme.onBackground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => showGeneratePasswordDialog(context, pendingUsers.first),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Generar Clave',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // User list
          Expanded(
            child: userProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: List.generate(4, (tabIndex) {
                      final users = _filterUsers(
                        userProvider.users,
                        tabIndex,
                      );

                      if (users.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.people_outline_rounded,
                                size: 64,
                                color: AppTheme.textSecondary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No se encontraron usuarios coincidentes'
                                    : 'No hay usuarios en esta categoría',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          return _UserTile(
                            user: user,
                            isCurrentLoggedAdmin: user.id == auth.currentUser?.id,
                          );
                        },
                      );
                    }),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateUserModal(context),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Crear Usuario'),
      ),
    );
  }

  void _showCreateUserModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _CreateUserBottomSheet(),
    );
  }
}

class _UserTile extends StatefulWidget {
  final UserProfile user;
  final bool isCurrentLoggedAdmin;

  const _UserTile({
    required this.user,
    required this.isCurrentLoggedAdmin,
  });

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _showPassword = false;

  Color _getRoleColor(String role) {
    switch (role) {
      case 'administrador':
        return AppTheme.primary;
      case 'coordinador':
        return AppTheme.secondary;
      case 'profesor':
        return AppTheme.accent;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'administrador':
        return 'Administrador';
      case 'coordinador':
        return 'Coordinador';
      case 'profesor':
        return 'Profesor';
      default:
        return role;
    }
  }

  void _openEditModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditUserBottomSheet(user: widget.user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final roleColor = _getRoleColor(user.role);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final studentProvider = context.watch<StudentProvider>();
    final assignedClassrooms = studentProvider.classrooms
        .where((c) => c.teacherId == user.id)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
          ),
        ],
      ),
      child: ListTile(
        onTap: widget.isCurrentLoggedAdmin ? null : () => _openEditModal(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: roleColor.withOpacity(0.15),
          backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
          child: user.avatarUrl == null
              ? Text(
                  user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U',
                  style: TextStyle(
                    color: roleColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                )
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                user.fullName,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: roleColor.withOpacity(0.3)),
              ),
              child: Text(
                _getRoleLabel(user.role),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: roleColor,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.email_outlined, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    user.email,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (user.displayPhone != null && user.displayPhone!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.phone_rounded, size: 13, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    user.displayPhone!,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ],

            // Fila de Contraseña visible para el Administrador
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.08) : AppTheme.divider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded, size: 12, color: AppTheme.accent),
                  const SizedBox(width: 5),
                  Text(
                    'Contraseña: ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    user.currentPassword != null
                        ? (_showPassword ? user.currentPassword! : '••••••••')
                        : (widget.isCurrentLoggedAdmin ? 'Tu clave actual' : 'Cifrada en BD'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      fontFamily: (_showPassword && user.currentPassword != null) ? 'monospace' : null,
                      color: isDark ? Colors.white : AppTheme.onBackground,
                    ),
                  ),
                  if (user.currentPassword != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => setState(() => _showPassword = !_showPassword),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          _showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 14,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: user.currentPassword!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Contraseña de ${user.fullName} copiada'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ],
                  if (user.mustChangePassword) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '1er inicio',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (user.hasResetRequest ||
                context.watch<UserProvider>().pendingResetEmails.contains(user.email.toLowerCase())) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.key_rounded, size: 13, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    const Text(
                      'Solicitó nueva contraseña',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => showGeneratePasswordDialog(context, user),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Generar Clave',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (assignedClassrooms.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.school_rounded, size: 13, color: AppTheme.accent),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Sección: ${assignedClassrooms.map((c) => c.shortName).join(', ')}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: widget.isCurrentLoggedAdmin
            ? const Tooltip(
                message: 'Tu cuenta actual',
                child: Icon(Icons.verified_user_rounded, color: AppTheme.primary, size: 20),
              )
            : PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) async {
                  if (value == 'edit_user') {
                    _openEditModal(context);
                  } else if (value == 'generate_password') {
                    showGeneratePasswordDialog(context, user);
                  } else if (value == 'role_profesor') {
                    await context.read<UserProvider>().updateUserRole(user.id, 'profesor');
                  } else if (value == 'role_coordinador') {
                    await context.read<UserProvider>().updateUserRole(user.id, 'coordinador');
                    for (final c in studentProvider.classrooms.where((c) => c.teacherId == user.id)) {
                      await studentProvider.assignTeacherToClassroom(c.id, null);
                    }
                  } else if (value == 'role_administrador') {
                    await context.read<UserProvider>().updateUserRole(user.id, 'administrador');
                    for (final c in studentProvider.classrooms.where((c) => c.teacherId == user.id)) {
                      await studentProvider.assignTeacherToClassroom(c.id, null);
                    }
                  } else if (value == 'toggle_status') {
                    await context.read<UserProvider>().toggleUserStatus(user.id, !user.isActive);
                  } else if (value == 'assign_classroom') {
                    _showAssignSectionDialog(context, studentProvider);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit_user',
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, size: 18, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text(
                          'Editar Datos y Contraseña',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'generate_password',
                    child: Row(
                      children: [
                        const Icon(Icons.key_rounded, size: 18, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Text(
                          user.hasResetRequest ? 'Atender Solicitud de Clave' : 'Restablecer / Generar Clave',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  if (user.role == 'profesor') ...[
                    const PopupMenuItem(
                      value: 'assign_classroom',
                      child: Row(
                        children: [
                          Icon(Icons.assignment_ind_outlined, size: 18, color: AppTheme.primary),
                          SizedBox(width: 8),
                          Text('Asignar a Sección / Salón'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                  ],
                  PopupMenuItem(
                    value: 'role_profesor',
                    child: Row(
                      children: [
                        const Icon(Icons.school_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(user.role == 'profesor' ? '✓ Profesor' : 'Hacer Profesor'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'role_coordinador',
                    child: Row(
                      children: [
                        const Icon(Icons.manage_accounts_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(user.role == 'coordinador' ? '✓ Coordinador' : 'Hacer Coordinador'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'role_administrador',
                    child: Row(
                      children: [
                        const Icon(Icons.security_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(user.role == 'administrador' ? '✓ Administrador' : 'Hacer Administrador'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'toggle_status',
                    child: Row(
                      children: [
                        Icon(
                          user.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                          size: 18,
                          color: user.isActive ? AppTheme.warning : AppTheme.success,
                        ),
                        const SizedBox(width: 8),
                        Text(user.isActive ? 'Desactivar cuenta' : 'Reactivar cuenta'),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showAssignSectionDialog(BuildContext context, StudentProvider studentProvider) {
    final user = widget.user;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Asignar a ${user.fullName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: studentProvider.classrooms.isEmpty
                ? const Text('No hay salones disponibles.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: studentProvider.classrooms.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return ListTile(
                          leading: const Icon(Icons.person_remove_rounded, color: AppTheme.warning),
                          title: const Text('Sin asignación (Desasignar)'),
                          onTap: () async {
                            Navigator.pop(ctx);
                            for (final c in studentProvider.classrooms.where((c) => c.teacherId == user.id)) {
                              await studentProvider.assignTeacherToClassroom(c.id, null);
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Secciones desasignadas para ${user.fullName}')),
                            );
                          },
                        );
                      }
                      final classroom = studentProvider.classrooms[index - 1];
                      final isAssigned = classroom.teacherId == user.id;

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: isAssigned ? AppTheme.accent : AppTheme.primary.withOpacity(0.1),
                          foregroundColor: isAssigned ? Colors.white : AppTheme.primary,
                          child: Text(classroom.section, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        title: Text(classroom.displayName),
                        subtitle: Text(
                          isAssigned
                              ? 'Asignado actualmente a este usuario'
                              : (classroom.teacherName != null
                                  ? 'Actualmente: Prof. ${classroom.teacherName}'
                                  : 'Sin profesor'),
                          style: TextStyle(
                            fontSize: 11,
                            color: isAssigned ? AppTheme.accent : AppTheme.textSecondary,
                            fontWeight: isAssigned ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        trailing: isAssigned
                            ? const Icon(Icons.check_circle_rounded, color: AppTheme.accent)
                            : null,
                        onTap: () async {
                          Navigator.pop(ctx);
                          final ok = await studentProvider.assignTeacherToClassroom(classroom.id, user.id);
                          if (ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppTheme.accent,
                                content: Text('Asignado exitosamente a ${classroom.displayName}'),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }
}

class _EditUserBottomSheet extends StatefulWidget {
  final UserProfile user;

  const _EditUserBottomSheet({required this.user});

  @override
  State<_EditUserBottomSheet> createState() => _EditUserBottomSheetState();
}

class _EditUserBottomSheetState extends State<_EditUserBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  final _newPasswordCtrl = TextEditingController();

  String _phonePrefix = '0414';
  late String _selectedRole;
  String? _selectedClassroomId;
  bool _forcePwdChange = false;
  bool _showCurrentPassword = false;
  bool _obscureNewPassword = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.fullName);
    _selectedRole = widget.user.role;
    _forcePwdChange = widget.user.mustChangePassword;

    // Parse phone prefix and number
    final cleanPhone = widget.user.displayPhone?.replaceAll(RegExp(r'[\s\-\(\)\.]'), '') ?? '';
    if (cleanPhone.length == 11) {
      final prefix = cleanPhone.substring(0, 4);
      if (Validators.venezuelanPhonePrefixes.contains(prefix)) {
        _phonePrefix = prefix;
        _phoneCtrl = TextEditingController(text: cleanPhone.substring(4));
      } else {
        _phoneCtrl = TextEditingController(text: cleanPhone);
      }
    } else {
      _phoneCtrl = TextEditingController(text: cleanPhone);
    }

    // Find current assigned classroom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final classrooms = context.read<StudentProvider>().classrooms;
      for (final c in classrooms) {
        if (c.teacherId == widget.user.id) {
          setState(() => _selectedClassroomId = c.id);
          break;
        }
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final newPwd = _newPasswordCtrl.text.trim();
    if (newPwd.isNotEmpty) {
      final policyError = Validators.validatePasswordPolicy(newPwd);
      if (policyError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(policyError),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    String? fullPhone;
    if (_phoneCtrl.text.trim().isNotEmpty) {
      final raw = _phoneCtrl.text.trim();
      final clean = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
      final combined = clean.length == 7 ? '$_phonePrefix$clean' : raw;
      fullPhone = Validators.formatPhone(combined);
    }

    final success = await context.read<UserProvider>().updateUserDetails(
          userId: widget.user.id,
          fullName: _nameCtrl.text.trim(),
          role: _selectedRole,
          phone: fullPhone,
          newPassword: newPwd.isNotEmpty ? newPwd : null,
          classroomId: _selectedRole == 'profesor' ? _selectedClassroomId : null,
          forcePwdChange: _forcePwdChange,
        );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Usuario ${widget.user.fullName} actualizado exitosamente'),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        final err = context.read<UserProvider>().error ?? 'Error al actualizar usuario';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final classrooms = context.watch<StudentProvider>().classrooms;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
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
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.manage_accounts_rounded, color: AppTheme.accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Administrar Usuario',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          widget.user.email,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Nombre
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'El nombre es obligatorio';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Teléfono con prefijo
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
                      controller: _phoneCtrl,
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
              const SizedBox(height: 14),

              // Rol Selector
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Rol del usuario *',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'profesor', child: Text('Profesor')),
                  DropdownMenuItem(value: 'coordinador', child: Text('Coordinador')),
                  DropdownMenuItem(value: 'administrador', child: Text('Administrador')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _selectedRole = v);
                },
              ),
              const SizedBox(height: 14),

              // Si es profesor: Asignación de aula
              if (_selectedRole == 'profesor') ...[
                DropdownButtonFormField<String>(
                  value: _selectedClassroomId,
                  decoration: const InputDecoration(
                    labelText: 'Salón asignado',
                    prefixIcon: Icon(Icons.class_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Sin aula asignada'),
                    ),
                    ...classrooms.map((c) {
                      return DropdownMenuItem(
                        value: c.id,
                        child: Text(c.displayName),
                      );
                    }),
                  ],
                  onChanged: (v) => setState(() => _selectedClassroomId = v),
                ),
                const SizedBox(height: 14),
              ],

              // Tarjeta de Contraseña Actual
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.08) : AppTheme.divider,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.vpn_key_rounded, size: 16, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Text(
                          'Contraseña actual registrada:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? const Color(0xFFCBD5E1) : AppTheme.onBackground,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.user.currentPassword != null
                                ? (_showCurrentPassword ? widget.user.currentPassword! : '••••••••')
                                : 'No visible (cifrada en Auth)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFamily: (_showCurrentPassword && widget.user.currentPassword != null) ? 'monospace' : null,
                              color: isDark ? Colors.white : AppTheme.onBackground,
                            ),
                          ),
                        ),
                        if (widget.user.currentPassword != null) ...[
                          IconButton(
                            icon: Icon(
                              _showCurrentPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              size: 18,
                              color: AppTheme.accent,
                            ),
                            tooltip: 'Mostrar / Ocultar',
                            onPressed: () => setState(() => _showCurrentPassword = !_showCurrentPassword),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.accent),
                            tooltip: 'Copiar contraseña',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: widget.user.currentPassword!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Contraseña copiada al portapapeles'),
                                  duration: Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Sección para Cambiar Contraseña
              TextFormField(
                controller: _newPasswordCtrl,
                obscureText: _obscureNewPassword,
                decoration: InputDecoration(
                  labelText: 'Asignar nueva contraseña (opcional)',
                  hintText: '8 caracteres seguros',
                  prefixIcon: const Icon(Icons.lock_reset_rounded),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.autorenew_rounded, size: 20),
                        tooltip: 'Generar clave de 8 caracteres',
                        onPressed: () {
                          setState(() {
                            _newPasswordCtrl.text = PasswordManagementService.generateSecurePassword();
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _obscureNewPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Checkbox de forzar cambio en primer inicio
              CheckboxListTile(
                value: _forcePwdChange,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Solicitar que cambie la contraseña en su próximo inicio de sesión',
                  style: TextStyle(fontSize: 12.5),
                ),
                onChanged: (val) => setState(() => _forcePwdChange = val ?? false),
              ),
              const SizedBox(height: 16),

              // Botón Guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Guardar Cambios'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showGeneratePasswordDialog(BuildContext context, UserProfile user) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  String generatedPassword = PasswordManagementService.generateSecurePassword();
  final passwordCtrl = TextEditingController(text: generatedPassword);

  showDialog(
    context: context,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF162032) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isDark ? Colors.white.withOpacity(0.12) : AppTheme.divider,
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.key_rounded,
                    color: AppTheme.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generar Contraseña',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppTheme.onBackground,
                        ),
                      ),
                      Text(
                        user.fullName,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2D42) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.email_outlined, size: 18, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            user.email,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : AppTheme.onBackground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nueva contraseña asignada:',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFCBD5E1) : AppTheme.onBackground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: passwordCtrl,
                          style: TextStyle(
                            color: isDark ? Colors.white : AppTheme.onBackground,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            fontSize: 15,
                            letterSpacing: 1.1,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark ? Colors.white.withOpacity(0.15) : AppTheme.divider,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppTheme.accent, width: 2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Botón para regenerar
                      IconButton.filledTonal(
                        onPressed: () {
                          final newPwd = PasswordManagementService.generateSecurePassword();
                          passwordCtrl.text = newPwd;
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: 'Generar otra contraseña',
                      ),
                      // Botón para copiar al portapapeles
                      IconButton.filledTonal(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: passwordCtrl.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Contraseña copiada al portapapeles'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        tooltip: 'Copiar al portapapeles',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '💡 Al guardar, esta contraseña quedará habilitada para el usuario. Podrás facilitársela para que ingrese de inmediato.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: Text(
                  'Cancelar',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final pwd = passwordCtrl.text.trim();
                  if (pwd.length < 6) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('La contraseña debe tener mínimo 6 caracteres.'),
                        backgroundColor: AppTheme.error,
                      ),
                    );
                    return;
                  }

                  Navigator.of(dialogCtx).pop();

                  final success = await context.read<UserProvider>().assignTemporaryPassword(
                    userId: user.id,
                    email: user.email,
                    newPassword: pwd,
                    currentPhone: user.phone,
                  );

                  if (context.mounted) {
                    if (success) {
                      showPasswordAssignedSuccessDialog(context, user, pwd);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Error al asignar contraseña temporal'),
                          backgroundColor: AppTheme.error,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Guardar y Asignar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

void showPasswordAssignedSuccessDialog(BuildContext context, UserProfile user, String password) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF162032) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 24),
          SizedBox(width: 10),
          Text('Contraseña Asignada', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Se ha asignado la nueva clave a ${user.fullName}.',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white : AppTheme.onBackground),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Usuario: ${user.email}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Contraseña: $password',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accent,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: 'Usuario: ${user.email}\nContraseña: $password'));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Credenciales copiadas al portapapeles'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copiar Credenciales'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Listo'),
        ),
      ],
    ),
  );
}

class _CreateUserBottomSheet extends StatefulWidget {
  const _CreateUserBottomSheet();

  @override
  State<_CreateUserBottomSheet> createState() => _CreateUserBottomSheetState();
}

class _CreateUserBottomSheetState extends State<_CreateUserBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _phonePrefix = '0414';
  String _selectedRole = 'profesor';
  String? _selectedClassroomId;
  bool _obscurePassword = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.text = PasswordManagementService.generateSecurePassword();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    String? fullPhone;
    if (_phoneCtrl.text.trim().isNotEmpty) {
      final raw = _phoneCtrl.text.trim();
      final clean = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
      final combined = clean.length == 7 ? '$_phonePrefix$clean' : raw;
      fullPhone = Validators.formatPhone(combined);
    }

    // Marca de cambio de contraseña obligatorio para el primer inicio de sesión y registro visible para el admin
    final phoneWithFlag = '[FORCE_PWD_CHANGE][PWD:${_passwordCtrl.text.trim()}]${fullPhone ?? ''}';

    final success = await context.read<UserProvider>().createUser(
          email: _emailCtrl.text.trim().toLowerCase(),
          password: _passwordCtrl.text.trim(),
          fullName: _nameCtrl.text.trim(),
          role: _selectedRole,
          phone: phoneWithFlag,
          classroomId: _selectedRole == 'profesor' ? _selectedClassroomId : null,
        );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Usuario ${_nameCtrl.text.trim()} creado exitosamente'),
            backgroundColor: AppTheme.success,
          ),
        );
      } else {
        final err = context.read<UserProvider>().error ?? 'Error al crear usuario';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final classrooms = context.watch<StudentProvider>().classrooms;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
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
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_add_rounded, color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Crear Nuevo Usuario',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Text(
                        'Completa los datos del profesor o coordinador',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Nombre
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                  hintText: 'Ej: Carlos Pérez',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'El nombre es obligatorio';
                  if (v.trim().length < 3) return 'Ingresa nombre y apellido';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Correo
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico *',
                  hintText: 'ejemplo@correo.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) => Validators.validateEmail(v, required: true),
              ),
              const SizedBox(height: 14),

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
                      controller: _phoneCtrl,
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
              const SizedBox(height: 14),

              // Rol Selector
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Rol del usuario *',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'profesor',
                    child: Text('Profesor'),
                  ),
                  DropdownMenuItem(
                    value: 'coordinador',
                    child: Text('Coordinador'),
                  ),
                  DropdownMenuItem(
                    value: 'administrador',
                    child: Text('Administrador'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _selectedRole = v);
                },
              ),
              const SizedBox(height: 14),

              // Contraseña
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Contraseña inicial (8 caracteres) *',
                  hintText: '8 caracteres seguros',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.autorenew_rounded, size: 20),
                        tooltip: 'Generar nueva clave de 8 caracteres',
                        onPressed: () {
                          setState(() {
                            _passwordCtrl.text = PasswordManagementService.generateSecurePassword();
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ],
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'La contraseña es obligatoria';
                  if (v.trim().length < 8) return 'Debe tener al menos 8 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Si es profesor: Asignar salón inicial
              if (_selectedRole == 'profesor') ...[
                DropdownButtonFormField<String>(
                  value: _selectedClassroomId,
                  decoration: const InputDecoration(
                    labelText: 'Asignar a un salón (opcional)',
                    prefixIcon: Icon(Icons.class_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Sin salón asignado por ahora'),
                    ),
                    ...classrooms.map((c) {
                      return DropdownMenuItem(
                        value: c.id,
                        child: Text(c.displayName),
                      );
                    }),
                  ],
                  onChanged: (v) => setState(() => _selectedClassroomId = v),
                ),
                const SizedBox(height: 14),
              ],

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Crear Usuario'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
