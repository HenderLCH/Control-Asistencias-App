import 'package:equatable/equatable.dart';

class Classroom extends Equatable {
  final String id;
  final String grade; // 1er Grado, 2do Grado, etc.
  final String section; // A, B
  final String? teacherId;
  final String? teacherName;
  final int? studentCount;
  final bool isActive;
  final DateTime createdAt;

  const Classroom({
    required this.id,
    required this.grade,
    required this.section,
    this.teacherId,
    this.teacherName,
    this.studentCount,
    this.isActive = true,
    required this.createdAt,
  });

  String get displayName => '$grade - Sección $section';
  String get shortName => '${grade.substring(0, 3)} $section';

  factory Classroom.fromMap(Map<String, dynamic> map) {
    return Classroom(
      id: map['id'] as String,
      grade: map['grade'] as String,
      section: map['section'] as String,
      teacherId: map['teacher_id'] as String?,
      teacherName: map['teacher_name'] as String?,
      studentCount: map['student_count'] as int?,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'grade': grade,
      'section': section,
      'teacher_id': teacherId,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, grade, section, teacherId, isActive];
}
