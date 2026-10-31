import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:contro_asistencias/providers/attendance_provider.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/providers/user_provider.dart';
import 'package:contro_asistencias/providers/student_provider.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/data/models/attendance_record.dart';
import 'package:contro_asistencias/data/models/user_profile.dart';
import 'package:contro_asistencias/presentation/screens/users/users_management_screen.dart';

class TardinessNotificationBadge extends StatelessWidget {
  final bool isLightOnDark;

  const TardinessNotificationBadge({
    super.key,
    this.isLightOnDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Only Admin and Coordinator receive these notifications
    if (!auth.isAdmin && !auth.isCoordinator) {
      return const SizedBox.shrink();
    }

    final attendance = context.watch<AttendanceProvider>();
    final userProvider = context.watch<UserProvider>();
    final totalAlerts = attendance.totalAlertsCount;
    final citationsCount = attendance.citationsCount;

    final pendingPasswordUsers = auth.isAdmin
        ? userProvider.users.where((u) =>
            u.hasResetRequest ||
            userProvider.pendingResetEmails.contains(u.email.toLowerCase())
          ).toList()
        : <UserProfile>[];

    final passwordCount = pendingPasswordUsers.length;
    final totalCount = totalAlerts + passwordCount;

    final badgeColor = citationsCount > 0
        ? const Color(0xFFEF4444) // Rojo alerta urgente
        : const Color(0xFFF59E0B); // Ámbar preventiva / contraseña

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showTardinessAlertsModal(context),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isLightOnDark
                      ? Colors.white.withOpacity(0.18)
                      : (citationsCount > 0
                          ? const Color(0xFFEF4444).withOpacity(0.15)
                          : (totalCount > 0
                              ? const Color(0xFFF59E0B).withOpacity(0.15)
                              : Theme.of(context).cardColor)),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isLightOnDark
                        ? Colors.white.withOpacity(0.3)
                        : (citationsCount > 0
                            ? const Color(0xFFEF4444).withOpacity(0.4)
                            : (totalCount > 0
                                ? const Color(0xFFF59E0B).withOpacity(0.4)
                                : Theme.of(context).dividerColor)),
                  ),
                ),
                child: Icon(
                  citationsCount > 0
                      ? Icons.notifications_active_rounded
                      : (totalCount > 0
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_outlined),
                  color: isLightOnDark
                      ? Colors.white
                      : (citationsCount > 0
                          ? const Color(0xFFEF4444)
                          : (totalCount > 0
                              ? const Color(0xFFF59E0B)
                              : Theme.of(context).iconTheme.color)),
                  size: 20,
                ),
              ),
              if (totalCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: badgeColor.withOpacity(0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Center(
                      child: Text(
                        totalCount > 99 ? '99+' : '$totalCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                   .scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 800.ms),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showTardinessAlertsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _TardinessAlertsSheet(),
    );
  }
}

class _TardinessAlertsSheet extends StatefulWidget {
  const _TardinessAlertsSheet();

  @override
  State<_TardinessAlertsSheet> createState() => _TardinessAlertsSheetState();
}

class _TardinessAlertsSheetState extends State<_TardinessAlertsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attendance = context.watch<AttendanceProvider>();
    final userProvider = context.watch<UserProvider>();
    final auth = context.watch<AuthProvider>();
    final citations = attendance.citations;
    final warnings = attendance.warnings;

    final pendingPasswordUsers = auth.isAdmin
        ? userProvider.users.where((u) =>
            u.hasResetRequest ||
            userProvider.pendingResetEmails.contains(u.email.toLowerCase())
          ).toList()
        : <UserProfile>[];

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 4),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Color(0xFFEF4444),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Centro de Notificaciones',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Tardanzas, citaciones y solicitudes',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    attendance.loadTardinessAlerts();
                    userProvider.loadUsers();
                    attendance.checkCompletedClassroomsForToday(context.read<StudentProvider>().classrooms);
                  },
                  tooltip: 'Refrescar',
                  icon: attendance.isLoadingAlerts || userProvider.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),

          // Sección de solicitudes de cambio de contraseña para el Administrador
          if (pendingPasswordUsers.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.key_rounded, color: Color(0xFFF59E0B), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Solicitudes de Contraseña (${pendingPasswordUsers.length})',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFF59E0B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...pendingPasswordUsers.map((user) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text(user.email, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            showGeneratePasswordDialog(context, user);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Generar Clave', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),

          // Salones con asistencia completada hoy para Coordinador y Administrador
          if (attendance.completedClassroomNamesToday.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Asistencias Completadas Hoy (${attendance.completedClassroomNamesToday.length})',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF10B981)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: attendance.completedClassroomNamesToday.map((name) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '✓ $name',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF10B981)),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),

          // Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🚨 Citar Rep.'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${citations.length}',
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('⚠️ Preventiva'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${warnings.length}',
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Citar Representante (>= 3 tardanzas)
                _AlertsList(
                  alerts: citations,
                  emptyText: 'No hay estudiantes que hayan alcanzado 3 tardanzas.',
                  isCitationTab: true,
                ),

                // Tab 2: Preventiva (2 tardanzas)
                _AlertsList(
                  alerts: warnings,
                  emptyText: 'No hay estudiantes con 2 tardanzas en este momento.',
                  isCitationTab: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertsList extends StatelessWidget {
  final List<TardinessAlert> alerts;
  final String emptyText;
  final bool isCitationTab;

  const _AlertsList({
    required this.alerts,
    required this.emptyText,
    required this.isCitationTab,
  });

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isCitationTab ? Icons.check_circle_outline_rounded : Icons.thumb_up_alt_outlined,
                size: 56,
                color: isCitationTab ? AppTheme.success : AppTheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                emptyText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        final alert = alerts[index];
        final alertColor = isCitationTab
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: alertColor.withOpacity(0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: alertColor.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Student + Status Badge
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: alertColor.withOpacity(0.12),
                      child: Text(
                        alert.studentName.isNotEmpty ? alert.studentName[0].toUpperCase() : 'E',
                        style: TextStyle(
                          color: alertColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert.studentName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  alert.classroomDisplayName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                              if (alert.cedula.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  'C.I: ${alert.cedula}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: alertColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: alertColor.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${alert.lateCount}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: alertColor,
                              height: 1,
                            ),
                          ),
                          Text(
                            alert.lateCount == 1 ? 'tardanza' : 'tardanzas',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: alertColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Alert message banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: alertColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCitationTab ? Icons.assignment_late_rounded : Icons.info_outline_rounded,
                        color: alertColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isCitationTab
                              ? '🚨 Acción requerida: Citar al representante por acumular ${alert.lateCount} tardanzas.'
                              : '⚠️ Aviso preventivo: A 1 tardanza de citación (lleva 2 acumuladas).',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: alertColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Representative Info & Action
                if (alert.parentName != null || alert.parentPhone != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.family_restroom_rounded, size: 16, color: AppTheme.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${alert.parentName ?? 'Representante'}${alert.parentPhone != null ? ' • ${alert.parentPhone}' : ''}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ),
                      if (alert.parentPhone != null)
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: alert.parentPhone!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Teléfono copiado: ${alert.parentPhone}'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy_rounded, size: 14, color: AppTheme.primary),
                                SizedBox(width: 4),
                                Text(
                                  'Copiar',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Dates of late arrivals
                if (alert.lateDates.isNotEmpty)
                  Text(
                    'Fechas registradas: ${alert.lateDates.take(4).map((d) => DateFormat('dd/MM/yyyy').format(d)).join(', ')}${alert.lateDates.length > 4 ? '...' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
          ),
        ).animate(delay: Duration(milliseconds: index * 40)).fadeIn().slideY(begin: 0.1);
      },
    );
  }
}
