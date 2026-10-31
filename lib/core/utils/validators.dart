class Validators {
  static const List<String> venezuelanPhonePrefixes = [
    '0414',
    '0424',
    '0412',
    '0416',
    '0426',
    '0422',
  ];

  /// Valida números de teléfono venezolanos con prefijos (0414, 0424, 0412, 0416, 0426, 0422)
  /// Longitud requerida: 11 dígitos.
  static String? validateVenezuelanPhone(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      if (required) return 'El teléfono es requerido';
      return null;
    }

    String clean = value.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');

    // Soporte para formato internacional +58 / 58
    if (clean.startsWith('+58')) {
      clean = '0${clean.substring(3)}';
    } else if (clean.startsWith('58') && clean.length == 12) {
      clean = '0${clean.substring(2)}';
    }

    // Debe contener solo dígitos
    if (!RegExp(r'^\d+$').hasMatch(clean)) {
      return 'El teléfono solo debe contener números';
    }

    // Verificar prefijo de Venezuela
    final hasValidPrefix = venezuelanPhonePrefixes.any((prefix) => clean.startsWith(prefix));
    if (!hasValidPrefix) {
      return 'Debe comenzar con 0414, 0424, 0412, 0416, 0426 o 0422';
    }

    // Debe tener exactamente 11 dígitos
    if (clean.length != 11) {
      return 'Debe tener 11 dígitos (Ej: 0414-1234567)';
    }

    return null;
  }

  /// Valida correo electrónico con formato estándar
  static String? validateEmail(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      if (required) return 'El correo es requerido';
      return null;
    }

    final trimmed = value.trim();
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
    );

    if (!emailRegex.hasMatch(trimmed)) {
      return 'Ingresa un correo electrónico válido (Ej: usuario@correo.com)';
    }

    return null;
  }

  /// Formatea un número limpio a formato legible 0414-1234567
  static String formatPhone(String phone) {
    String clean = phone.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (clean.startsWith('+58')) clean = '0${clean.substring(3)}';
    if (clean.length == 11) {
      return '${clean.substring(0, 4)}-${clean.substring(4)}';
    }
    return phone;
  }

  /// Valida la política obligatoria de contraseñas:
  /// - Mínimo 8 caracteres
  /// - Al menos una letra mayúscula
  /// - Al menos una letra minúscula
  /// - Al menos un número
  /// - Al menos un signo especial (incluido el '.')
  static String? validatePasswordPolicy(String? value) {
    if (value == null || value.isEmpty) {
      return 'La contraseña es requerida';
    }
    if (value.length < 8) {
      return 'Debe tener al menos 8 caracteres';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Debe incluir al menos una letra mayúscula';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Debe incluir al menos una letra minúscula';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Debe incluir al menos un número';
    }
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>\.\-_~`+=/\\[\]]').hasMatch(value)) {
      return 'Debe incluir al menos un carácter especial (ej: . o -)';
    }
    return null;
  }

  /// Verifica individualmente cada criterio de la política de contraseñas
  static Map<String, bool> checkPasswordCriteria(String value) {
    return {
      'length': value.length >= 8,
      'upper': RegExp(r'[A-Z]').hasMatch(value),
      'lower': RegExp(r'[a-z]').hasMatch(value),
      'digit': RegExp(r'[0-9]').hasMatch(value),
      'special': RegExp(r'[!@#\$%^&*(),.?":{}|<>\.\-_~`+=/\\[\]]').hasMatch(value),
    };
  }
}
