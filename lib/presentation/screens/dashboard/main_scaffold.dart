import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';

class MainScaffold extends StatefulWidget {
  final Widget child;

  const MainScaffold({super.key, required this.child});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  static const List<_NavItem> _adminNavItems = [
    _NavItem(
      label: 'Inicio',
      icon: Icons.home_rounded,
      activeIcon: Icons.home_rounded,
      route: '/dashboard',
    ),
    _NavItem(
      label: 'Salones',
      icon: Icons.class_outlined,
      activeIcon: Icons.class_rounded,
      route: '/classrooms',
    ),
    _NavItem(
      label: 'Justificativos',
      icon: Icons.assignment_turned_in_outlined,
      activeIcon: Icons.assignment_turned_in_rounded,
      route: '/justifications',
    ),
    _NavItem(
      label: 'Reportes',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart_rounded,
      route: '/reports',
    ),
    _NavItem(
      label: 'Perfil',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      route: '/profile',
    ),
  ];

  static const List<_NavItem> _teacherNavItems = [
    _NavItem(
      label: 'Inicio',
      icon: Icons.home_rounded,
      activeIcon: Icons.home_rounded,
      route: '/dashboard',
    ),
    _NavItem(
      label: 'Justificativos',
      icon: Icons.assignment_turned_in_outlined,
      activeIcon: Icons.assignment_turned_in_rounded,
      route: '/justifications',
    ),
    _NavItem(
      label: 'Perfil',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      route: '/profile',
    ),
  ];

  int _getIndexFromRoute(String location, bool isTeacher) {
    if (isTeacher) {
      if (location.startsWith('/justifications')) return 1;
      if (location.startsWith('/profile')) return 2;
      return 0;
    }
    if (location.startsWith('/classrooms')) return 1;
    if (location.startsWith('/justifications')) return 2;
    if (location.startsWith('/reports')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isTeacher = auth.isTeacher;
    final navItems = isTeacher ? _teacherNavItems : _adminNavItems;

    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _getIndexFromRoute(location, isTeacher);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(navItems.length, (index) {
                final item = navItems[index];
                final isSelected = index == currentIndex;
                return _NavBarItem(
                  label: item.label,
                  icon: item.icon,
                  activeIcon: item.activeIcon,
                  isSelected: isSelected,
                  onTap: () => context.go(item.route),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
  });
}

class _NavBarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : AppTheme.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? activeColor : inactiveColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
