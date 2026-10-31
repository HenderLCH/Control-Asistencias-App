import 'package:equatable/equatable.dart';

class AttendanceRecord extends Equatable {
  final String id;
  final String studentId;
  final String classroomId;
  final DateTime date;
  final String status; // presente, ausente, tardanza, justificado
  final String? notes;
  final String? markedById; // Teacher/coordinator who marked it
  final DateTime? markedAt;

  const AttendanceRecord({
    required this.id,
    required this.studentId,
    required this.classroomId,
    required this.date,
    required this.status,
    this.notes,
    this.markedById,
    this.markedAt,
  });

  bool get isPresent => status == 'presente';
  bool get isAbsent => status == 'ausente';
  bool get isLate => status == 'tardanza';
  bool get isJustified => status == 'justificado';

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    return AttendanceRecord(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      classroomId: map['classroom_id'] as String,
      date: DateTime.parse(map['date'] as String),
      status: map['status'] as String,
      notes: map['notes'] as String?,
      markedById: map['marked_by_id'] as String?,
      markedAt: map['marked_at'] != null
          ? DateTime.parse(map['marked_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'classroom_id': classroomId,
      'date': date.toIso8601String().split('T')[0],
      'status': status,
      'notes': notes,
      'marked_by_id': markedById,
      'marked_at': markedAt?.toIso8601String(),
    };
  }

  AttendanceRecord copyWith({
    String? id,
    String? studentId,
    String? classroomId,
    DateTime? date,
    String? status,
    String? notes,
    String? markedById,
    DateTime? markedAt,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      classroomId: classroomId ?? this.classroomId,
      date: date ?? this.date,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      markedById: markedById ?? this.markedById,
      markedAt: markedAt ?? this.markedAt,
    );
  }

  @override
  List<Object?> get props => [id, studentId, classroomId, date, status, notes];
}

class AttendanceSummary {
  final String studentId;
  final String studentName;
  final String cedula;
  final String gender; // 'M' o 'F'
  final int totalDays;
  final int presentDays;
  final int absentDays; // Inasistencias (FALTÓ)
  final int lateDays;   // Tardanzas (Llegó tarde, NO faltó)
  final int justifiedDays; // Justificados (Con razón válida, NO faltó)

  const AttendanceSummary({
    required this.studentId,
    required this.studentName,
    this.cedula = '',
    this.gender = 'M',
    required this.totalDays,
    required this.presentDays,
    required this.absentDays,
    required this.lateDays,
    required this.justifiedDays,
  });

  bool get isMale => gender != 'F';
  bool get isFemale => gender == 'F';
  String get genderLabel => gender == 'F' ? 'Femenino' : 'Masculino';
  String get genderAbbr => gender == 'F' ? 'F' : 'M';

  /// Tasa de asistencia: presentes + tardanzas (porque tardanza llegó tarde, no faltó)
  double get attendanceRate =>
      totalDays > 0 ? (presentDays + lateDays) / totalDays * 100 : 0;

  /// Tasa de inasistencia: solo ausentes cuentan como inasistencia
  double get absenceRate =>
      totalDays > 0 ? absentDays / totalDays * 100 : 0;
}

/// Información resumida de un estudiante inasistente para el reporte
class AbsentStudentInfo {
  final String studentId;
  final String studentName;
  final String cedula;
  final String gender; // 'M' o 'F'
  final int count;

  const AbsentStudentInfo({
    required this.studentId,
    required this.studentName,
    this.cedula = '',
    this.gender = 'M',
    this.count = 1,
  });

  bool get isMale => gender != 'F';
  bool get isFemale => gender == 'F';
  String get genderBadge => gender == 'F' ? 'H' : 'V';
}

/// Resumen de asistencia consolidado por salón para el reporte de los 12 salones
class ClassroomAttendanceSummary {
  final String classroomId;
  final String grade;
  final String section;
  final String? teacherName;
  final int totalEnrolled;
  final int maleEnrolled;
  final int femaleEnrolled;
  final int presentDays;       // Total presentes
  final int presentMaleDays;   // V(A) - Varones Asistentes
  final int presentFemaleDays; // H(A) - Hembras Asistentes
  final int absentDays;        // FALTÓ (Inasistencias)
  final int absentMaleDays;    // V(I) - Inasistencias Varones
  final int absentFemaleDays;  // H(I) - Inasistencias Hembras
  final int lateDays;          // Tardanzas (Llegó tarde, no faltó)
  final int justifiedDays;     // Justificados
  final int totalDays;
  final List<AbsentStudentInfo> absentStudents;

  const ClassroomAttendanceSummary({
    required this.classroomId,
    required this.grade,
    required this.section,
    this.teacherName,
    required this.totalEnrolled,
    required this.maleEnrolled,
    required this.femaleEnrolled,
    required this.presentDays,
    this.presentMaleDays = 0,
    this.presentFemaleDays = 0,
    required this.absentDays,
    required this.absentMaleDays,
    required this.absentFemaleDays,
    required this.lateDays,
    required this.justifiedDays,
    required this.totalDays,
    this.absentStudents = const [],
  });

  String get displayName => '$grade - Sección $section';

  /// Código corto del salón (ej: 1A, 1B, 2A, ...)
  String get classroomCode {
    final match = RegExp(r'\d+').firstMatch(grade);
    final num = match != null ? match.group(0) : (grade.isNotEmpty ? grade[0] : '');
    return '$num$section';
  }

  /// Formato con profesor titular como en la nómina (ej: 1A - Maria)
  String get displayNameWithTeacher {
    final t = (teacherName != null && teacherName!.trim().isNotEmpty)
        ? teacherName!.trim()
        : 'Sin asignar';
    return '$classroomCode - $t';
  }

  /// Total Asistencia: V(A) + H(A)
  int get totalAssistance => presentMaleDays + presentFemaleDays;

  /// Total Inasistencia: V(I) + H(I)
  int get totalAbsence => absentMaleDays + absentFemaleDays;

  int get totalRecords => presentDays + absentDays + lateDays + justifiedDays;

  double get attendanceRate =>
      totalRecords > 0 ? (presentDays + lateDays) / totalRecords * 100 : 0;

  double get absenceRate =>
      totalRecords > 0 ? absentDays / totalRecords * 100 : 0;
}

/// Alerta de tardanza para coordinadores y administradores
class TardinessAlert {
  final String studentId;
  final String studentName;
  final String cedula;
  final String gender;
  final String classroomId;
  final String grade;
  final String section;
  final String? parentName;
  final String? parentPhone;
  final int lateCount;
  final List<DateTime> lateDates;

  const TardinessAlert({
    required this.studentId,
    required this.studentName,
    required this.cedula,
    this.gender = 'M',
    required this.classroomId,
    required this.grade,
    required this.section,
    this.parentName,
    this.parentPhone,
    required this.lateCount,
    required this.lateDates,
  });

  bool get isCitation => lateCount >= 3;
  bool get isWarning => lateCount == 2;
  String get classroomDisplayName => '$grade - Sección $section';
}
