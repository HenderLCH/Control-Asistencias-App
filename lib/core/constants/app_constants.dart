class AppConstants {
  static const String appName = 'Contro-Asistencias';
  static const String institutionName =
      'Colegio Nuestra Señora de la Consolación de Táriba';
  static const String institutionLocation = 'Estado Táchira - Venezuela';
  static const String institutionShort = 'CNSC Táriba';
  static const String logoAsset = 'assets/images/logo.png';

  // Grades
  static const List<String> grades = [
    '1er Grado',
    '2do Grado',
    '3er Grado',
    '4to Grado',
    '5to Grado',
    '6to Grado',
  ];

  static const List<String> sections = ['A', 'B'];

  // Roles
  static const String roleAdmin = 'administrador';
  static const String roleCoordinator = 'coordinador';
  static const String roleTeacher = 'profesor';

  // Attendance status
  static const String statusPresent = 'presente';
  static const String statusAbsent = 'ausente';
  static const String statusLate = 'tardanza';
  static const String statusJustified = 'justificado';

  // Report types
  static const String reportDaily = 'diario';
  static const String reportWeekly = 'semanal';
  static const String reportBiweekly = 'quincenal';
  static const String reportMonthly = 'mensual';

  // Shared prefs keys
  static const String keyUserRole = 'user_role';
  static const String keyUserId = 'user_id';
  static const String keyUserName = 'user_name';
}
