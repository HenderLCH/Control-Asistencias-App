import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class VersionCheckService {
  static final VersionCheckService _instance = VersionCheckService._internal();
  factory VersionCheckService() => _instance;
  VersionCheckService._internal();

  // Endpoint público en GitHub raw
  static const String _versionUrl =
      'https://raw.githubusercontent.com/HenderLCH/Control-Asistencias-App/main/app_version.json';

  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.consolacion.contro_asistencias';

  bool _hasChecked = false;

  Future<void> checkForUpdates(BuildContext context) async {
    if (_hasChecked) return;
    _hasChecked = true;

    try {
      final response = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final minRequiredVersion = data['min_required_version'] as String? ?? '1.0.0';
      final latestVersion = data['latest_version'] as String? ?? '1.0.0';
      final forceUpdate = data['force_update'] as bool? ?? false;
      final updateUrl = data['update_url'] as String? ?? _playStoreUrl;
      final title = data['title'] as String? ?? 'Actualización disponible';
      final message = data['message'] as String? ??
          'Hay una versión más reciente de Control de Asistencias disponible en Google Play Store.';

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.2.0"

      final isCurrentObsolete = _isVersionLower(currentVersion, minRequiredVersion);
      final isNewerAvailable = _isVersionLower(currentVersion, latestVersion);

      if ((isCurrentObsolete || isNewerAvailable) && context.mounted) {
        final isForced = isCurrentObsolete || forceUpdate;
        _showUpdateDialog(
          context,
          title: title,
          message: message,
          updateUrl: updateUrl,
          isForced: isForced,
          latestVersion: latestVersion,
        );
      }
    } catch (e) {
      debugPrint('Version check notice: $e');
    }
  }

  /// Compara dos versiones semánticas (ej. 1.2.0 < 1.3.0 -> true)
  bool _isVersionLower(String current, String target) {
    try {
      final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final targetParts = target.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      while (currentParts.length < 3) {
        currentParts.add(0);
      }
      while (targetParts.length < 3) {
        targetParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (currentParts[i] < targetParts[i]) return true;
        if (currentParts[i] > targetParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _showUpdateDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String updateUrl,
    required bool isForced,
    required String latestVersion,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isForced,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return WillPopScope(
          onWillPop: () async => !isForced,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppTheme.accent,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Nueva versión: v$latestVersion',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      final uri = Uri.parse(updateUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.storefront_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Actualizar en Google Play',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isForced) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text(
                      'Recordar más tarde',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
