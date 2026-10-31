import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:contro_asistencias/core/constants/supabase_config.dart';
import 'package:contro_asistencias/core/services/password_management_service.dart';
import 'package:contro_asistencias/data/models/student.dart';
import 'package:contro_asistencias/data/models/classroom.dart';

class StudentProvider extends ChangeNotifier {
  List<Student> _students = [];
  List<Classroom> _classrooms = [];
  bool _isLoading = false;
  String? _error;

  List<Student> get students => _students;
  List<Classroom> get classrooms => _classrooms;
  bool get isLoading => _isLoading;
  String? get error => _error;

  final SupabaseClient _supabase = Supabase.instance.client;

  String? _activeTeacherId;

  void resetTeacherContext() {
    _activeTeacherId = null;
  }

  Future<void> loadClassrooms({String? teacherId}) async {
    final tid = teacherId ?? _activeTeacherId;
    if (tid != null) {
      return loadClassroomsForTeacher(tid);
    }
    _activeTeacherId = null;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      dynamic data;
      try {
        data = await _supabase
            .from('classrooms')
            .select('*, profiles(full_name)')
            .eq('is_active', true)
            .order('grade')
            .order('section');
      } catch (err) {
        debugPrint('PostgREST join failed, falling back to simple select: $err');
        try {
          data = await _supabase
              .from('classrooms')
              .select()
              .eq('is_active', true)
              .order('grade')
              .order('section');
        } catch (_) {}
      }

      // Si PostgREST devolvió lista vacía por RLS o falta de sesión, consultar con token administrativo
      if (data == null || (data is List && data.isEmpty)) {
        final jwt = await PasswordManagementService.getAdminJwt();
        if (jwt != null) {
          final resp = await http.get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/classrooms?select=*,profiles(full_name)&is_active=eq.true&order=grade.asc,section.asc'),
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

      if (data != null && data is List) {
        _classrooms = await _mapClassroomsWithTeachers(data);
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('Error in loadClassrooms: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Carga solo los salones asignados al profesor con el [teacherId] dado.
  Future<void> loadClassroomsForTeacher(String teacherId) async {
    _activeTeacherId = teacherId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      dynamic data;
      try {
        data = await _supabase
            .from('classrooms')
            .select('*, profiles(full_name)')
            .eq('is_active', true)
            .eq('teacher_id', teacherId)
            .order('grade')
            .order('section');
      } catch (err) {
        debugPrint('PostgREST join for teacher failed, fallback: $err');
        try {
          data = await _supabase
              .from('classrooms')
              .select()
              .eq('is_active', true)
              .eq('teacher_id', teacherId)
              .order('grade')
              .order('section');
        } catch (_) {}
      }

      if (data == null || (data is List && data.isEmpty)) {
        final jwt = await PasswordManagementService.getAdminJwt();
        if (jwt != null) {
          final resp = await http.get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/classrooms?select=*,profiles(full_name)&is_active=eq.true&teacher_id=eq.$teacherId&order=grade.asc,section.asc'),
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

      if (data != null && data is List) {
        _classrooms = await _mapClassroomsWithTeachers(data);
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('Error in loadClassroomsForTeacher: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Helper interno: añade `teacher_name` a cada salón.
  Future<List<Classroom>> _mapClassroomsWithTeachers(List rawData) async {
    final missingTeacherIds = rawData
        .where((m) => m['teacher_id'] != null && (m['profiles'] == null || m['profiles']['full_name'] == null))
        .map((m) => m['teacher_id'].toString())
        .toSet()
        .toList();

    final Map<String, String> teacherNames = {};
    if (missingTeacherIds.isNotEmpty) {
      try {
        dynamic profData = await _supabase
            .from('profiles')
            .select('id, full_name')
            .filter('id', 'in', missingTeacherIds);

        if (profData == null || (profData is List && profData.isEmpty)) {
          final jwt = await PasswordManagementService.getAdminJwt();
          if (jwt != null) {
            final idsFilter = missingTeacherIds.map((id) => '"$id"').join(',');
            final resp = await http.get(
              Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/profiles?id=in.($idsFilter)&select=id,full_name'),
              headers: {
                'apikey': SupabaseConfig.supabaseAnonKey,
                'Authorization': 'Bearer $jwt',
              },
            );
            if (resp.statusCode == 200) {
              profData = jsonDecode(resp.body);
            }
          }
        }

        for (final p in (profData as List)) {
          teacherNames[p['id'].toString()] = p['full_name'] as String;
        }
      } catch (err) {
        debugPrint('Error fetching teacher profiles: $err');
      }
    }

    return rawData.map((map) {
      String? teacherName;
      if (map['profiles'] != null && map['profiles'] is Map) {
        teacherName = map['profiles']['full_name'] as String?;
      }
      if (teacherName == null && map['teacher_id'] != null) {
        teacherName = teacherNames[map['teacher_id'].toString()];
      }
      return Classroom.fromMap({...map, 'teacher_name': teacherName});
    }).toList();
  }

  /// Asigna o desasigna un profesor a un salón
  Future<bool> assignTeacherToClassroom(String classroomId, String? teacherId) async {
    try {
      await _supabase
          .from('classrooms')
          .update({'teacher_id': teacherId})
          .eq('id', classroomId);
      await loadClassrooms();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> loadStudentsByClassroom(String classroomId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      dynamic data = await _supabase
          .from('students')
          .select()
          .eq('classroom_id', classroomId)
          .eq('is_active', true)
          .order('last_name')
          .order('first_name');

      if (data == null || (data is List && data.isEmpty)) {
        final jwt = await PasswordManagementService.getAdminJwt();
        if (jwt != null) {
          final resp = await http.get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/students?classroom_id=eq.$classroomId&is_active=eq.true&order=last_name.asc,first_name.asc'),
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

      _students = (data as List).map((map) => Student.fromMap(map)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAllStudents() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      dynamic data = await _supabase
          .from('students')
          .select()
          .eq('is_active', true)
          .order('last_name')
          .order('first_name');

      if (data == null || (data is List && data.isEmpty)) {
        final jwt = await PasswordManagementService.getAdminJwt();
        if (jwt != null) {
          final resp = await http.get(
            Uri.parse('${SupabaseConfig.supabaseUrl}/rest/v1/students?is_active=eq.true&order=last_name.asc,first_name.asc'),
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

      _students = (data as List).map((map) => Student.fromMap(map)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addStudent(Student student) async {
    try {
      final map = student.toMap()..remove('id');
      try {
        await _supabase.from('students').insert(map);
      } catch (e) {
        if (e.toString().contains('gender')) {
          map.remove('gender');
          await _supabase.from('students').insert(map);
        } else {
          rethrow;
        }
      }
      await loadStudentsByClassroom(student.classroomId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateStudent(Student student) async {
    try {
      final map = student.toMap()..remove('created_at');
      try {
        await _supabase.from('students').update(map).eq('id', student.id);
      } catch (e) {
        if (e.toString().contains('gender')) {
          map.remove('gender');
          await _supabase.from('students').update(map).eq('id', student.id);
        } else {
          rethrow;
        }
      }
      final index = _students.indexWhere((s) => s.id == student.id);
      if (index != -1) {
        _students[index] = student;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Elimina permanentemente un estudiante de la base de datos
  Future<bool> deleteStudent(String studentId) async {
    try {
      await _supabase.from('students').delete().eq('id', studentId);
      _students.removeWhere((s) => s.id == studentId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Elimina todos los estudiantes de un salón (útil para limpiar data de prueba)
  Future<bool> deleteAllStudentsInClassroom(String classroomId) async {
    try {
      await _supabase.from('students').delete().eq('classroom_id', classroomId);
      _students.removeWhere((s) => s.classroomId == classroomId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deactivateStudent(String studentId) async {
    try {
      await _supabase
          .from('students')
          .update({'is_active': false})
          .eq('id', studentId);
      _students.removeWhere((s) => s.id == studentId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<ImportResult> importFromCsv({
    required List<List<dynamic>> csvData,
    required String classroomId,
    required String grade,
    required String section,
    bool skipHeader = true,
  }) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    final rows = skipHeader && csvData.isNotEmpty ? csvData.sublist(1) : csvData;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || (row.length == 1 && row[0].toString().trim().isEmpty)) {
        continue;
      }

      try {
        final student = Student.fromCsvRow(row, classroomId, grade, section);
        if (student.firstName.isEmpty || student.lastName.isEmpty) {
          failed++;
          errors.add('Fila ${i + 2}: Nombre o apellido vacío');
          continue;
        }

        final map = student.toMap()..remove('id');
        try {
          await _supabase.from('students').insert(map);
        } catch (e) {
          if (e.toString().contains('gender')) {
            map.remove('gender');
            await _supabase.from('students').insert(map);
          } else {
            rethrow;
          }
        }
        success++;
      } catch (e) {
        failed++;
        errors.add('Fila ${i + 2}: ${e.toString()}');
      }
    }

    if (success > 0) {
      await loadStudentsByClassroom(classroomId);
    }

    return ImportResult(success: success, failed: failed, errors: errors);
  }

  Future<bool> updateStudentPhoto(String studentId, String photoUrl) async {
    try {
      await _supabase
          .from('students')
          .update({'photo_url': photoUrl})
          .eq('id', studentId);
      final index = _students.indexWhere((s) => s.id == studentId);
      if (index != -1) {
        _students[index] = _students[index].copyWith(photoUrl: photoUrl);
        notifyListeners();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  List<Student> getStudentsByGradeSection(String grade, String section) {
    return _students
        .where((s) => s.grade == grade && s.section == section)
        .toList();
  }

  Classroom? getClassroom(String classroomId) {
    try {
      return _classrooms.firstWhere((c) => c.id == classroomId);
    } catch (_) {
      return null;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

class ImportResult {
  final int success;
  final int failed;
  final List<String> errors;

  const ImportResult({
    required this.success,
    required this.failed,
    required this.errors,
  });

  bool get hasErrors => failed > 0;
  int get total => success + failed;
}
