import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/presentation/screens/auth/login_screen.dart';
import 'package:contro_asistencias/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:contro_asistencias/presentation/screens/students/classrooms_screen.dart';
import 'package:contro_asistencias/presentation/screens/students/students_list_screen.dart';
import 'package:contro_asistencias/presentation/screens/students/student_detail_screen.dart';
import 'package:contro_asistencias/presentation/screens/students/add_student_screen.dart';
import 'package:contro_asistencias/presentation/screens/attendance/attendance_screen.dart';
import 'package:contro_asistencias/presentation/screens/reports/reports_screen.dart';
import 'package:contro_asistencias/presentation/screens/justifications/justifications_screen.dart';
import 'package:contro_asistencias/presentation/screens/profile/profile_screen.dart';
import 'package:contro_asistencias/presentation/screens/users/users_management_screen.dart';
import 'package:contro_asistencias/presentation/screens/dashboard/main_scaffold.dart';

class AppRouter {
  static GoRouter? _router;
  static AuthProvider? _cachedAuthProvider;

  static GoRouter createRouter(AuthProvider authProvider) {
    if (_router != null && _cachedAuthProvider == authProvider) {
      return _router!;
    }
    _cachedAuthProvider = authProvider;
    return _router = GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final isAuthenticated = authProvider.isAuthenticated;
        final isLoginRoute = state.matchedLocation == '/login';

        if (!isAuthenticated && !isLoginRoute) return '/login';
        if (isAuthenticated && isLoginRoute) return '/dashboard';

        // Profesores solo acceden a Dashboard, su Salón asignado, Justificativos de su salón y Perfil
        if (isAuthenticated && authProvider.isTeacher) {
          if (state.matchedLocation == '/classrooms' ||
              state.matchedLocation.startsWith('/reports') ||
              state.matchedLocation.startsWith('/users')) {
            return '/dashboard';
          }
        }
        return null;
      },
      refreshListenable: authProvider,
      routes: [
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (context, state) => const LoginScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) => MainScaffold(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              name: 'dashboard',
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: '/classrooms',
              name: 'classrooms',
              builder: (context, state) => const ClassroomsScreen(),
              routes: [
                GoRoute(
                  path: ':classroomId/students',
                  name: 'students',
                  builder: (context, state) => StudentsListScreen(
                    classroomId: state.pathParameters['classroomId']!,
                  ),
                  routes: [
                    GoRoute(
                      path: 'add',
                      name: 'add-student',
                      builder: (context, state) => AddStudentScreen(
                        classroomId: state.pathParameters['classroomId']!,
                      ),
                    ),
                    GoRoute(
                      path: ':studentId',
                      name: 'student-detail',
                      builder: (context, state) => StudentDetailScreen(
                        studentId: state.pathParameters['studentId']!,
                        classroomId: state.pathParameters['classroomId']!,
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: ':classroomId/attendance',
                  name: 'attendance',
                  builder: (context, state) => AttendanceScreen(
                    classroomId: state.pathParameters['classroomId']!,
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/justifications',
              name: 'justifications',
              builder: (context, state) => const JustificationsScreen(),
            ),
            GoRoute(
              path: '/reports',
              name: 'reports',
              builder: (context, state) => const ReportsScreen(),
            ),
            GoRoute(
              path: '/profile',
              name: 'profile',
              builder: (context, state) => const ProfileScreen(),
            ),
            GoRoute(
              path: '/users',
              name: 'users',
              builder: (context, state) => const UsersManagementScreen(),
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Text('Página no encontrada: ${state.error}'),
        ),
      ),
    );
  }
}
