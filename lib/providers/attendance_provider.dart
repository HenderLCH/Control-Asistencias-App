import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:contro_asistencias/core/constants/supabase_config.dart';
import 'package:contro_asistencias/core/services/password_management_service.dart';
import 'package:contro_asistencias/data/models/attendance_record.dart';
import 'package:contro_asistencias/data/models/student.dart';
import 'package:contro_asistencias/data/models/classroom.dart';
import 'package:contro_asistencias/core/services/notification_service.dart';
import 'package:contro_asistencias/core/services/fcm_sender_service.dart';

class AttendanceProvider extends ChangeNotifier {
  // Map: studentId -> AttendanceRecord for the current date
  Map<String, AttendanceRecord> _todayAttendance = {};
  List<AttendanceRecord> _attendanceHistory = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;
  DateTime _selectedDate = DateTime.now();

  // Tardiness tracking & alerts
  List<TardinessAlert> _tardinessAlerts = [];
  Map<String, int> _studentLateCounts = {};
  bool _isLoadingAlerts = false;

  Map<String, AttendanceRecord> get todayAttendance => _todayAttendance;
  List<AttendanceRecord> get attendanceHistory => _attendanceHistory;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;
  DateTime get selectedDate => _selectedDate;

  // Tardiness getters
  List<TardinessAlert> get tardinessAlerts => _tardinessAlerts;
  List<TardinessAlert> get citations =>
      _tardinessAlerts.where((a) => a.isCitation).toList();
  List<TardinessAlert> get warnings =>
      _tardinessAlerts.where((a) => a.isWarning).toList();
  int get totalAlertsCount => _tardinessAlerts.length;
  int get citationsCount => citations.length;
  int get warningsCount => warnings.length;
  bool get isLoadingAlerts => _isLoadingAlerts;

  int getLateCountForStudent(String studentId) =>
      _studentLateCounts[studentId] ?? 0;

  int getCitationsCountForClassroom(String classroomId) =>
      _tardinessAlerts.where((a) => a.classroomId == classroomId && a.isCitation).length;

  int getWarningsCountForClassroom(String classroomId) =>
      _tardinessAlerts.where((a) => a.classroomId == classroomId && a.isWarning).length;

  TardinessAlert? getAlertForStudent(String studentId) {
    try {
      return _tardinessAlerts.firstWhere((a) => a.studentId == studentId);
    } catch (_) {
      return null;
    }
  }

  // Completed classrooms tracking for today
  List<String> _completedClassroomNamesToday = [];
  List<String> get completedClassroomNamesToday => _completedClassroomNamesToday;
  int get completedClassroomsCount => _completedClassroomNamesToday.length;

  final String _clientInstanceId = DateTime.now().microsecondsSinceEpoch.toString();
  RealtimeChannel? _realtimeChannel;
  bool _isRealtimeSubscribed = false;
  bool Function()? _isEligibleRecipient;

  void initializeRealtimeNotifications({
    required bool Function() isEligibleRecipient,
  }) {
    _isEligibleRecipient = isEligibleRecipient;
    _ensureRealtimeChannel();
  }

  RealtimeChannel _ensureRealtimeChannel() {
    if (_realtimeChannel != null && _isRealtimeSubscribed) {
      return _realtimeChannel!;
    }

    try {
      _realtimeChannel = _supabase.channel(
        'attendance_global_events',
        opts: const RealtimeChannelConfig(
          self: true,
        ),
      );

      _realtimeChannel!.onBroadcast(
        event: 'attendance_action',
        callback: (Map<String, dynamic> payload) {
          final actionType = payload['action_type'] as String? ?? 'completed';
          final classroomName = payload['classroom_name'] as String? ?? 'un salón';
          final teacherName = payload['teacher_name'] as String?;
          final senderInstanceId = payload['sender_instance_id'] as String?;

          // 1. Si este dispositivo específico fue el emisor, ignorar el broadcast (ya se manejó localmente si correspondía)
          if (senderInstanceId != null && senderInstanceId == _clientInstanceId) {
            return;
          }

          // 2. Solo mostrar a Administrador y Coordinador ("Al profesor no le debe mostrar ninguna notificación de esas")
          final isEligible = _isEligibleRecipient != null ? _isEligibleRecipient!() : true;
          if (isEligible) {
            markClassroomCompleted(classroomName);

            if (actionType == 'modified') {
              NotificationService().showAttendanceModifiedNotification(
                classroomName: classroomName,
                teacherName: teacherName,
              );
            } else {
              NotificationService().showAttendanceCompletedNotification(
                classroomName: classroomName,
                teacherName: teacherName,
              );
            }
          }
        },
      );

      _realtimeChannel!.subscribe((status, error) {
        _isRealtimeSubscribed = (status == RealtimeSubscribeStatus.subscribed);
        debugPrint('Realtime channel attendance_global_events status: $status, error: $error');
      });
    } catch (e) {
      debugPrint('Error subscribing to attendance realtime notifications: $e');
    }

    return _realtimeChannel!;
  }

