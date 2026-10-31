import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/utils/validators.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';

class ChangePasswordDialog extends StatefulWidget {
  final bool isForced;

  const ChangePasswordDialog({
    super.key,
    this.isForced = false,
  });

  /// Muestra el diálogo en pantalla.
  /// Si [isForced] es true, bloquea el cierre involuntario hasta completar el cambio.
  static Future<bool?> show(BuildContext context, {bool isForced = false}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: !isForced,
      builder: (ctx) => PopScope(
        canPop: !isForced,
        child: ChangePasswordDialog(isForced: isForced),
      ),
    );
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _newPasswordCtrl.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    final newPwd = _newPasswordCtrl.text.trim();
    final confirmPwd = _confirmPasswordCtrl.text.trim();

    if (newPwd != confirmPwd) {
      setState(() => _errorMessage = 'Las contraseñas no coinciden');
      return;
    }

    final policyError = Validators.validatePasswordPolicy(newPwd);
    if (policyError != null) {
      setState(() => _errorMessage = policyError);
      return;
    }

    setState(() => _isSaving = true);

    final auth = context.read<AuthProvider>();
    final success = await auth.changePassword(newPwd);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text('¡Contraseña actualizada exitosamente! Ya puedes usar la app.'),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorMessage = auth.errorMessage ?? 'Error al actualizar la contraseña';
      });
    }
  }

  Widget _buildRequirementItem({
    required String label,
    required bool isMet,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: isMet
                ? AppTheme.success
                : (isDark ? const Color(0xFF64748B) : AppTheme.textSecondary.withOpacity(0.6)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isMet ? FontWeight.w600 : FontWeight.w400,
                color: isMet
                    ? (isDark ? Colors.white : AppTheme.onBackground)
                    : (isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final criteria = Validators.checkPasswordCriteria(_newPasswordCtrl.text);

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF162032) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isDark ? Colors.white.withOpacity(0.12) : AppTheme.divider,
        ),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_reset_rounded,
              color: AppTheme.accent,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isForced ? 'Primer Inicio de Sesión' : 'Cambiar Contraseña',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppTheme.onBackground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.isForced
                      ? 'Por seguridad, debes establecer una contraseña personal antes de continuar.'
                      : 'Establece tu nueva contraseña segura.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppTheme.error,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Campo: Nueva Contraseña
              TextFormField(
                controller: _newPasswordCtrl,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'Nueva Contraseña *',
                  hintText: 'Mínimo 8 caracteres',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) => Validators.validatePasswordPolicy(v),
              ),
              const SizedBox(height: 12),

              // Campo: Confirmar Contraseña
              TextFormField(
                controller: _confirmPasswordCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirmar Nueva Contraseña *',
                  hintText: 'Repite la contraseña',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Confirma tu contraseña';
                  if (v != _newPasswordCtrl.text) return 'Las contraseñas no coinciden';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Requisitos de la política
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.08) : AppTheme.divider,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Requisitos de seguridad:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white70 : AppTheme.onBackground.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildRequirementItem(
                      label: 'Mínimo 8 caracteres',
                      isMet: criteria['length'] ?? false,
                      isDark: isDark,
                    ),
                    _buildRequirementItem(
                      label: 'Al menos 1 letra mayúscula (A-Z)',
                      isMet: criteria['upper'] ?? false,
                      isDark: isDark,
                    ),
                    _buildRequirementItem(
                      label: 'Al menos 1 letra minúscula (a-z)',
                      isMet: criteria['lower'] ?? false,
                      isDark: isDark,
                    ),
                    _buildRequirementItem(
                      label: 'Al menos 1 número (0-9)',
                      isMet: criteria['digit'] ?? false,
                      isDark: isDark,
                    ),
                    _buildRequirementItem(
                      label: 'Al menos 1 signo especial (incluido el punto ".")',
                      isMet: criteria['special'] ?? false,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!widget.isForced)
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
        SizedBox(
          width: widget.isForced ? double.infinity : null,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(widget.isForced ? 'Establecer Contraseña y Entrar' : 'Guardar Contraseña'),
          ),
        ),
      ],
    );
  }
}
