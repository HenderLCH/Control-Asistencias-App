import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:contro_asistencias/core/constants/supabase_config.dart';
import 'package:contro_asistencias/data/models/user_profile.dart';
import 'package:contro_asistencias/core/services/password_management_service.dart';

class AuthProvider extends ChangeNotifier {
  UserProfile? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  bool _shouldShowWelcome = false;

  UserProfile? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;
  bool get shouldShowWelcome => _shouldShowWelcome;

  void markWelcomeShown() {
    _shouldShowWelcome = false;
  }

  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isDirector => _currentUser?.isDirector ?? false;
  bool get isCoordinator => _currentUser?.isCoordinator ?? false;
  bool get isTeacher => _currentUser?.isTeacher ?? false;
  bool get canManageData => isAdmin;
  bool get canAssignTeachers => isAdmin || isCoordinator;

  bool _isTempLogin = false;
  static const String _explicitLoginEmailKey = 'cnsc_explicit_login_email';
  static const String _explicitLoginUidKey = 'cnsc_explicit_login_uid';
  static const String _persistedUserJsonKey = 'cnsc_persisted_user_json';
  static const String rememberMeKey = 'cnsc_remember_me';
  static const String savedEmailKey = 'cnsc_saved_email';
  static const String savedPasswordKey = 'cnsc_saved_password';

  final SupabaseClient _supabase = Supabase.instance.client;

  AuthProvider() {
    _initAuth();
  }

  void _initAuth() {
    _supabase.auth.onAuthStateChange.listen((event) async {
      if (_isTempLogin) return;
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.userUpdated) {
        await _loadUserProfile(event.session?.user);
      } else if (event.event == AuthChangeEvent.signedOut) {
        if (!_isTempLogin) {
          _currentUser = null;
          notifyListeners();
        }
      }
    });

