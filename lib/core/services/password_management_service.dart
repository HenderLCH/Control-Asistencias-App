import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contro_asistencias/core/constants/supabase_config.dart';
import 'package:contro_asistencias/data/models/user_profile.dart';

class PasswordManagementService {
  static const String _pendingResetsKey = 'cnsc_pending_reset_emails';
  static const String _tempPasswordPrefix = 'cnsc_temp_pwd_';

  static String? _cachedAdminJwt;
  static DateTime? _adminJwtExpiry;

  /// Obtiene un JWT administrativo mediante petición REST directa sin alterar la sesión de la UI
  static Future<String?> getAdminJwt() async {
    if (_cachedAdminJwt != null &&
        _adminJwtExpiry != null &&
        DateTime.now().isBefore(_adminJwtExpiry!)) {
      return _cachedAdminJwt;
    }
    if (SupabaseConfig.adminServiceEmail.isEmpty ||
        SupabaseConfig.adminServicePass.isEmpty) {
      return null;
    }
    try {
      final resp = await http.post(
        Uri.parse('${SupabaseConfig.supabaseUrl}/auth/v1/token?grant_type=password'),
        headers: {
          'apikey': SupabaseConfig.supabaseAnonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': SupabaseConfig.adminServiceEmail,
          'password': SupabaseConfig.adminServicePass,
        }),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        _cachedAdminJwt = data['access_token'] as String?;
        _adminJwtExpiry = DateTime.now().add(const Duration(minutes: 50));
        return _cachedAdminJwt;
      }
    } catch (e) {
      debugPrint('Error obteniendo token administrativo: $e');
    }
    return null;
  }

  /// Genera una contraseña sugerida segura de 8 caracteres que cumple con:
  /// mayúscula, minúscula, número y signo especial (incluido el '.')
  static String generateSecurePassword({int length = 8}) {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnpqrstuvwxyz';
    const digits = '23456789';
    const specials = '.!@#*';
    const all = '$upper$lower$digits$specials';

    final random = Random.secure();
    final chars = <String>[
      upper[random.nextInt(upper.length)],
      lower[random.nextInt(lower.length)],
      digits[random.nextInt(digits.length)],
      specials[random.nextInt(specials.length)],
    ];

    while (chars.length < length) {
      chars.add(all[random.nextInt(all.length)]);
    }

    chars.shuffle(random);
    return chars.join();
  }

  /// Registra una solicitud de cambio de contraseña desde la pantalla de login
  static Future<bool> requestPasswordReset(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      // 1. Guardar en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_pendingResetsKey) ?? [];
      if (!list.contains(cleanEmail)) {
        list.add(cleanEmail);
        await prefs.setStringList(_pendingResetsKey, list);
      }

      // 2. Marcar [RESET_REQ] en Supabase profiles vía API REST administrativa
      final jwt = await getAdminJwt();
      if (jwt != null) {
        final getResp = await http.get(
          Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?email=eq.$cleanEmail'),
          headers: {
            'apikey': SupabaseConfig.supabaseAnonKey,
            'Authorization': 'Bearer $jwt',
          },
        );

        if (getResp.statusCode == 200) {
          final rows = jsonDecode(getResp.body) as List;
          if (rows.isNotEmpty) {
            final row = rows.first;
            final id = row['id'] as String;
            final curPhone = row['phone'] as String? ?? '';
            if (!curPhone.contains('[RESET_REQ]')) {
              await http.patch(
                Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?id=eq.$id'),
                headers: {
                  'apikey': SupabaseConfig.supabaseAnonKey,
                  'Authorization': 'Bearer $jwt',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({'phone': '[RESET_REQ]$curPhone'}),
              );
            }
          }
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error en requestPasswordReset: $e');
      return false;
    }
  }

  /// Registra una solicitud de eliminación de cuenta y datos personales
  static Future<bool> requestAccountDeletion({
    required String email,
    String? reason,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('cnsc_pending_deletion_emails') ?? [];
      if (!list.contains(cleanEmail)) {
        list.add(cleanEmail);
        await prefs.setStringList('cnsc_pending_deletion_emails', list);
      }
      return true;
    } catch (e) {
      debugPrint('Error en requestAccountDeletion: $e');
      return false;
    }
  }

  /// Retorna la lista de correos con solicitud pendiente
  static Future<List<String>> getPendingResetEmails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_pendingResetsKey) ?? [];
    } catch (_) {
      return [];
    }
  }

  /// Asigna una nueva contraseña temporal a un usuario (invocado por el administrador)
  static Future<bool> assignTemporaryPassword({
    required String userId,
    required String email,
    required String newPassword,
    String? currentPhone,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPwd = newPassword.trim();

    try {
      // 1. Guardar en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_tempPasswordPrefix$cleanEmail', cleanPwd);

      final list = prefs.getStringList(_pendingResetsKey) ?? [];
      list.remove(cleanEmail);
      await prefs.setStringList(_pendingResetsKey, list);

      // 2. Limpiar teléfono de marcas previas y agregar [TEMP_PWD:...]
      final basePhone = (currentPhone ?? '')
          .replaceAll(RegExp(r'\[RESET_REQ\]'), '')
          .replaceAll(RegExp(r'\[TEMP_PWD:[^\]]+\]'), '')
          .trim();

      final newPhoneVal = '[TEMP_PWD:$cleanPwd]$basePhone';

      // 3. Actualizar en Supabase Auth y profiles vía API REST
      final jwt = await getAdminJwt();
      if (jwt != null) {
        try {
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
        } catch (_) {}

        final patchResp = await http.patch(
          Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?id=eq.$userId'),
          headers: {
            'apikey': SupabaseConfig.supabaseAnonKey,
            'Authorization': 'Bearer $jwt',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'phone': newPhoneVal}),
        );

        return patchResp.statusCode == 204 || patchResp.statusCode == 200;
      }
    } catch (e) {
      debugPrint('Error assigning temporary password: $e');
    }
    return false;
  }

  /// Limpia cualquier solicitud pendiente para un usuario
  static Future<void> clearResetRequest({
    required String userId,
    required String email,
    String? currentPhone,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_pendingResetsKey) ?? [];
      list.remove(cleanEmail);
      await prefs.setStringList(_pendingResetsKey, list);

      if (currentPhone != null && currentPhone.contains('[RESET_REQ]')) {
        final cleaned = currentPhone.replaceAll('[RESET_REQ]', '').trim();
        final jwt = await getAdminJwt();
        if (jwt != null) {
          await http.patch(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?id=eq.$userId'),
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
              'Authorization': 'Bearer $jwt',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'phone': cleaned.isEmpty ? null : cleaned}),
          );
        }
      }
    } catch (e) {
      debugPrint('Error clearing reset request: $e');
    }
  }

  /// Valida si el usuario ingresó una contraseña temporal válida generada por el admin
  static Future<UserProfile?> verifyTemporaryPassword(
    String email,
    String password,
  ) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPwd = password.trim();

    try {
      // 1. Verificar primero en SharedPreferences (acceso local instantáneo)
      final prefs = await SharedPreferences.getInstance();
      final cachedPwd = prefs.getString('$_tempPasswordPrefix$cleanEmail');
      bool localMatches = (cachedPwd != null && cachedPwd.trim() == cleanPwd);

      // 2. Consultar en la base de datos Supabase usando el token de servicio
      final jwt = await getAdminJwt();
      if (jwt != null) {
        final resp = await http.get(
          Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?email=eq.$cleanEmail'),
          headers: {
            'apikey': SupabaseConfig.supabaseAnonKey,
            'Authorization': 'Bearer $jwt',
          },
        );

        if (resp.statusCode == 200) {
          final list = jsonDecode(resp.body) as List;
          if (list.isNotEmpty) {
            final profileData = list.first as Map<String, dynamic>;
            final phone = profileData['phone'] as String? ?? '';
            final match = RegExp(r'\[(?:TEMP_PWD|PWD):([^\]]+)\]').firstMatch(phone);
            final expectedPwd = match?.group(1)?.trim();

            if ((expectedPwd != null && expectedPwd == cleanPwd) || localMatches) {
              return UserProfile.fromMap(profileData);
            }
          }
        }
      }

      if (localMatches) {
        return UserProfile(
          id: 'temp_${cleanEmail.hashCode}',
          email: cleanEmail,
          fullName: cleanEmail.split('@').first,
          role: cleanEmail.contains('coord') ? 'coordinador' : 'profesor',
        );
      }
    } catch (e) {
      debugPrint('Error verifying temporary password: $e');
    }
    return null;
  }
}
