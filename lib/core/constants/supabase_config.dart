class SupabaseConfig {
  // Credenciales inyectadas en build time via:
  //   flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info --dart-define-from-file=dart_defines/prod.json
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mkhcmfjyowketdahadvt.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_fmS5vAc6n1gspsDUhE7-1w_yqQPAfpf',
  );
  static const String adminServiceEmail = String.fromEnvironment(
    'ADMIN_SERVICE_EMAIL',
    defaultValue: '',
  );
  static const String adminServicePass = String.fromEnvironment(
    'ADMIN_SERVICE_PASS',
    defaultValue: '',
  );

  // Versión actual de la aplicación para control de versiones
  static const String appVersion = '1.2.0';

  // Table names
  static const String tableProfiles = 'profiles';
  static const String tableStudents = 'students';
  static const String tableClassrooms = 'classrooms';
  static const String tableAttendance = 'attendance';
  static const String tableAttendanceSessions = 'attendance_sessions';
}
