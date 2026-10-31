import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/providers/student_provider.dart';
import 'package:contro_asistencias/providers/attendance_provider.dart';
import 'package:contro_asistencias/providers/theme_provider.dart';
import 'package:contro_asistencias/presentation/widgets/attendance/tardiness_notification_badge.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/constants/app_constants.dart';
import 'package:contro_asistencias/data/models/classroom.dart';
import 'package:contro_asistencias/data/models/user_profile.dart';
import 'package:contro_asistencias/presentation/widgets/common/logo_loading_indicator.dart';
import 'package:contro_asistencias/core/services/notification_service.dart';
import 'package:contro_asistencias/presentation/widgets/auth/change_password_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sProv = context.read<StudentProvider>();
      final aProv = context.read<AttendanceProvider>();
      final authProv = context.read<AuthProvider>();
      
      // Solicitar permisos de notificación una vez la app está en pantalla
      NotificationService().requestPermissions();

      // Suscribir al canal de alertas Firebase para administradores y coordinadores
      if (authProv.isAdmin || authProv.isCoordinator) {
        NotificationService().subscribeToAdminAlerts();
      } else {
        NotificationService().unsubscribeFromAdminAlerts();
      }

      // Si el usuario debe cambiar su contraseña obligatoriamente (primer inicio de sesión o clave temporal)
      if (authProv.currentUser != null && authProv.currentUser!.mustChangePassword && mounted) {
        ChangePasswordDialog.show(context, isForced: true);
      } else if (authProv.shouldShowWelcome && mounted) {
        authProv.markWelcomeShown();
        _showWelcomeModal(context, authProv.currentUser);
      }

      // Cargar salones según el rol:
      // - Profesor: solo sus salones asignados
      // - Admin / Coordinador: todos los salones
      if (authProv.isTeacher && authProv.currentUser != null) {
        await sProv.loadClassroomsForTeacher(authProv.currentUser!.id);
      } else {
        await sProv.loadClassrooms();
      }

      // Iniciar escucha en tiempo real de eventos de asistencia (completado / modificado)
      aProv.initializeRealtimeNotifications(
        isEligibleRecipient: () => authProv.isAdmin || authProv.isCoordinator,
      );

      await aProv.loadTardinessAlerts();
      if (mounted) {
        await aProv.checkCompletedClassroomsForToday(sProv.classrooms);
      }
    });
  }

  void _showWelcomeModal(BuildContext context, UserProfile? user) {
    if (!mounted) return;
    String welcomeTitle;
    String subtitle;
    IconData icon;
    Color accentColor;

    if (user?.role == 'administrador') {
      welcomeTitle = 'Bienvenido Administrador';
      subtitle = 'Panel de Gestión y Control Institucional';
      icon = Icons.admin_panel_settings_rounded;
      accentColor = AppTheme.primary;
    } else if (user?.role == 'coordinador') {
      welcomeTitle = 'Bienvenido/a Coord. ${user?.fullName ?? ""}';
      subtitle = 'Supervisión General de Asistencias y Salones';
      icon = Icons.supervised_user_circle_rounded;
      accentColor = const Color(0xFF0284C7);
    } else if (user?.role == 'profesor') {
      welcomeTitle = 'Bienvenido/a Prof. ${user?.fullName ?? ""}';
      subtitle = 'Control de Asistencias de tus Salones';
      icon = Icons.school_rounded;
      accentColor = const Color(0xFF10B981);
    } else {
      welcomeTitle = 'Bienvenido/a ${user?.fullName ?? ""}';
      subtitle = 'Colegio Nuestra Señora de la Consolación';
      icon = Icons.person_rounded;
      accentColor = AppTheme.primary;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 1800), () {
          if (ctx.mounted) {
            Navigator.of(ctx, rootNavigator: true).pop();
          }
        });

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF162032) : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: accentColor.withOpacity(0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.2),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accentColor, size: 30),
                ),
                const SizedBox(height: 14),
                Text(
                  welcomeTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppTheme.onBackground,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final students = context.watch<StudentProvider>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 180,
            floating: false,
            pinned: true,
            backgroundColor: AppTheme.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppTheme.cardGradient),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Logo y nombre del colegio arriba sobre el bienvenido (sin ubicación)
                        Row(
                          children: [
                            Image.asset(
                              AppConstants.logoAsset,
                              width: 30,
                              height: 30,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                AppConstants.institutionName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.white.withOpacity(0.2),
                              backgroundImage:
                                  auth.currentUser?.avatarUrl != null
                                      ? NetworkImage(auth.currentUser!.avatarUrl!)
                                      : null,
                              child: auth.currentUser?.avatarUrl == null
                                  ? Text(
                                      auth.currentUser?.fullName
                                              .isNotEmpty ==
                                              true
                                          ? auth.currentUser!.fullName[0]
                                              .toUpperCase()
                                          : 'U',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 18,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bienvenido, 👋',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    auth.currentUser?.fullName ?? 'Usuario',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppTheme.accent.withOpacity(0.5),
                                ),
                              ),
                              child: Text(
                                _getRoleLabel(auth.currentUser?.role ?? ''),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const TardinessNotificationBadge(isLightOnDark: true),
                            const SizedBox(width: 4),
                            Consumer<ThemeProvider>(
                              builder: (context, themeProvider, _) {
                                final isDark = Theme.of(context).brightness == Brightness.dark;
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => themeProvider.toggleTheme(),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.18),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Icon(
                                        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                        color: isDark ? const Color(0xFFFFD600) : Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Stats Row (Solo Administradores y Coordinadores)
                if (auth.isAdmin || auth.isCoordinator) ...[
                  _StatsRow(classrooms: students.classrooms),
                  const SizedBox(height: 24),
                ],

                // Quick Actions (Solo Administradores y Coordinadores)
                if (auth.isAdmin || auth.isCoordinator) ...[
                  _SectionTitle(title: 'Acciones Rápidas'),
                  const SizedBox(height: 12),
                  _QuickActionsGrid(context: context, auth: auth),
                  const SizedBox(height: 24),
                ],

                // Today's date / Classrooms Section
                _SectionTitle(
                  title: auth.isTeacher ? 'Mi Salón Asignado' : 'Salones',
                  subtitle: auth.isTeacher
                      ? 'Pasa asistencia diaria de tus alumnos'
                      : 'Selecciona para pasar asistencia',
                ),
                const SizedBox(height: 12),

                // Classrooms list
                if (students.isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: LogoLoadingIndicator(
                        size: 48,
                        message: 'Cargando salones...',
                      ),
                    ),
                  )
                else if (students.classrooms.isEmpty)
                  _EmptyClassrooms(isAdmin: auth.isAdmin)
                else
                  ...students.classrooms
                      .asMap()
                      .entries
                      .map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ClassroomCard(
                            classroom: entry.value,
                            index: entry.key,
                          ),
                        ),
                      ),

                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'administrador':
        return 'Admin';
      case 'coordinador':
        return 'Coord.';
      case 'profesor':
        return 'Profesor';
      default:
        return role;
    }
  }
}

