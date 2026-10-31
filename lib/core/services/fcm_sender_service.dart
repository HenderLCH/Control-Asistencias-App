import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';
import '../constants/supabase_config.dart';

class FcmSenderService {
  static final FcmSenderService _instance = FcmSenderService._internal();
  factory FcmSenderService() => _instance;
  FcmSenderService._internal();

  static Map<String, dynamic> get _serviceAccount => {
    "type": "service_account",
    "project_id": "control-asitencias-nazareth",
    "private_key_id": SupabaseConfig.fcmPrivateKeyId,
    "private_key": SupabaseConfig.fcmPrivateKey.replaceAll(r'\n', '\n'),
    "client_email": "firebase-adminsdk-fbsvc@control-asitencias-nazareth.iam.gserviceaccount.com",
    "client_id": "110296567271265451976",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
  };

  AutoRefreshingAuthClient? _cachedClient;

  Future<AutoRefreshingAuthClient?> _getClient() async {
    try {
      if (_cachedClient != null) {
        return _cachedClient;
      }
      final credentials = ServiceAccountCredentials.fromJson(_serviceAccount);
      _cachedClient = await clientViaServiceAccount(credentials, [
        'https://www.googleapis.com/auth/firebase.messaging',
      ]);
      return _cachedClient;
    } catch (e) {
      debugPrint('Error creating FCM auth client: $e');
      return null;
    }
  }

  Future<void> sendAttendancePushNotification({
    required String classroomName,
    String? teacherName,
    required bool isModification,
  }) async {
    try {
      final client = await _getClient();
      if (client == null) {
        debugPrint('Cannot send push notification: client is null');
        return;
      }

      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/control-asitencias-nazareth/messages:send',
      );

      final title = isModification
          ? 'Asistencia modificada: $classroomName'
          : 'Asistencia completada: $classroomName';

      final body = isModification
          ? (teacherName != null && teacherName.isNotEmpty
              ? 'El Prof. $teacherName ha modificado la asistencia de $classroomName.'
              : 'Se ha modificado la asistencia de $classroomName.')
          : (teacherName != null && teacherName.isNotEmpty
              ? 'El Prof. $teacherName ha completado la asistencia de $classroomName.'
              : 'Se ha completado la asistencia de $classroomName.');

      final payload = {
        'message': {
          'topic': 'admin_attendance_completed',
          'notification': {
            'title': title,
            'body': body,
          },
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': 'cnsc_attendance_channel',
              'default_sound': true,
              'default_vibrate_timings': true,
              'notification_priority': 'PRIORITY_MAX',
              'icon': '@mipmap/ic_launcher',
            },
          },
          'data': {
            'classroom_name': classroomName,
            'teacher_name': teacherName ?? '',
            'action_type': isModification ? 'modified' : 'completed',
          },
        }
      };

      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('FCM Push notification sent successfully to topic: admin_attendance_completed');
      } else {
        debugPrint('FCM Push error: ${response.statusCode} - ${response.body}');
        _cachedClient = null;
      }
    } catch (e) {
      debugPrint('Error sending FCM push: $e');
      _cachedClient = null;
    }
  }
}
