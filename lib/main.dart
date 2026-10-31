import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/constants/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'providers/auth_provider.dart';
import 'providers/student_provider.dart';
import 'providers/attendance_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/user_provider.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Background Firebase init error: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Handle uncaught Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Uncaught Flutter error: ${details.exception}');
  };

  // Set preferred orientations
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (e) {
    debugPrint('Orientation error: $e');
  }

  // Initialize intl for Spanish locale
  try {
    await initializeDateFormatting('es', null);
  } catch (e) {
    debugPrint('Date formatting init error: $e');
  }

  // Initialize Firebase Cloud Messaging
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // Initialize Supabase
  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
      debug: false,
    );
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }

  runApp(const ConsoApp());
}

class ConsoApp extends StatelessWidget {
  const ConsoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
      ],
      child: Builder(
        builder: (context) {
          final authProvider = context.watch<AuthProvider>();
          final themeProvider = context.watch<ThemeProvider>();
          final router = AppRouter.createRouter(authProvider);

          return MaterialApp.router(
            title: 'CNSC - Control de Asistencias',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            routerConfig: router,
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              // Escala de fuentes del sistema operativo (Android / iOS)
              final systemScale = mediaQuery.textScaler.scale(1.0);

              // Si el teléfono tiene configurada una fuente grande (> 1.05, p. ej. en Samsung A37),
              // se permite únicamente un incremento sutil de ~2 píxeles (factor 1.10 en fuentes de 14-16px).
              // Si la fuente del sistema es normal (<= 1.05), se mantiene obligada en 1.0.
              // Esto garantiza legibilidad sin romper componentes ni ocultar información.
              final effectiveScaler = systemScale > 1.05
                  ? const TextScaler.linear(1.10)
                  : const TextScaler.linear(1.0);

              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: effectiveScaler,
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
