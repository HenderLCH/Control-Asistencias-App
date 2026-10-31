import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';

class FcmSenderService {
  static final FcmSenderService _instance = FcmSenderService._internal();
  factory FcmSenderService() => _instance;
  FcmSenderService._internal();

  static const _serviceAccount = {
    "type": "service_account",
    "project_id": "control-asitencias-nazareth",
    "private_key_id": "b1500e9bb1f7eb836e41f4b1db0022cf05fad277",
    "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDo/QtJ0QaW5oZx\nec3rTUV69GYpmy5FstCBlG53dO0r8wxX8GEYHU4+ovuXLK9IPBe6isyX6ddCxrD/\nJG4zivB59K3idFHaUU3rE255WRN3qL4qvvgrjDpMVKkQwT3EnabXCOk894ThB7wz\nV3ZTntGGyyB1wZjtwKPhrSfieeLcehOy4Dqb+OqQ5twPFMGMO6ScWCis68iCPDHg\nKwDxWFSspnRjwv2LYxQoWRTB/NThfIF7zLvczyVDt8Ufg88xxMwugGNOKzpD2jgI\nmIZYUMEIYlbXJwZYqtz4xfosb53RJDtZhk9YrQwilgU/sm8m74br24GjIkKUxcbz\nOIgmM+vDAgMBAAECggEAB8ADFB2D3pkkd7nZg646VXCzxUaIL4FXNjg9xHN7QC8B\nhhtU33x6EdNSEyFFY128XFQpohQBORNq59HKaKSCg0wETLgZ0O1LbjpjPl4cK6rN\nSJa5opkzhz55sTj8WQH1fsmpGIITRXkAZaTPJtDtn1I6bjBWafIygVtFLF9pkHPe\n20gVdNxaFZ9AGkrDlBt6Wkl/75zzTQc4HJbY8UU7dR/Xs6JVYWPyA2fcfteIP8+F\n0ulMNXmdqbZIxhawXzjTiN/HhA/sYRgMG7QqyICc8L1m+SpQmTv+yvdEEXtkL2GS\n62q9j2dQJVgVOWVpetWDNpTcCWlBASyaWkh4MaAc4QKBgQD6EzMPb/wVB4fLYuD5\neoWBBSrfU/Tv1+BoHX5pQdeYDx1D/mxDiFf0sCw5tVP9gEpqOX03EeZGgBLS0Qsw\nwUsDqeKZ3TRROs8KqrogX6gw6dH8nBQzAFhxSyGya7v89CeMU+//K5nkqFLXpw0S\ndDPQHgRqHSb6heaZN0DzxNvt9wKBgQDugjVNWc7syoGfSbFytjnXwfBuUzk0f8mR\n4rzaX2TwAiOhqTW6C1fCEgZZjsUhrGDfE3D49XC4y6LGlA2z0oHqI3bBATxgshgw\nNtlotgdHJzarMQ7cUp2SyZVczXKcT2SxQQwZb6xWX3YTlnUcyWX717IlWTTGIQCV\nrJrAwhItlQKBgQD4MpgJ6VZjNM8lIKUzVtQsIonTj8tZRIQYMbWmGFA3PkEIm/qt\n6COL2lJ6kCqlPnAdD6PkRWKsdC66h/m4UQ/3ueQKXA6x1FFrP9ltiiMvMNJWCj7O\nA7jD8RKnt9+jhlu+Hgzj0E10MU/Pc6A4wZYvJ6uv+fEW0lD1nm5bwvWZLwKBgA+H\nZMcLgOCD8tqXJrmMScnVc70LKB9V7p7T/23MZjsGOKGu7bOWR3l4SPeNxyIBIjGE\nB4f+Gv+9KnT5cMbzfsfq1TGNzguRrOd+ursJlwG3+OQ+hnQr4NyMyW/IZJzuwmSU\nEqCZV8Qr5Pkzg56DMmOqUIwD+d6oiWw1V8ITILHdAoGBALXColoNywZVlcWGLFp2\n3Cnqy4ZOIYMiZmJzGgIi+AqdmBENN/2PrcEHKRrFNqHOIKh9gkZ9KxiqUKOCL20o\nHZXIigcBjIX7rWBwVtd78iKzi/Xt5ka9Bkf4/lZJBaSOxQe3KSLB6n0x+dLyjMIm\nqn0QQbaJnVOrMph/TWhJ5rgN\n-----END PRIVATE KEY-----\n",
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
