import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  DateTime? _lastNotificationTime;
  String? _lastNotificationKey;

  bool _isDuplicate(String key) {
    final now = DateTime.now();
    if (_lastNotificationKey == key &&
        _lastNotificationTime != null &&
        now.difference(_lastNotificationTime!).inSeconds < 3) {
      return true;
    }
    _lastNotificationKey = key;
    _lastNotificationTime = now;
    return false;
  }

  Future<void> initialize() async {
    if (kIsWeb) return;
    if (_isInitialized) return;

    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
        macOS: initializationSettingsDarwin,
      );

      await _notificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('Notification clicked: ${response.payload}');
        },
      );

      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'cnsc_attendance_channel',
            'Asistencias CNSC',
            description:
                'Avisos en tiempo real cuando un salón finaliza el pase de asistencia',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      }

      // Escuchar notificaciones de Firebase Messaging en primer plano
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM Foreground message: ${message.messageId}');
        final notification = message.notification;
        final data = message.data;
        final classroom = data['classroom_name'] ?? notification?.title ?? 'un salón';
        final teacher = data['teacher_name'];
        final actionType = data['action_type'] ?? 'completed';

        if (actionType == 'modified') {
          showAttendanceModifiedNotification(
            classroomName: classroom.toString(),
            teacherName: teacher?.toString(),
          );
        } else {
          showAttendanceCompletedNotification(
            classroomName: classroom.toString(),
            teacherName: teacher?.toString(),
          );
        }
      });

      _isInitialized = true;
      debugPrint('NotificationService and FCM initialized successfully');
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }
  }

  /// Solicita permisos de notificación de forma segura cuando la UI ya está montada
  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    try {
      if (!_isInitialized) {
        await initialize();
      }
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }

      // Permisos nativos de FCM para Android 13+ e iOS
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (e) {
      debugPrint('Error requesting notification permissions: $e');
    }
  }

  /// Suscribe el dispositivo al canal de avisos de asistencias para Administradores
  Future<void> subscribeToAdminAlerts() async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.subscribeToTopic('admin_attendance_completed');
      debugPrint('Subscribed to admin_attendance_completed FCM topic');
    } catch (e) {
      debugPrint('Error subscribing to FCM topic: $e');
    }
  }

  /// Desuscribe el dispositivo del canal
  Future<void> unsubscribeFromAdminAlerts() async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic('admin_attendance_completed');
      debugPrint('Unsubscribed from admin_attendance_completed FCM topic');
    } catch (e) {
      debugPrint('Error unsubscribing from FCM topic: $e');
    }
  }

  Future<void> showAttendanceCompletedNotification({
    required String classroomName,
    String? teacherName,
  }) async {
    if (kIsWeb) return;
    if (_isDuplicate('completed_$classroomName')) return;
    try {
      if (!_isInitialized) {
        await initialize();
      }

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'cnsc_attendance_channel',
        'Asistencias CNSC',
        channelDescription:
            'Avisos en tiempo real cuando un salón finaliza el pase de asistencia',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Asistencia completada',
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails darwinDetails =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      final title = 'Asistencia completada: $classroomName';
      final body = teacherName != null && teacherName.isNotEmpty
          ? 'El Prof. $teacherName ha completado la asistencia de $classroomName.'
          : 'Se ha completado la asistencia de $classroomName.';

      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await _notificationsPlugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: platformDetails,
        payload: classroomName,
      );
    } catch (e) {
      debugPrint('Error showing attendance completed notification: $e');
    }
  }

  Future<void> showAttendanceModifiedNotification({
    required String classroomName,
    String? teacherName,
  }) async {
    if (kIsWeb) return;
    if (_isDuplicate('modified_$classroomName')) return;
    try {
      if (!_isInitialized) {
        await initialize();
      }

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'cnsc_attendance_channel',
        'Asistencias CNSC',
        channelDescription:
            'Avisos en tiempo real cuando un salón modifica el pase de asistencia',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Asistencia modificada',
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
      );

      const DarwinNotificationDetails darwinDetails =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      final title = 'Asistencia modificada: $classroomName';
      final body = teacherName != null && teacherName.isNotEmpty
          ? 'El Prof. $teacherName ha modificado la asistencia de $classroomName.'
          : 'Se han realizado modificaciones en la asistencia de $classroomName.';

      final notificationId = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 1;

      await _notificationsPlugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: platformDetails,
        payload: classroomName,
      );
    } catch (e) {
      debugPrint('Error showing attendance modified notification: $e');
    }
  }
}