class _StatsRow extends StatelessWidget {
  final List<Classroom> classrooms;

  const _StatsRow({required this.classrooms});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Salones',
            value: '${classrooms.length}',
            icon: Icons.class_rounded,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Grados',
            value: '6',
            icon: Icons.school_rounded,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Secciones',
            value: 'A & B',
            icon: Icons.groups_rounded,
            color: AppTheme.secondary,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2);
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppTheme.onBackground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionTitle({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : AppTheme.onBackground,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  final BuildContext context;
  final AuthProvider auth;

  const _QuickActionsGrid({required this.context, required this.auth});

  @override
  Widget build(BuildContext context) {
    final isCoordinator = auth.isCoordinator && !auth.isAdmin;
    final actions = isCoordinator
        ? [
            _ActionCard(
              icon: Icons.class_rounded,
              label: 'Ver\nSalones',
              color: AppTheme.primary,
              onTap: () => context.go('/classrooms'),
            ),
            _ActionCard(
              icon: Icons.assignment_turned_in_rounded,
              label: 'Sección\nJustificativos',
              color: const Color(0xFFF59E0B),
              onTap: () => context.go('/justifications'),
            ),
            _ActionCard(
              icon: Icons.bar_chart_rounded,
              label: 'Ver\nReportes',
              color: const Color(0xFF10B981),
              onTap: () => context.go('/reports'),
            ),
          ]
        : [
            _ActionCard(
              icon: Icons.assignment_turned_in_rounded,
              label: 'Sección\nJustificativos',
              color: const Color(0xFF8B5CF6),
              onTap: () => context.go('/justifications'),
            ),
            _ActionCard(
              icon: Icons.person_add_rounded,
              label: 'Agregar\nEstudiante',
              color: AppTheme.accent,
              onTap: () => context.go('/classrooms'),
            ),
            _ActionCard(
              icon: Icons.bar_chart_rounded,
              label: 'Ver\nReportes',
              color: const Color(0xFF10B981),
              onTap: () => context.go('/reports'),
            ),
            _ActionCard(
              icon: Icons.people_rounded,
              label: 'Gestionar\nUsuarios',
              color: const Color(0xFFF59E0B),
              onTap: () => context.go('/users'),
            ),
          ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: actions,
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppTheme.onBackground,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassroomCard extends StatelessWidget {
  final Classroom classroom;
  final int index;

  const _ClassroomCard({required this.classroom, required this.index});

  @override
  Widget build(BuildContext context) {
    final gradeColors = [
      AppTheme.primary,
      AppTheme.accent,
      AppTheme.secondary,
      AppTheme.info,
      const Color(0xFFFF6B35),
      const Color(0xFF8BC34A),
    ];

    final gradeIndex = AppConstants.grades.indexOf(classroom.grade);
    final color = gradeColors[gradeIndex >= 0 ? gradeIndex % gradeColors.length : 0];

    final attendanceProvider = context.watch<AttendanceProvider>();
    final isCompletedToday = attendanceProvider.completedClassroomNamesToday.contains(classroom.displayName);

    return GestureDetector(
      onTap: () {
        context.go('/classrooms/${classroom.id}/attendance');
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCompletedToday
                ? const Color(0xFF10B981).withOpacity(0.35)
                : Theme.of(context).dividerColor,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  classroom.section,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    classroom.grade,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'Sección ${classroom.section}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (isCompletedToday) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF10B981)),
                              SizedBox(width: 3),
                              Text(
                                'Tomada',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (classroom.teacherName != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline_rounded,
                          size: 12,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            classroom.teacherName!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Botón para ver la lista de estudiantes y sus perfiles
            Tooltip(
              message: 'Ver estudiantes del salón',
              child: InkWell(
                onTap: () {
                  context.go('/classrooms/${classroom.id}/students');
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
                  ),
                  child: const Icon(
                    Icons.people_alt_rounded,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Botón interactivo de Pasar Lista o Editar
            InkWell(
              onTap: () {
                context.go('/classrooms/${classroom.id}/attendance');
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isCompletedToday
                      ? const Color(0xFF0284C7).withOpacity(0.1)
                      : AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isCompletedToday
                        ? const Color(0xFF0284C7).withOpacity(0.3)
                        : AppTheme.accent.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCompletedToday ? Icons.edit_note_rounded : Icons.how_to_reg_rounded,
                      size: 16,
                      color: isCompletedToday ? const Color(0xFF0284C7) : AppTheme.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCompletedToday ? 'Editar' : 'Pasar lista',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: isCompletedToday ? const Color(0xFF0284C7) : AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ).animate(delay: Duration(milliseconds: 100 * index)).fadeIn().slideX(begin: 0.1),
    );
  }
}

class _EmptyClassrooms extends StatelessWidget {
  final bool isAdmin;

  const _EmptyClassrooms({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.class_outlined,
            size: 56,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 16),
          const Text(
            'No hay salones configurados',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.onBackground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isAdmin
                ? 'El administrador puede crear salones desde el panel'
                : 'Contacta al administrador para configurar los salones',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
