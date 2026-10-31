import 'package:equatable/equatable.dart';
import 'package:contro_asistencias/core/utils/validators.dart';

class Student extends Equatable {
  final String id;
  final String cedula; // Cédula escolar o identificador
  final String firstName;
  final String lastName;
  final String gender; // 'M' (Masculino) o 'F' (Femenino)
  final String classroomId;
  final String grade;
  final String section;
  final String? photoUrl;
  final String? parentName;
  final String? parentPhone;
  final String? parentEmail;
  final DateTime? birthDate;
  final bool isActive;
  final DateTime createdAt;

  const Student({
    required this.id,
    required this.cedula,
    required this.firstName,
    required this.lastName,
    this.gender = 'M',
    required this.classroomId,
    required this.grade,
    required this.section,
    this.photoUrl,
    this.parentName,
    this.parentPhone,
    this.parentEmail,
    this.birthDate,
    this.isActive = true,
    required this.createdAt,
  });

  String get fullName => '$firstName $lastName';
  String get displayGrade => '$grade - Sección $section';
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    return '$f$l'.toUpperCase();
  }

  bool get isMale => gender != 'F';
  bool get isFemale => gender == 'F';
  String get genderLabel => gender == 'F' ? 'Femenino' : 'Masculino';
  String get genderAbbr => gender == 'F' ? 'F' : 'M';

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'] as String,
      cedula: map['cedula'] as String? ?? '',
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      gender: (map['gender'] as String?)?.toUpperCase() == 'F' ||
              (map['photo_url'] as String?) == 'gender:F'
          ? 'F'
          : 'M',
      classroomId: map['classroom_id'] as String,
      grade: map['grade'] as String,
      section: map['section'] as String,
      photoUrl: (map['photo_url'] as String?) != null &&
              (map['photo_url'] as String).startsWith('http')
          ? map['photo_url'] as String
          : null,
      parentName: map['parent_name'] as String?,
      parentPhone: map['parent_phone'] as String?,
      parentEmail: map['parent_email'] as String?,
      birthDate: map['birth_date'] != null
          ? DateTime.parse(map['birth_date'] as String)
          : null,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cedula': cedula,
      'first_name': firstName,
      'last_name': lastName,
      'gender': gender,
      'classroom_id': classroomId,
      'grade': grade,
      'section': section,
      'photo_url': (photoUrl != null && photoUrl!.startsWith('http'))
          ? photoUrl
          : 'gender:$gender',
      'parent_name': parentName,
      'parent_phone': parentPhone,
      'parent_email': parentEmail,
      'birth_date': birthDate?.toIso8601String().split('T')[0],
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Creates a Student from CSV row data
  /// CSV format: cedula, first_name, last_name, gender, parent_name, parent_phone, parent_email
  factory Student.fromCsvRow(
    List<dynamic> row,
    String classroomId,
    String grade,
    String section,
  ) {
    // Detect gender if present in columns
    String parsedGender = 'M';
    for (final col in row) {
      final val = col.toString().trim().toUpperCase();
      if (val == 'F' || val == 'FEMENINO' || val == 'HEMBRA' || val == 'H') {
        parsedGender = 'F';
        break;
      } else if (val == 'M' || val == 'MASCULINO' || val == 'VARON' || val == 'V') {
        parsedGender = 'M';
        break;
      }
    }

    return Student(
      id: '', // Will be assigned by Supabase
      cedula: row.isNotEmpty ? row[0].toString().trim() : '',
      firstName: row.length > 1 ? row[1].toString().trim() : '',
      lastName: row.length > 2 ? row[2].toString().trim() : '',
      gender: parsedGender,
      classroomId: classroomId,
      grade: grade,
      section: section,
      parentName: row.length > 3 && row[3].toString().trim().isNotEmpty
          ? row[3].toString().trim()
          : null,
      parentPhone: row.length > 4 && row[4].toString().trim().isNotEmpty
          ? Validators.formatPhone(row[4].toString().trim())
          : null,
      parentEmail: row.length > 5 && row[5].toString().trim().isNotEmpty
          ? row[5].toString().trim().toLowerCase()
          : null,
      createdAt: DateTime.now(),
    );
  }

  Student copyWith({
    String? id,
    String? cedula,
    String? firstName,
    String? lastName,
    String? gender,
    String? classroomId,
    String? grade,
    String? section,
    String? photoUrl,
    String? parentName,
    String? parentPhone,
    String? parentEmail,
    DateTime? birthDate,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Student(
      id: id ?? this.id,
      cedula: cedula ?? this.cedula,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      gender: gender ?? this.gender,
      classroomId: classroomId ?? this.classroomId,
      grade: grade ?? this.grade,
      section: section ?? this.section,
      photoUrl: photoUrl ?? this.photoUrl,
      parentName: parentName ?? this.parentName,
      parentPhone: parentPhone ?? this.parentPhone,
      parentEmail: parentEmail ?? this.parentEmail,
      birthDate: birthDate ?? this.birthDate,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, cedula, firstName, lastName, gender, classroomId, grade, section];
}
