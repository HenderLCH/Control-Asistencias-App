import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:contro_asistencias/providers/auth_provider.dart';
import 'package:contro_asistencias/providers/theme_provider.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/constants/app_constants.dart';
import 'package:contro_asistencias/core/services/password_management_service.dart';
import 'package:contro_asistencias/presentation/widgets/common/logo_loading_indicator.dart';
import 'package:contro_asistencias/presentation/widgets/legal/legal_documents_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onTextChanged);
    _passwordController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  void dispose() {
    _emailController.removeListener(_onTextChanged);
    _passwordController.removeListener(_onTextChanged);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _errorMessage = null);

    final authProvider = context.read<AuthProvider>();
    final success = await runWithLoading<bool>(
      context,
      () => authProvider.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
      message: 'Iniciando sesión...',
    );

    if (success && mounted) {
      context.go('/dashboard');
    } else if (!success && mounted) {
      final msg = authProvider.errorMessage ??
          'Correo o contraseña incorrectos. Verifica tus datos o solicita un cambio de contraseña.';
      setState(() {
        _errorMessage = msg;
      });
    }
  }

  void _showForgotPasswordModal() {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF162032) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isDark ? Colors.white.withOpacity(0.12) : AppTheme.divider,
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_reset_rounded,
                  color: AppTheme.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '¿Olvidaste tu contraseña?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppTheme.onBackground,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ingresa tu correo electrónico registrado. Se enviará una notificación inmediata al Administrador para que genere una nueva contraseña para tu cuenta desde el Panel de Gestión de Usuarios.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.onBackground,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  labelText: 'Correo institucional',
                  hintText: 'ej. profesor@gmail.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E2D42) : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white.withOpacity(0.15) : AppTheme.divider,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.accent, width: 2),
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final email = emailCtrl.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor, ingresa un correo válido.'),
                      backgroundColor: AppTheme.error,
                    ),
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();

                await runWithLoading(
                  context,
                  () => PasswordManagementService.requestPasswordReset(email),
                  message: 'Notificando al administrador...',
                );

                if (mounted) {
                  _showResetSuccessDialog(email);
                }
              },
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('Notificar al Administrador'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showResetSuccessDialog(String email) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF162032) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 26),
            SizedBox(width: 10),
            Text(
              'Solicitud Registrada',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          'Se ha notificado al Administrador sobre el usuario ($email).\n\nEl administrador generará tu nueva contraseña desde el Panel de Gestión de Usuarios y te la suministrará para que puedas ingresar.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFFCBD5E1) : AppTheme.onBackground,
            height: 1.4,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0D1421),
              Color(0xFF16243B),
              Color(0xFF1E3A5F),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Theme toggle button at top right
              Positioned(
                top: 12,
                right: 16,
                child: Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => themeProvider.toggleTheme(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                color: isDark ? const Color(0xFFFFD600) : Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isDark ? 'Modo Claro' : 'Modo Oscuro',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),

                      // Logo Oficial del Colegio
                      Container(
                        width: 90,
                        height: 90,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            AppConstants.logoAsset,
                            fit: BoxFit.contain,
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 500.ms)
                          .scale(begin: const Offset(0.85, 0.85)),

                      const SizedBox(height: 16),

                      // Title
                      const Text(
                        AppConstants.institutionName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 150.ms, duration: 400.ms)
                          .slideY(begin: 0.15),

                      const SizedBox(height: 10),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: const Text(
                          'Sistema de Control de Asistencias',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

                      const SizedBox(height: 28),

                      // Login Card - Perfectly tailored for Light and Dark modes
                      Container(
                        constraints: const BoxConstraints(maxWidth: 440),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF162032) : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.12)
                                : const Color(0xFFE2E8F0),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.45 : 0.15),
                              blurRadius: 32,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(28),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Iniciar Sesión',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : AppTheme.onBackground,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Ingresa tus credenciales para continuar',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 22),

                              // ALERTA DE ERROR VISIBLE Y DESTACADA
                              if (_errorMessage != null) ...[
                                Container(
                                  margin: const EdgeInsets.only(bottom: 20),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.error.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.error.withOpacity(0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: AppTheme.error,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Credenciales Incorrectas',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.error,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _errorMessage!,
                                              style: TextStyle(
                                                color: isDark
                                                    ? const Color(0xFFF1F5F9)
                                                    : const Color(0xFF334155),
                                                fontSize: 12,
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => setState(() => _errorMessage = null),
                                        child: const Padding(
                                          padding: EdgeInsets.all(2),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: AppTheme.error,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ).animate().shake(duration: 400.ms),
                              ],

                              // Email field with high contrast
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                style: TextStyle(
                                  color: isDark ? Colors.white : AppTheme.onBackground,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Correo electrónico',
                                  labelStyle: TextStyle(
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : AppTheme.textSecondary,
                                    fontSize: 14,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.email_outlined,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : AppTheme.textSecondary,
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF1E2D42)
                                      : const Color(0xFFF8FAFC),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white.withOpacity(0.15)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: AppTheme.accent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Ingresa tu correo';
                                  }
                                  if (!value.contains('@')) {
                                    return 'Correo inválido';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 16),

                              // Password field with high contrast
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _handleLogin(),
                                style: TextStyle(
                                  color: isDark ? Colors.white : AppTheme.onBackground,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  labelStyle: TextStyle(
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : AppTheme.textSecondary,
                                    fontSize: 14,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.lock_outline_rounded,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : AppTheme.textSecondary,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : AppTheme.textSecondary,
                                    ),
                                    onPressed: () => setState(
                                      () => _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF1E2D42)
                                      : const Color(0xFFF8FAFC),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white.withOpacity(0.15)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: AppTheme.accent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Ingresa tu contraseña';
                                  }
                                  if (value.length < 6) {
                                    return 'Mínimo 6 caracteres';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 8),

                              // ¿OLVIDASTE TU CONTRASEÑA? LINK
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _showForgotPasswordModal,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    '¿Olvidaste tu contraseña?',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppTheme.accentLight
                                          : AppTheme.primary,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Login button
                              Consumer<AuthProvider>(
                                builder: (context, auth, _) {
                                  return SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: auth.isLoading ? null : _handleLogin,
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        backgroundColor: isDark
                                            ? AppTheme.accent
                                            : AppTheme.primary,
                                        elevation: isDark ? 2 : 0,
                                      ),
                                      child: auth.isLoading
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor:
                                                    AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                              ),
                                            )
                                          : Text(
                                              'Ingresar',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: isDark
                                                    ? const Color(0xFF0F172A)
                                                    : Colors.white,
                                              ),
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 350.ms, duration: 500.ms)
                          .slideY(begin: 0.2),

                      const SizedBox(height: 22),

                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          TextButton(
                            onPressed: () => LegalDocumentsDialog.show(
                              context,
                              initialTab: LegalDocType.privacy,
                              userEmail: _emailController.text.trim(),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Política de Privacidad',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.8),
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white54,
                              ),
                            ),
                          ),
                          Text(
                            '•',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                          ),
                          TextButton(
                            onPressed: () => LegalDocumentsDialog.show(
                              context,
                              initialTab: LegalDocType.terms,
                              userEmail: _emailController.text.trim(),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Términos de Uso',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.8),
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white54,
                              ),
                            ),
                          ),
                          Text(
                            '•',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                          ),
                          TextButton(
                            onPressed: () => LegalDocumentsDialog.show(
                              context,
                              initialTab: LegalDocType.accountDeletion,
                              userEmail: _emailController.text.trim(),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Eliminar Cuenta',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.8),
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white54,
                              ),
                            ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 450.ms),

                      const SizedBox(height: 8),

                      Text(
                        '© 2026 ${AppConstants.institutionShort} • Uso Institucional (+18)',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ).animate().fadeIn(delay: 500.ms),

                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