    // Check current session or persisted session ("Recordarme")
    final currentSession = _supabase.auth.currentSession;
    if (currentSession != null) {
      _loadUserProfile(currentSession.user);
    } else {
      _restorePersistedSession();
    }
  }

  Future<void> _restorePersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(rememberMeKey) ?? true;
      if (!remember) return;

      final rawJson = prefs.getString(_persistedUserJsonKey);
      if (rawJson == null || rawJson.isEmpty) return;

      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final restoredUser = UserProfile.fromMap(map);
      final adminEmail = SupabaseConfig.adminServiceEmail.trim().toLowerCase();
      final explicitEmail = prefs.getString(_explicitLoginEmailKey)?.toLowerCase();

      if (adminEmail.isNotEmpty &&
          restoredUser.email.trim().toLowerCase() == adminEmail &&
          explicitEmail != adminEmail) {
        await prefs.remove(_persistedUserJsonKey);
        return;
      }

      _isTempLogin = true;
      _currentUser = restoredUser;
      notifyListeners();

      // Refrescar perfil en segundo plano desde Supabase para mantener rol/datos al día
      final jwt = await PasswordManagementService.getAdminJwt();
      if (jwt != null && !restoredUser.id.startsWith('temp_')) {
        final resp = await http.get(
          Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?id=eq.${restoredUser.id}&select=*'),
          headers: {
            'apikey': SupabaseConfig.supabaseAnonKey,
            'Authorization': 'Bearer $jwt',
          },
        );
        if (resp.statusCode == 200) {
          final list = jsonDecode(resp.body) as List;
          if (list.isNotEmpty) {
            final freshMap = {
              ...(list.first as Map<String, dynamic>),
              'email': restoredUser.email,
            };
            final freshUser = UserProfile.fromMap(freshMap);
            if (!freshUser.isActive) {
              await signOut();
              return;
            }
            _currentUser = freshUser;
            await prefs.setString(_persistedUserJsonKey, jsonEncode(freshUser.toMap()));
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('Error restoring persisted session: $e');
    }
  }

  Future<void> _persistCurrentUserIfRemembered() async {
    if (_currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(rememberMeKey) ?? true;
      if (remember) {
        await prefs.setString(_persistedUserJsonKey, jsonEncode(_currentUser!.toMap()));
      } else {
        await prefs.remove(_persistedUserJsonKey);
      }
    } catch (_) {}
  }

  Future<void> _loadUserProfile(User? user) async {
    if (user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final explicitEmail = prefs.getString(_explicitLoginEmailKey)?.toLowerCase();
      final sessionEmail = (user.email ?? '').trim().toLowerCase();
      final adminEmail = SupabaseConfig.adminServiceEmail.trim().toLowerCase();

      // Protección crítica: Si un teléfono de profesor quedó con la sesión de servicio admin
      // guardada por versiones previas (cuando usaron clave temporal), cerrar esa sesión de inmediato.
      if (adminEmail.isNotEmpty &&
          sessionEmail == adminEmail &&
          explicitEmail != adminEmail) {
        debugPrint('Detected leaked admin service session on non-admin device. Signing out...');
        await _supabase.auth.signOut();
        _currentUser = null;
        notifyListeners();
        return;
      }

      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data != null) {
        _currentUser = UserProfile.fromMap({...data, 'email': user.email ?? ''});
      } else {
        // Fallback consultando con JWT administrativo por si RLS bloqueó la lectura
        final jwt = await PasswordManagementService.getAdminJwt();
        if (jwt != null) {
          final resp = await http.get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?id=eq.${user.id}&select=*'),
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
              'Authorization': 'Bearer $jwt',
            },
          );
          if (resp.statusCode == 200) {
            final list = jsonDecode(resp.body) as List;
            if (list.isNotEmpty) {
              _currentUser = UserProfile.fromMap({
                ...(list.first as Map<String, dynamic>),
                'email': user.email ?? '',
              });
              notifyListeners();
              return;
            }
          }
        }

        // Create profile if missing
        final role = (user.email == 'henderljunior@gmail.com')
            ? 'administrador'
            : (user.userMetadata?['role'] ?? 'profesor');
        final fullName = user.userMetadata?['full_name'] ??
            (user.email?.split('@').first ?? 'Usuario');
        final newProfile = {
          'id': user.id,
          'email': user.email ?? '',
          'full_name': fullName,
          'role': role,
          'is_active': true,
        };
        try {
          await _supabase.from('profiles').upsert(newProfile);
        } catch (_) {}
        _currentUser = UserProfile.fromMap(newProfile);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading profile: $e');
      // Resilient fallback so administrator is never locked out
      final role = (user.email == 'henderljunior@gmail.com')
          ? 'administrador'
          : (user.email == 'ludytibisay@gmail.com'
              ? 'coordinador'
              : (user.userMetadata?['role'] ?? 'profesor'));
      _currentUser = UserProfile(
        id: user.id,
        email: user.email ?? '',
        fullName: user.userMetadata?['full_name'] ??
            (user.email == 'henderljunior@gmail.com'
                ? 'Administrador CNSC'
                : (user.email ?? 'Usuario')),
        role: role,
      );
      notifyListeners();
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final cleanEmail = email.trim().toLowerCase();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_explicitLoginEmailKey, cleanEmail);
      await prefs.setBool(rememberMeKey, rememberMe);
      if (rememberMe) {
        await prefs.setString(savedEmailKey, cleanEmail);
        await prefs.setString(savedPasswordKey, password);
      } else {
        await prefs.remove(savedEmailKey);
        await prefs.remove(savedPasswordKey);
        await prefs.remove(_persistedUserJsonKey);
      }

      final response = await _supabase.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );

      if (response.user != null) {
        _isTempLogin = false;
        await prefs.setString(_explicitLoginUidKey, response.user!.id);
        await _loadUserProfile(response.user);
        await _persistCurrentUserIfRemembered();
        _isLoading = false;
        _shouldShowWelcome = true;
        notifyListeners();
        return true;
      }
      _isLoading = false;
      _errorMessage = 'Credenciales inválidas';
      notifyListeners();
      return false;
    } on AuthException catch (e) {
      // Intentar validar si tiene una contraseña temporal generada por el administrador
      final tempUser = await PasswordManagementService.verifyTemporaryPassword(
        cleanEmail,
        password,
      );
      if (tempUser != null) {
        return await _completeTempUserLogin(
          tempUser: tempUser,
          email: cleanEmail,
          password: password,
        );
      }

      _isLoading = false;
      _errorMessage = _getAuthErrorMessage(e.message);
      notifyListeners();
      return false;
    } catch (e) {
      // Intentar validar si tiene una contraseña temporal generada por el administrador
      final tempUser = await PasswordManagementService.verifyTemporaryPassword(
        cleanEmail,
        password,
      );
      if (tempUser != null) {
        return await _completeTempUserLogin(
          tempUser: tempUser,
          email: cleanEmail,
          password: password,
        );
      }

      _isLoading = false;
      _errorMessage = 'Error de conexión o credenciales incorrectas.';
      notifyListeners();
      return false;
    }
  }

  /// Sincroniza la clave temporal con la propia cuenta del usuario en Supabase Auth
  /// NUNCA inicia sesión con la cuenta del administrador en el dispositivo del profesor.
  Future<bool> _completeTempUserLogin({
    required UserProfile tempUser,
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_explicitLoginEmailKey, email);
    await prefs.setString(_explicitLoginUidKey, tempUser.id);

    // Sincronizar la contraseña en Supabase Auth para este usuario específico y autenticar su propia sesión
    try {
      final jwt = await PasswordManagementService.getAdminJwt();
      if (jwt != null && !tempUser.id.startsWith('temp_')) {
        await http.put(
          Uri.parse('${SupabaseConfig.supabaseUrl}/auth/v1/admin/users/${tempUser.id}'),
          headers: {
            'apikey': SupabaseConfig.supabaseAnonKey,
            'Authorization': 'Bearer $jwt',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'password': password.trim(),
            'email_confirm': true,
          }),
        );
        final res = await _supabase.auth.signInWithPassword(
          email: email,
          password: password.trim(),
        );
        if (res.user != null) {
          _isTempLogin = false;
          _currentUser = tempUser;
          await _persistCurrentUserIfRemembered();
          _isLoading = false;
          _errorMessage = null;
          _shouldShowWelcome = true;
          notifyListeners();
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error syncing temp user auth session: $e');
    }

    _isTempLogin = true;
    _currentUser = tempUser;
    await _persistCurrentUserIfRemembered();
    _isLoading = false;
    _errorMessage = null;
    _shouldShowWelcome = true;
    notifyListeners();
    return true;
  }

  Future<void> signOut() async {
    _isTempLogin = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_explicitLoginEmailKey);
      await prefs.remove(_explicitLoginUidKey);
      await prefs.remove(_persistedUserJsonKey);
    } catch (_) {}
    await _supabase.auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  Future<bool> updateProfile({
    String? fullName,
    String? phone,
    String? avatarUrl,
  }) async {
    if (_currentUser == null) return false;
    try {
      final updates = <String, dynamic>{};
      if (fullName != null) updates['full_name'] = fullName;
      if (phone != null) updates['phone'] = phone;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      await _supabase
          .from('profiles')
          .update(updates)
          .eq('id', _currentUser!.id);

      _currentUser = _currentUser!.copyWith(
        fullName: fullName ?? _currentUser!.fullName,
        phone: phone ?? _currentUser!.phone,
        avatarUrl: avatarUrl ?? _currentUser!.avatarUrl,
      );
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> changePassword(String newPassword) async {
    if (_currentUser == null) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final jwt = await PasswordManagementService.getAdminJwt();

      // 1. Intentar actualizar contraseña a través de la sesión propia de Supabase Auth
      bool authUpdated = false;
      if (!_isTempLogin && _supabase.auth.currentUser?.id == _currentUser!.id) {
        try {
          await _supabase.auth.updateUser(UserAttributes(password: newPassword));
          authUpdated = true;
        } catch (authErr) {
          debugPrint('Direct updateUser failed: $authErr. Trying admin REST API...');
        }
      }

      // Si falló o si era sesión temporal, actualizar la cuenta específica mediante API administrativa
      if (!authUpdated && jwt != null) {
        final adminUrl = '${SupabaseConfig.supabaseUrl}/auth/v1/admin/users/${_currentUser!.id}';
        final resp = await http.put(
          Uri.parse(adminUrl),
          headers: {
            'apikey': SupabaseConfig.supabaseAnonKey,
            'Authorization': 'Bearer $jwt',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'password': newPassword}),
        );
        debugPrint('Admin update user password response: ${resp.statusCode}');
      }

      // 2. Limpiar bandera [FORCE_PWD_CHANGE] y registrar la contraseña visible para el admin en [PWD:...]
      final rawPhone = _currentUser!.phone ?? '';
      final cleanedPhone = rawPhone
          .replaceAll('[FORCE_PWD_CHANGE]', '')
          .replaceAll(RegExp(r'\[(?:TEMP_PWD|PWD):[^\]]+\]'), '')
          .replaceAll('[RESET_REQ]', '')
          .trim();
      final cleanVal = '[PWD:${newPassword.trim()}]$cleanedPhone';

      if (jwt != null) {
        await http.patch(
          Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?id=eq.${_currentUser!.id}'),
          headers: {
            'apikey': SupabaseConfig.supabaseAnonKey,
            'Authorization': 'Bearer $jwt',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'phone': cleanVal,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      } else {
        await _supabase
            .from('profiles')
            .update({
              'phone': cleanVal,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', _currentUser!.id);
      }

      // 3. Limpiar SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cnsc_temp_pwd_${_currentUser!.email.toLowerCase()}');
      if (prefs.getBool(rememberMeKey) ?? true) {
        await prefs.setString(savedPasswordKey, newPassword.trim());
      }

      // 4. Actualizar usuario en memoria y persistir sesión si tiene Recordarme activo
      _currentUser = _currentUser!.copyWith(
        phone: cleanVal,
      );
      await _persistCurrentUserIfRemembered();
      _isTempLogin = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error en changePassword: $e');
      _errorMessage = 'No se pudo actualizar la contraseña. Intenta nuevamente.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  String _getAuthErrorMessage(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'Correo o contraseña incorrectos';
    } else if (message.contains('Email not confirmed')) {
      return 'Confirma tu correo electrónico';
    } else if (message.contains('Too many requests')) {
      return 'Demasiados intentos. Espera un momento.';
    }
    return 'Error al iniciar sesión. Intenta de nuevo.';
  }
}
