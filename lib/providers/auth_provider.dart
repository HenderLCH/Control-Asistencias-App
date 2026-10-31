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
  bool get isCoordinator => _currentUser?.isCoordinator ?? false;
  bool get isTeacher => _currentUser?.isTeacher ?? false;
  bool get canManageData => isAdmin;
  bool get canAssignTeachers => isAdmin || isCoordinator;

  bool _isTempLogin = false;

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
        _currentUser = null;
        notifyListeners();
      }
    });

    // Check current session
    final currentSession = _supabase.auth.currentSession;
    if (currentSession != null) {
      _loadUserProfile(currentSession.user);
    }
  }

  Future<void> _loadUserProfile(User? user) async {
    if (user == null) return;
    try {
      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data != null) {
        _currentUser = UserProfile.fromMap({...data, 'email': user.email ?? ''});
      } else {
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
                : 'Ludy Tibisay'),
        role: role,
      );
      notifyListeners();
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        _isTempLogin = false;
        await _loadUserProfile(response.user);
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
        email,
        password,
      );
      if (tempUser != null) {
        _isTempLogin = true;
        if (SupabaseConfig.adminServiceEmail.isNotEmpty &&
            SupabaseConfig.adminServicePass.isNotEmpty) {
          try {
            await _supabase.auth.signInWithPassword(
              email: SupabaseConfig.adminServiceEmail,
              password: SupabaseConfig.adminServicePass,
            );
          } catch (_) {}
        }
        _currentUser = tempUser;
        _isLoading = false;
        _errorMessage = null;
        _shouldShowWelcome = true;
        notifyListeners();
        return true;
      }

      _isLoading = false;
      _errorMessage = _getAuthErrorMessage(e.message);
      notifyListeners();
      return false;
    } catch (e) {
      // Intentar validar si tiene una contraseña temporal generada por el administrador
      final tempUser = await PasswordManagementService.verifyTemporaryPassword(
        email,
        password,
      );
      if (tempUser != null) {
        _isTempLogin = true;
        if (SupabaseConfig.adminServiceEmail.isNotEmpty &&
            SupabaseConfig.adminServicePass.isNotEmpty) {
          try {
            await _supabase.auth.signInWithPassword(
              email: SupabaseConfig.adminServiceEmail,
              password: SupabaseConfig.adminServicePass,
            );
          } catch (_) {}
        }
        _currentUser = tempUser;
        _isLoading = false;
        _errorMessage = null;
        _shouldShowWelcome = true;
        notifyListeners();
        return true;
      }

      _isLoading = false;
      _errorMessage = 'Error de conexión o credenciales incorrectas.';
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _isTempLogin = false;
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

      // 1. Intentar actualizar contraseña a través de la sesión de Supabase Auth
      bool authUpdated = false;
      try {
        await _supabase.auth.updateUser(UserAttributes(password: newPassword));
        authUpdated = true;
      } catch (authErr) {
        debugPrint('Direct updateUser failed: $authErr. Trying admin REST API...');
      }

      // Si falló (ej. por ser sesión temporal admin-fallback), actualizar mediante API administrativa
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

      // 4. Actualizar usuario en memoria
      _currentUser = _currentUser!.copyWith(
        phone: cleanVal,
      );
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
