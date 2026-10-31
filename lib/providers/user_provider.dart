import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:contro_asistencias/core/constants/supabase_config.dart';
import 'package:contro_asistencias/data/models/user_profile.dart';
import 'package:contro_asistencias/core/services/password_management_service.dart';

class UserProvider extends ChangeNotifier {
  List<UserProfile> _users = [];
  bool _isLoading = false;
  String? _error;

  List<String> _pendingResetEmails = [];

  List<UserProfile> get users => _users;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<String> get pendingResetEmails => _pendingResetEmails;

  List<UserProfile> get teachers =>
      _users.where((u) => u.role == 'profesor').toList();

  List<UserProfile> get coordinators =>
      _users.where((u) => u.role == 'coordinador').toList();

  List<UserProfile> get staffAndTeachers =>
      _users.where((u) => u.role == 'profesor' || u.role == 'coordinador').toList();

  final SupabaseClient _supabase = Supabase.instance.client;

  UserProvider() {
    loadUsers();
  }

  Future<void> loadUsers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      dynamic data = await _supabase
          .from('profiles')
          .select()
          .order('role')
          .order('full_name');

      if (data == null || (data is List && data.isEmpty)) {
        final jwt = await PasswordManagementService.getAdminJwt();
        if (jwt != null) {
          final resp = await http.get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?select=*&order=role.asc,full_name.asc'),
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
              'Authorization': 'Bearer $jwt',
            },
          );
          if (resp.statusCode == 200) {
            data = jsonDecode(resp.body);
          }
        }
      }

      _users = (data as List).map((map) => UserProfile.fromMap(map)).toList();
      _pendingResetEmails = await PasswordManagementService.getPendingResetEmails();
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading users: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Crea un nuevo usuario mediante una instancia aislada de Supabase Auth
  /// para no invalidar ni modificar la sesión del administrador actual.
  Future<bool> createUser({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? phone,
    String? classroomId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Instancia aislada del cliente para el registro sin cambiar la sesión actual
      final authClient = SupabaseClient(
        SupabaseConfig.supabaseUrl,
        SupabaseConfig.supabaseAnonKey,
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );

      final response = await authClient.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'role': role,
          'phone': phone ?? '',
        },
      );

      final newUserId = response.user?.id;
      if (newUserId != null) {
        // Asegurar que el perfil quede guardado y activo
        try {
          await _supabase.from('profiles').upsert({
            'id': newUserId,
            'email': email,
            'full_name': fullName,
            'role': role,
            'phone': phone,
            'is_active': true,
          });
        } catch (_) {}

        // Si se seleccionó un salón para el profesor, asignarlo inmediatamente
        if (classroomId != null && classroomId.isNotEmpty) {
          try {
            await _supabase
                .from('classrooms')
                .update({'teacher_id': newUserId})
                .eq('id', classroomId);
          } catch (_) {}
        }

        await loadUsers();
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _error = 'No se pudo crear el usuario. Verifica los datos.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Actualiza los detalles completos de un usuario: nombre, teléfono, rol, contraseña opcional y salón
  Future<bool> updateUserDetails({
    required String userId,
    required String fullName,
    required String role,
    String? phone,
    String? newPassword,
    String? classroomId,
    bool forcePwdChange = false,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final jwt = await PasswordManagementService.getAdminJwt();

      // 1. Si se especificó una nueva contraseña, actualizar en Supabase Auth
      if (newPassword != null && newPassword.trim().isNotEmpty && jwt != null) {
        final cleanPwd = newPassword.trim();
        final adminUrl = '${SupabaseConfig.supabaseUrl}/auth/v1/admin/users/$userId';
        await http.put(
          Uri.parse(adminUrl),
          headers: {
            'apikey': SupabaseConfig.supabaseAnonKey,
            'Authorization': 'Bearer $jwt',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'password': cleanPwd}),
        );
      }

      // 2. Construir el campo phone con las marcas [PWD:...] y [FORCE_PWD_CHANGE] si corresponde
      String? updatedPhone = phone;
      if (newPassword != null && newPassword.trim().isNotEmpty) {
        final cleanBasePhone = (phone ?? '')
            .replaceAll(RegExp(r'\[RESET_REQ\]'), '')
            .replaceAll(RegExp(r'\[(?:TEMP_PWD|PWD):[^\]]+\]'), '')
            .replaceAll('[FORCE_PWD_CHANGE]', '')
            .trim();

        final pwdTag = '[PWD:${newPassword.trim()}]';
        final forceTag = forcePwdChange ? '[FORCE_PWD_CHANGE]' : '';
        updatedPhone = '$forceTag$pwdTag$cleanBasePhone';
      }

      // 3. Actualizar perfil en Supabase
      final profilePayload = {
        'full_name': fullName.trim(),
        'role': role,
        'phone': updatedPhone,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (jwt != null) {
        await http.patch(
          Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?id=eq.$userId'),
          headers: {
            'apikey': SupabaseConfig.supabaseAnonKey,
            'Authorization': 'Bearer $jwt',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(profilePayload),
        );
      } else {
        await _supabase.from('profiles').update(profilePayload).eq('id', userId);
      }

      // 4. Actualizar asignación de salón
      // Desasignar cualquier salón previo
      try {
        await _supabase
            .from('classrooms')
            .update({'teacher_id': null})
            .eq('teacher_id', userId);
      } catch (_) {}

      // Si es profesor y se seleccionó salón, asignarlo
      if (role == 'profesor' && classroomId != null && classroomId.isNotEmpty) {
        try {
          await _supabase
              .from('classrooms')
              .update({'teacher_id': userId})
              .eq('id', classroomId);
        } catch (_) {}
      }

      await loadUsers();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error updating user details: $e');
      _error = 'Error al actualizar usuario: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Cambia el rol de un usuario
  Future<bool> updateUserRole(String userId, String newRole) async {
    try {
      await _supabase
          .from('profiles')
          .update({'role': newRole})
          .eq('id', userId);
      await loadUsers();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Activa o desactiva un usuario
  Future<bool> toggleUserStatus(String userId, bool isActive) async {
    try {
      await _supabase
          .from('profiles')
          .update({'is_active': isActive})
          .eq('id', userId);
      await loadUsers();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Elimina el perfil del usuario de la base de datos
  Future<bool> deleteProfile(String userId) async {
    try {
      await _supabase.from('profiles').delete().eq('id', userId);
      _users.removeWhere((u) => u.id == userId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Asigna una nueva contraseña temporal a un usuario
  Future<bool> assignTemporaryPassword({
    required String userId,
    required String email,
    required String newPassword,
    String? currentPhone,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await PasswordManagementService.assignTemporaryPassword(
        userId: userId,
        email: email,
        newPassword: newPassword,
        currentPhone: currentPhone,
      );

      if (success) {
        await loadUsers();
        return true;
      } else {
        _error = 'No se pudo asignar la contraseña temporal';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Limpia una solicitud de restablecimiento para un usuario
  Future<void> clearResetRequest({
    required String userId,
    required String email,
    String? currentPhone,
  }) async {
    await PasswordManagementService.clearResetRequest(
      userId: userId,
      email: email,
      currentPhone: currentPhone,
    );
    await loadUsers();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
