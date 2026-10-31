import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  final String id;
  final String email;
  final String fullName;
  final String role; // administrador, coordinador, profesor
  final String? avatarUrl;
  final String? phone;
  final bool isActive;
  final DateTime createdAt;

  UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.avatarUrl,
    this.phone,
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static String? sanitizePhone(String? rawPhone) {
    if (rawPhone == null) return null;
    final cleaned = rawPhone
        .replaceAll(RegExp(r'\[RESET_REQ\]'), '')
        .replaceAll(RegExp(r'\[(?:TEMP_PWD|PWD):[^\]]+\]'), '')
        .replaceAll('[FORCE_PWD_CHANGE]', '')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  String? get cleanPhone => sanitizePhone(phone);

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final rawPhone = map['phone'] as String?;
    return UserProfile(
      id: map['id'] as String,
      email: map['email'] as String,
      fullName: map['full_name'] as String,
      role: map['role'] as String,
      avatarUrl: map['avatar_url'] as String?,
      phone: rawPhone,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'role': role,
      'avatar_url': avatarUrl,
      'phone': phone,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? email,
    String? fullName,
    String? role,
    String? avatarUrl,
    String? phone,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isAdmin => role == 'administrador';
  bool get isCoordinator => role == 'coordinador';
  bool get isTeacher => role == 'profesor';
  bool get canManageUsers => isAdmin;
  bool get canImportData => isAdmin;
  bool get canAssignTeachers => isAdmin || isCoordinator;

  /// Indica si este usuario tiene una solicitud pendiente de cambio de contraseña
  bool get hasResetRequest {
    if (phone == null) return false;
    return phone!.contains('[RESET_REQ]');
  }

  /// Retorna la contraseña temporal o asignada visible para el administrador
  String? get tempPassword {
    if (phone == null) return null;
    final match = RegExp(r'\[(?:TEMP_PWD|PWD):([^\]]+)\]').firstMatch(phone!);
    return match?.group(1);
  }

  /// Retorna la contraseña actual asignada o gestionada visible para el administrador
  String? get currentPassword => tempPassword;

  /// Indica si el usuario debe cambiar su contraseña obligatoriamente
  bool get mustChangePassword {
    if (phone == null) return false;
    return phone!.contains('[FORCE_PWD_CHANGE]');
  }

  /// Retorna el número de teléfono limpio para mostrar en la interfaz
  String? get displayPhone {
    if (phone == null) return null;
    final cleaned = phone!
        .replaceAll(RegExp(r'\[RESET_REQ\]'), '')
        .replaceAll(RegExp(r'\[(?:TEMP_PWD|PWD):[^\]]+\]'), '')
        .replaceAll('[FORCE_PWD_CHANGE]', '')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  @override
  List<Object?> get props => [id, email, fullName, role, avatarUrl, phone, isActive];
}