  Future<void> notifyAttendanceAction({
    required String classroomName,
    required String teacherName,
    required bool isModification,
  }) async {
    try {
      markClassroomCompleted(classroomName);

      final channel = _ensureRealtimeChannel();

      // Si el canal aún no está conectado, esperar hasta 2.5s a que complete el handshake WebSocket
      if (!_isRealtimeSubscribed) {
        for (int i = 0; i < 25; i++) {
          if (_isRealtimeSubscribed) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      final res = await channel.sendBroadcastMessage(
        event: 'attendance_action',
        payload: {
          'action_type': isModification ? 'modified' : 'completed',
          'classroom_name': classroomName,
          'teacher_name': teacherName,
          'sender_instance_id': _clientInstanceId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      debugPrint('Broadcast attendance_action sent ($res): $classroomName (isMod=$isModification, instance=$_clientInstanceId)');

      // Disparar push notification FCM v1 a través de Google Cloud Messaging
      // Esto despierta dispositivos de Administradores y Coordinadores en segundo plano o con pantalla bloqueada
      FcmSenderService().sendAttendancePushNotification(
        classroomName: classroomName,
        teacherName: teacherName,
        isModification: isModification,
      );

      // Margen de 300ms para asegurar que el frame TCP/WebSocket se transmita antes de cualquier cambio de ruta UI
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('Error broadcasting attendance action: $e');
    }
  }

  void markClassroomCompleted(String classroomName) {
    if (!_completedClassroomNamesToday.contains(classroomName)) {
      _completedClassroomNamesToday.add(classroomName);
      notifyListeners();
    }
  }

  Future<void> checkCompletedClassroomsForToday(List<Classroom> classrooms) async {
    try {
      final dateStr = _dateToString(DateTime.now());
      final attendanceData = await _supabase
          .from('attendance')
          .select('classroom_id, student_id, status, notes')
          .eq('date', dateStr);

      final Map<String, Set<String>> markedByClassroom = {};
      for (final r in (attendanceData as List)) {
        if (r['status'] != 'removido' && r['notes'] != '[DESMARCADO]') {
          final cId = r['classroom_id'] as String;
          final sId = r['student_id'] as String;
          markedByClassroom.putIfAbsent(cId, () => {}).add(sId);
        }
      }

      final List<String> completed = [];
      for (final c in classrooms) {
        final count = c.studentCount ?? 0;
        final marked = markedByClassroom[c.id]?.length ?? 0;
        if (count > 0 && marked >= count) {
          completed.add(c.displayName);
        }
      }
      _completedClassroomNamesToday = completed;
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking completed classrooms: $e');
    }
  }

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> loadAttendanceForDate({
    required String classroomId,
    required DateTime date,
  }) async {
    _isLoading = true;
    _selectedDate = date;
    _error = null;
    notifyListeners();

    try {
      final dateStr = _dateToString(date);
      dynamic data = await _supabase
          .from('attendance')
          .select()
          .eq('classroom_id', classroomId)
          .eq('date', dateStr);

      if (data == null || (data is List && data.isEmpty)) {
        final jwt = await PasswordManagementService.getAdminJwt();
        if (jwt != null) {
          final resp = await http.get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/attendance?classroom_id=eq.$classroomId&date=eq.$dateStr&select=*'),
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

      _todayAttendance = {};
      if (data != null && data is List) {
        for (final map in data) {
          final record = AttendanceRecord.fromMap(map);
          if (record.status != 'removido' && record.notes != '[DESMARCADO]') {
            _todayAttendance[record.studentId] = record;
          }
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> markAttendance({
    required String studentId,
    required String classroomId,
    required String status,
    String? notes,
    String? markedById,
    DateTime? date,
  }) async {
    _isSaving = true;
    notifyListeners();

    try {
      final targetDate = date ?? _selectedDate;
      final dateStr = _dateToString(targetDate);
      final currentUid = _supabase.auth.currentUser?.id;
      final effectiveMarkedById = currentUid ?? markedById ?? 'b94e5b1c-82fa-469b-8333-a08d54d65cfd';

      dynamic response;
      try {
        response = await _supabase
            .from('attendance')
            .upsert({
              'student_id': studentId,
              'classroom_id': classroomId,
              'date': dateStr,
              'status': status,
              'notes': notes,
              'marked_by_id': effectiveMarkedById,
              'marked_at': DateTime.now().toIso8601String(),
            }, onConflict: 'student_id,date')
            .select()
            .single();
      } catch (err) {
        debugPrint('Supabase direct upsert failed ($err), executing administrative REST fallback');
        final adminJwt = await PasswordManagementService.getAdminJwt();
        if (adminJwt != null) {
          final url = Uri.parse(
            '${SupabaseConfig.supabaseUrl}/rest/v1/attendance?on_conflict=student_id,date',
          );
          final resp = await http.post(
            url,
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
              'Authorization': 'Bearer $adminJwt',
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=representation',
            },
            body: jsonEncode({
              'student_id': studentId,
              'classroom_id': classroomId,
              'date': dateStr,
              'status': status,
              'notes': notes,
              'marked_by_id': 'b94e5b1c-82fa-469b-8333-a08d54d65cfd',
              'marked_at': DateTime.now().toIso8601String(),
            }),
          );
          if (resp.statusCode == 200 || resp.statusCode == 201) {
            final list = jsonDecode(resp.body) as List;
            if (list.isNotEmpty) {
              response = list.first as Map<String, dynamic>;
            }
          }
        }
      }

      if (response != null) {
        final updatedRecord = AttendanceRecord.fromMap(response as Map<String, dynamic>);
        if (dateStr == _dateToString(_selectedDate)) {
          _todayAttendance[studentId] = updatedRecord;
        }

        // Actualizar también el historial individual si contiene registros de este alumno
        final histIdx = _attendanceHistory.indexWhere(
          (r) => r.studentId == studentId && _dateToString(r.date) == dateStr,
        );
        if (histIdx >= 0) {
          _attendanceHistory[histIdx] = updatedRecord;
        } else {
          _attendanceHistory.insert(0, updatedRecord);
          _attendanceHistory.sort((a, b) => b.date.compareTo(a.date));
        }

        _isSaving = false;
        notifyListeners();

        loadTardinessAlerts();

        return true;
      }
      throw Exception('No se pudo guardar la asistencia en el servidor');
    } catch (e) {
      debugPrint('Error en markAttendance: $e');
      _error = e.toString();
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  /// Registra o justifica múltiples fechas a la vez para un mismo estudiante
  /// (por ejemplo, cuando faltó 5 días seguidos y trae un único justificativo al 6to día).
  Future<bool> markMultipleDatesAttendance({
    required String studentId,
    required String classroomId,
    required String status,
    required List<DateTime> dates,
    String? notes,
    String? markedById,
  }) async {
    if (dates.isEmpty) return false;
    bool allSuccess = true;
    for (final d in dates) {
      final ok = await markAttendance(
        studentId: studentId,
        classroomId: classroomId,
        status: status,
        notes: notes,
        markedById: markedById,
        date: d,
      );
      if (!ok) allSuccess = false;
    }
    return allSuccess;
  }

  /// Obtiene todos los registros justificados filtrados por salón y rango de fechas
  /// incluyendo los datos del estudiante y del salón para la Sección de Justificativos.
  Future<List<Map<String, dynamic>>> fetchJustifiedRecords({
    String? classroomId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      dynamic data;
      final sDate = startDate != null ? _dateToString(startDate) : null;
      final eDate = endDate != null ? _dateToString(endDate) : null;

      try {
        var query = _supabase
            .from('attendance')
            .select('*, students(id, first_name, last_name, cedula, photo_url, parent_name, parent_phone, classroom_id, grade, section)')
            .eq('status', 'justificado');

        if (classroomId != null && classroomId.isNotEmpty) {
          query = query.eq('classroom_id', classroomId);
        }
        if (sDate != null) {
          query = query.gte('date', sDate);
        }
        if (eDate != null) {
          query = query.lte('date', eDate);
        }

        data = await query.order('date', ascending: false);
      } catch (e) {
        debugPrint('Direct select fetchJustifiedRecords failed: $e');
      }

      if (data == null || (data is List && data.isEmpty)) {
        final adminJwt = await PasswordManagementService.getAdminJwt();
        if (adminJwt != null) {
          var urlStr =
              '${SupabaseConfig.supabaseUrl}/rest/v1/attendance?status=eq.justificado&select=*,students(id,first_name,last_name,cedula,photo_url,parent_name,parent_phone,classroom_id,grade,section)&order=date.desc';
          if (classroomId != null && classroomId.isNotEmpty) {
            urlStr += '&classroom_id=eq.$classroomId';
          }
          if (sDate != null) {
            urlStr += '&date=gte.$sDate';
          }
          if (eDate != null) {
            urlStr += '&date=lte.$eDate';
          }
          final resp = await http.get(
            Uri.parse(urlStr),
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
              'Authorization': 'Bearer $adminJwt',
            },
          );
          if (resp.statusCode == 200) {
            data = jsonDecode(resp.body);
          }
        }
      }

      if (data != null && data is List) {
        return data
            .cast<Map<String, dynamic>>()
            .where((row) => row['notes'] != '[DESMARCADO]')
            .toList();
      }
    } catch (e) {
      debugPrint('Error en fetchJustifiedRecords: $e');
    }
    return [];
  }

  /// Quita la asistencia de un estudiante (vuelve a estado sin marcar)
  Future<bool> removeAttendance({
    required String studentId,
  }) async {
    _isSaving = true;
    notifyListeners();

    try {
      final existingRecord = _todayAttendance[studentId];
      if (existingRecord != null) {
        bool updateSuccess = false;
        try {
          await _supabase.from('attendance').update({
            'notes': '[DESMARCADO]',
            'marked_at': DateTime.now().toIso8601String(),
          }).eq('id', existingRecord.id);
          updateSuccess = true;
        } catch (e) {
          debugPrint('Error en removeAttendance update, intentando fallback REST: $e');
        }

        if (!updateSuccess) {
          final adminJwt = await PasswordManagementService.getAdminJwt();
          if (adminJwt != null) {
            final url = Uri.parse(
              '${SupabaseConfig.supabaseUrl}/rest/v1/attendance?id=eq.${existingRecord.id}',
            );
            await http.patch(
              url,
              headers: {
                'apikey': SupabaseConfig.supabaseAnonKey,
                'Authorization': 'Bearer $adminJwt',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'notes': '[DESMARCADO]',
                'marked_at': DateTime.now().toIso8601String(),
              }),
            );
          }
        }

        _todayAttendance.remove(studentId);

        if (existingRecord.status == 'tardanza') {
          loadTardinessAlerts();
        }
      }
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error en removeAttendance: $e');
      _error = e.toString();
      _isSaving = false;
      notifyListeners();
      return false;
    }
  }

  /// Descarta los registros de asistencia tomados en la sesión actual si el usuario sale antes de completar
  Future<void> discardSessionAttendance({
    required Set<String> initialMarkedStudentIds,
  }) async {
    _isSaving = true;
    notifyListeners();

    try {
      final newlyMarked = _todayAttendance.keys
          .where((sId) => !initialMarkedStudentIds.contains(sId))
          .toList();

      for (final sId in newlyMarked) {
        final rec = _todayAttendance[sId];
        if (rec != null) {
          bool updated = false;
          try {
            await _supabase.from('attendance').update({
              'notes': '[DESMARCADO]',
              'marked_at': DateTime.now().toIso8601String(),
            }).eq('id', rec.id);
            updated = true;
          } catch (_) {}

          if (!updated) {
            final adminJwt = await PasswordManagementService.getAdminJwt();
            if (adminJwt != null) {
              await http.patch(
                Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/attendance?id=eq.${rec.id}'),
                headers: {
                  'apikey': SupabaseConfig.supabaseAnonKey,
                  'Authorization': 'Bearer $adminJwt',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'notes': '[DESMARCADO]',
                  'marked_at': DateTime.now().toIso8601String(),
                }),
              );
            }
          }
          _todayAttendance.remove(sId);
        }
      }

      await loadTardinessAlerts();
    } catch (e) {
      debugPrint('Error descartando asistencia: $e');
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> markAllPresent({
    required List<Student> students,
    required String classroomId,
    String? markedById,
  }) async {
    _isSaving = true;
    notifyListeners();

    try {
      final dateStr = _dateToString(_selectedDate);
      final currentUid = _supabase.auth.currentUser?.id;
      final effectiveMarkedById = currentUid ?? markedById ?? 'b94e5b1c-82fa-469b-8333-a08d54d65cfd';

      for (final student in students) {
        if (!_todayAttendance.containsKey(student.id)) {
          dynamic response;
          try {
            response = await _supabase
                .from('attendance')
                .upsert({
                  'student_id': student.id,
                  'classroom_id': classroomId,
                  'date': dateStr,
                  'status': 'presente',
                  'notes': null,
                  'marked_by_id': effectiveMarkedById,
                  'marked_at': DateTime.now().toIso8601String(),
                }, onConflict: 'student_id,date')
                .select()
                .single();
          } catch (_) {
            final adminJwt = await PasswordManagementService.getAdminJwt();
            if (adminJwt != null) {
              final resp = await http.post(
                Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/attendance?on_conflict=student_id,date'),
                headers: {
                  'apikey': SupabaseConfig.supabaseAnonKey,
                  'Authorization': 'Bearer $adminJwt',
                  'Content-Type': 'application/json',
                  'Prefer': 'resolution=merge-duplicates,return=representation',
                },
                body: jsonEncode({
                  'student_id': student.id,
                  'classroom_id': classroomId,
                  'date': dateStr,
                  'status': 'presente',
                  'notes': null,
                  'marked_by_id': 'b94e5b1c-82fa-469b-8333-a08d54d65cfd',
                  'marked_at': DateTime.now().toIso8601String(),
                }),
              );
              if (resp.statusCode == 200 || resp.statusCode == 201) {
                final list = jsonDecode(resp.body) as List;
                if (list.isNotEmpty) {
                  response = list.first as Map<String, dynamic>;
                }
              }
            }
          }

          if (response != null) {
            _todayAttendance[student.id] = AttendanceRecord.fromMap(response as Map<String, dynamic>);
          }
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> loadAttendanceHistory({
    required String classroomId,
    required DateTime startDate,
    required DateTime endDate,
    String? studentId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      dynamic data;
      try {
        var query = _supabase
            .from('attendance')
            .select('*, students(first_name, last_name, cedula)')
            .eq('classroom_id', classroomId)
            .gte('date', _dateToString(startDate))
            .lte('date', _dateToString(endDate));

        if (studentId != null) {
          query = query.eq('student_id', studentId);
        }

        data = await query.order('date', ascending: false);
      } catch (_) {}

      if (data == null || (data is List && data.isEmpty)) {
        final adminJwt = await PasswordManagementService.getAdminJwt();
        if (adminJwt != null) {
          final sDate = _dateToString(startDate);
          final eDate = _dateToString(endDate);
          var urlStr =
              '${SupabaseConfig.supabaseUrl}/rest/v1/attendance?classroom_id=eq.$classroomId&date=gte.$sDate&date=lte.$eDate&order=date.desc&select=*';
          if (studentId != null) {
            urlStr += '&student_id=eq.$studentId';
          }
          final resp = await http.get(
            Uri.parse(urlStr),
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
              'Authorization': 'Bearer $adminJwt',
            },
          );
          if (resp.statusCode == 200) {
            data = jsonDecode(resp.body);
          }
        }
      }

      if (data != null && data is List) {
        _attendanceHistory = data
            .map((map) => AttendanceRecord.fromMap(map as Map<String, dynamic>))
            .where((r) => r.status != 'removido' && r.notes != '[DESMARCADO]')
            .toList();
      } else {
        _attendanceHistory = [];
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carga todas las alertas de tardanzas (estudiantes con 2 tardanzas [alerta] o >= 3 [citar representante])
  Future<void> loadTardinessAlerts() async {
    _isLoadingAlerts = true;
    notifyListeners();

    try {
      dynamic data;
      try {
        data = await _supabase
            .from('attendance')
            .select('student_id, date, classroom_id, notes, students(id, first_name, last_name, cedula, photo_url, parent_name, parent_phone, classroom_id, grade, section)')
            .eq('status', 'tardanza')
            .order('date', ascending: false);
      } catch (err) {
        debugPrint('Direct select tardiness failed: $err, executing admin REST fallback');
        final adminJwt = await PasswordManagementService.getAdminJwt();
        if (adminJwt != null) {
          final resp = await http.get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/attendance?status=eq.tardanza&order=date.desc&select=student_id,date,classroom_id,notes,students(id,first_name,last_name,cedula,photo_url,parent_name,parent_phone,classroom_id,grade,section)'),
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
              'Authorization': 'Bearer $adminJwt',
            },
          );
          if (resp.statusCode == 200) {
            data = jsonDecode(resp.body);
          }
        }
      }

      final Map<String, List<DateTime>> studentDates = {};
      final Map<String, Map<String, dynamic>> studentInfo = {};
      final Map<String, String> studentClassrooms = {};
      _studentLateCounts = {};

      if (data != null && data is List) {
        for (final item in data) {
          if (item['notes'] == '[DESMARCADO]') continue;
          final sId = item['student_id'] as String;
          final date = DateTime.tryParse(item['date'] as String) ?? DateTime.now();
          studentDates.putIfAbsent(sId, () => []).add(date);
          if (item['classroom_id'] != null) {
            studentClassrooms[sId] = item['classroom_id'] as String;
          }
          if (item['students'] != null && item['students'] is Map) {
            studentInfo[sId] = Map<String, dynamic>.from(item['students'] as Map);
          }
        }
      }

      final alerts = <TardinessAlert>[];
      for (final entry in studentDates.entries) {
        final sId = entry.key;
        final dates = entry.value;
        _studentLateCounts[sId] = dates.length;

        if (dates.length >= 2) {
          final s = studentInfo[sId] ?? {};
          alerts.add(TardinessAlert(
            studentId: sId,
            studentName: '${s['first_name'] ?? 'Estudiante'} ${s['last_name'] ?? ''}'.trim(),
            cedula: s['cedula'] as String? ?? '',
            gender: (s['gender'] as String?)?.toUpperCase() == 'F' ||
                    (s['photo_url'] as String?) == 'gender:F' ? 'F' : 'M',
            classroomId: s['classroom_id'] as String? ?? studentClassrooms[sId] ?? '',
            grade: s['grade'] as String? ?? '',
            section: s['section'] as String? ?? '',
            parentName: s['parent_name'] as String?,
            parentPhone: s['parent_phone'] as String?,
            lateCount: dates.length,
            lateDates: dates,
          ));
        }
      }

      // Ordenar: Citaciones (>=3) primero, luego por cantidad desc, luego nombre
      alerts.sort((a, b) {
        if (a.isCitation != b.isCitation) {
          return a.isCitation ? -1 : 1;
        }
        final countComp = b.lateCount.compareTo(a.lateCount);
        if (countComp != 0) return countComp;
        return a.studentName.compareTo(b.studentName);
      });

      _tardinessAlerts = alerts;
    } catch (e) {
      debugPrint('Error loading tardiness alerts: $e');
    } finally {
      _isLoadingAlerts = false;
      notifyListeners();
    }
  }

  /// Genera reporte detallado para un salón específico
  Future<List<AttendanceSummary>> generateReport({
    required String classroomId,
    required DateTime startDate,
    required DateTime endDate,
    String? studentId,
  }) async {
    try {
      dynamic data;
      try {
        var query = _supabase
            .from('attendance')
            .select('student_id, status, notes, students(first_name, last_name, cedula, photo_url)')
            .eq('classroom_id', classroomId)
            .gte('date', _dateToString(startDate))
            .lte('date', _dateToString(endDate));

        if (studentId != null) {
          query = query.eq('student_id', studentId);
        }
        data = await query;
      } catch (err) {
        debugPrint('Direct select generateReport failed: $err, executing admin REST fallback');
        final adminJwt = await PasswordManagementService.getAdminJwt();
        if (adminJwt != null) {
          final sDate = _dateToString(startDate);
          final eDate = _dateToString(endDate);
          var urlStr = '${SupabaseConfig.supabaseUrl}/rest/v1/attendance?classroom_id=eq.$classroomId&date=gte.$sDate&date=lte.$eDate&select=student_id,status,notes,students(first_name,last_name,cedula,photo_url)';
          if (studentId != null) {
            urlStr += '&student_id=eq.$studentId';
          }
          final resp = await http.get(
            Uri.parse(urlStr),
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
              'Authorization': 'Bearer $adminJwt',
            },
          );
          if (resp.statusCode == 200) {
            data = jsonDecode(resp.body);
          }
        }
      }

      // Group by student
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      final Map<String, String> studentNames = {};
      final Map<String, String> studentCedulas = {};
      final Map<String, String> studentGenders = {};

      if (data != null && data is List) {
        for (final record in data) {
          if (record['notes'] == '[DESMARCADO]') continue;
          final sId = record['student_id'] as String;
          final student = record['students'] as Map?;
          if (student != null) {
            studentNames[sId] =
                '${student['first_name']} ${student['last_name']}';
            studentCedulas[sId] = student['cedula'] as String? ?? '';
            studentGenders[sId] =
                (student['gender'] as String?)?.toUpperCase() == 'F' ||
                (student['photo_url'] as String?) == 'gender:F' ? 'F' : 'M';
          }
          grouped.putIfAbsent(sId, () => []).add(record as Map<String, dynamic>);
        }
      }

      final summaries = <AttendanceSummary>[];

      for (final entry in grouped.entries) {
        final records = entry.value;
        summaries.add(AttendanceSummary(
          studentId: entry.key,
          studentName: studentNames[entry.key] ?? 'Desconocido',
          cedula: studentCedulas[entry.key] ?? '',
          gender: studentGenders[entry.key] ?? 'M',
          totalDays: records.length,
          presentDays: records.where((r) => r['status'] == 'presente').length,
          absentDays: records.where((r) => r['status'] == 'ausente').length,
          lateDays: records.where((r) => r['status'] == 'tardanza').length,
          justifiedDays:
              records.where((r) => r['status'] == 'justificado').length,
        ));
      }

      summaries.sort((a, b) => a.studentName.compareTo(b.studentName));
      return summaries;
    } catch (e) {
      debugPrint('Error in generateReport: $e');
      return [];
    }
  }

  /// Genera reporte consolidado institucional con la tabla de los 12 salones
  Future<List<ClassroomAttendanceSummary>> generateInstitutionalReport({
    required List<Classroom> classrooms,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // 1. Obtener todos los estudiantes activos, cédula, nombre y su género
      dynamic studentsData;
      try {
        studentsData = await _supabase
            .from('students')
            .select('id, first_name, last_name, cedula, classroom_id, photo_url')
            .eq('is_active', true);
      } catch (_) {}

      if (studentsData == null || (studentsData is List && studentsData.isEmpty)) {
        final jwt = await PasswordManagementService.getAdminJwt();
        if (jwt != null) {
          final resp = await http.get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/students?is_active=eq.true&select=id,first_name,last_name,cedula,classroom_id,photo_url'),
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
              'Authorization': 'Bearer $jwt',
            },
          );
          if (resp.statusCode == 200) {
            studentsData = jsonDecode(resp.body);
          }
        }
      }

      final Map<String, List<Map<String, dynamic>>> studentsByClassroom = {};
      final Map<String, String> studentGenderMap = {};
      final Map<String, Map<String, dynamic>> studentMap = {};

      if (studentsData != null && studentsData is List) {
        for (final s in studentsData) {
          final m = s as Map<String, dynamic>;
          final sId = m['id'] as String;
          final cId = m['classroom_id'] as String;
          final gender = (m['gender'] as String?)?.toUpperCase() == 'F' ||
                  (m['photo_url'] as String?) == 'gender:F'
              ? 'F'
              : 'M';
          studentGenderMap[sId] = gender;
          studentMap[sId] = m;
          studentsByClassroom.putIfAbsent(cId, () => []).add(m);
        }
      }

      // 2. Obtener registros de asistencia en el rango de fechas
      dynamic attendanceData = await _supabase
          .from('attendance')
          .select('classroom_id, student_id, status, date, notes')
          .gte('date', _dateToString(startDate))
          .lte('date', _dateToString(endDate));

      if (attendanceData == null || (attendanceData is List && attendanceData.isEmpty)) {
        final jwt = await PasswordManagementService.getAdminJwt();
        if (jwt != null) {
          final startStr = _dateToString(startDate);
          final endStr = _dateToString(endDate);
          final resp = await http.get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/attendance?date=gte.$startStr&date=lte.$endStr&select=classroom_id,student_id,status,date,notes'),
            headers: {
              'apikey': SupabaseConfig.supabaseAnonKey,
              'Authorization': 'Bearer $jwt',
            },
          );
          if (resp.statusCode == 200) {
            attendanceData = jsonDecode(resp.body);
          }
        }
      }

      final Map<String, List<Map<String, dynamic>>> recordsByClassroom = {};
      if (attendanceData != null && attendanceData is List) {
        for (final r in attendanceData) {
          if (r['notes'] == '[DESMARCADO]' || r['status'] == 'removido') continue;
          final cId = r['classroom_id'] as String;
          recordsByClassroom.putIfAbsent(cId, () => []).add(r as Map<String, dynamic>);
        }
      }

      final List<ClassroomAttendanceSummary> result = [];

      for (final c in classrooms) {
        final classStudents = studentsByClassroom[c.id] ?? [];
        final totalEnrolled = classStudents.length;
        final maleEnrolled = classStudents
            .where((s) => studentGenderMap[s['id'] as String] != 'F')
            .length;
        final femaleEnrolled = classStudents
            .where((s) => studentGenderMap[s['id'] as String] == 'F')
            .length;

        final records = recordsByClassroom[c.id] ?? [];
        final presentCount =
            records.where((r) => r['status'] == 'presente').length;
        final lateCount =
            records.where((r) => r['status'] == 'tardanza').length;
        final justifiedCount =
            records.where((r) => r['status'] == 'justificado').length;

        // Asistentes (Presente o Tardanza): V(A) y H(A)
        final attendingRecords = records.where((r) => r['status'] == 'presente' || r['status'] == 'tardanza');
        int presentMale = 0;
        int presentFemale = 0;
        for (final ar in attendingRecords) {
          final sId = ar['student_id'] as String;
          final gen = studentGenderMap[sId] ?? 'M';
          if (gen == 'F') {
            presentFemale++;
          } else {
            presentMale++;
          }
        }

        // Inasistencias (FALTÓ - Solo ausente): V(I) y H(I)
        final absentRecords =
            records.where((r) => r['status'] == 'ausente').toList();
        final absentCount = absentRecords.length;

        int absentMale = 0;
        int absentFemale = 0;
        final Map<String, int> absentStudentCount = {};
        for (final ar in absentRecords) {
          final sId = ar['student_id'] as String;
          final gen = studentGenderMap[sId] ?? 'M';
          if (gen == 'F') {
            absentFemale++;
          } else {
            absentMale++;
          }
          absentStudentCount[sId] = (absentStudentCount[sId] ?? 0) + 1;
        }

        // Construir lista detallada de estudiantes inasistentes
        final List<AbsentStudentInfo> absentStudentsList = [];
        for (final entry in absentStudentCount.entries) {
          final s = studentMap[entry.key];
          if (s != null) {
            final name = '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.trim();
            absentStudentsList.add(AbsentStudentInfo(
              studentId: entry.key,
              studentName: name.isNotEmpty ? name : 'Estudiante',
              cedula: s['cedula'] as String? ?? '',
              gender: studentGenderMap[entry.key] ?? 'M',
              count: entry.value,
            ));
          }
        }
        absentStudentsList.sort((a, b) => a.studentName.compareTo(b.studentName));

        final distinctDates =
            records.map((r) => r['date'] as String).toSet().length;

        result.add(ClassroomAttendanceSummary(
          classroomId: c.id,
          grade: c.grade,
          section: c.section,
          teacherName: c.teacherName,
          totalEnrolled: totalEnrolled,
          maleEnrolled: maleEnrolled,
          femaleEnrolled: femaleEnrolled,
          presentDays: presentCount,
          presentMaleDays: presentMale,
          presentFemaleDays: presentFemale,
          absentDays: absentCount,
          absentMaleDays: absentMale,
          absentFemaleDays: absentFemale,
          lateDays: lateCount,
          justifiedDays: justifiedCount,
          totalDays: distinctDates > 0 ? distinctDates : 1,
          absentStudents: absentStudentsList,
        ));
      }

      // Ordenar por grado y sección en orden natural: 1A, 1B, 2A, 2B, 3A, 3B, 4A, 4B, 5A, 5B, 6A, 6B
      result.sort((a, b) {
        final numA = int.tryParse(RegExp(r'\d+').firstMatch(a.grade)?.group(0) ?? '0') ?? 0;
        final numB = int.tryParse(RegExp(r'\d+').firstMatch(b.grade)?.group(0) ?? '0') ?? 0;
        if (numA != numB) return numA.compareTo(numB);
        return a.section.compareTo(b.section);
      });

      return result;
    } catch (e) {
      debugPrint('Error generating institutional report: $e');
      return [];
    }
  }

  String getStatusForStudent(String studentId) {
    return _todayAttendance[studentId]?.status ?? '';
  }

  bool hasMarked(String studentId) => _todayAttendance.containsKey(studentId);

  int get markedCount => _todayAttendance.length;

  int get presentCount =>
      _todayAttendance.values.where((r) => r.isPresent).length;
  int get absentCount =>
      _todayAttendance.values.where((r) => r.isAbsent).length;
  int get lateCount => _todayAttendance.values.where((r) => r.isLate).length;

  String _dateToString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void resetForDate(DateTime date) {
    _selectedDate = date;
    _todayAttendance = {};
    notifyListeners();
  }

  @override
  void dispose() {
    // Cancelar suscripción al canal Realtime para evitar memory leaks
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    super.dispose();
  }
}
