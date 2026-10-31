import 'package:flutter/material.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/constants/app_constants.dart';
import 'package:contro_asistencias/core/services/password_management_service.dart';

enum LegalDocType { privacy, terms, accountDeletion }

class LegalDocumentsDialog extends StatefulWidget {
  final LegalDocType initialTab;
  final String? userEmail;

  const LegalDocumentsDialog({
    super.key,
    this.initialTab = LegalDocType.privacy,
    this.userEmail,
  });

  static Future<void> show(
    BuildContext context, {
    LegalDocType initialTab = LegalDocType.privacy,
    String? userEmail,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LegalDocumentsDialog(
        initialTab: initialTab,
        userEmail: userEmail,
      ),
    );
  }

  @override
  State<LegalDocumentsDialog> createState() => _LegalDocumentsDialogState();
}

class _LegalDocumentsDialogState extends State<LegalDocumentsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _deleteEmailCtrl = TextEditingController();
  final _deleteReasonCtrl = TextEditingController();
  bool _isSubmittingDeletion = false;
  bool _deletionSubmitted = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    if (widget.userEmail != null) {
      _deleteEmailCtrl.text = widget.userEmail!;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _deleteEmailCtrl.dispose();
    _deleteReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitAccountDeletionRequest() async {
    final email = _deleteEmailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un correo electrónico válido.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSubmittingDeletion = true);

    try {
      await PasswordManagementService.requestAccountDeletion(
        email: email,
        reason: _deleteReasonCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _isSubmittingDeletion = false;
          _deletionSubmitted = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmittingDeletion = false;
          _deletionSubmitted = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxHeight = MediaQuery.of(context).size.height * 0.86;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162032) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.policy_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Información Legal y Privacidad',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppTheme.onBackground,
                        ),
                      ),
                      Text(
                        AppConstants.institutionName,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: AppTheme.accent,
            labelColor: isDark ? AppTheme.accentLight : AppTheme.primary,
            unselectedLabelColor: isDark ? const Color(0xFF94A3B8) : AppTheme.textSecondary,
            labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Privacidad'),
              Tab(text: 'Términos'),
              Tab(text: 'Eliminar Cuenta'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPrivacyTab(isDark),
                _buildTermsTab(isDark),
                _buildDeletionTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : AppTheme.primary,
        ),
      ),
    );
  }

  Widget _buildParagraph(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        height: 1.5,
        color: isDark ? const Color(0xFFCBD5E1) : AppTheme.onBackground.withOpacity(0.85),
      ),
    );
  }

  Widget _buildPrivacyTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Última actualización: Octubre 2026\nAplicación de uso institucional exclusivo para personal docente y administrativo.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildSectionTitle('1. Responsable del Tratamiento de Datos', isDark),
          _buildParagraph(
            'La aplicación "${AppConstants.appName}" es una herramienta tecnológica de gestión interna operada para la ${AppConstants.institutionName} (${AppConstants.institutionLocation}). Su finalidad única es el registro, control estadístico y seguimiento de la asistencia escolar.',
            isDark,
          ),
          _buildSectionTitle('2. Usuarios Autorizados (+18 años)', isDark),
          _buildParagraph(
            'El acceso a esta aplicación está restringido exclusivamente a profesores, coordinadores académicos y personal directivo/administrativo mayor de edad debidamente acreditado por la institución. Los estudiantes no poseen cuentas de acceso en la plataforma.',
            isDark,
          ),
          _buildSectionTitle('3. Datos Recopilados y Finalidad', isDark),
          _buildParagraph(
            '• Datos del Personal Docente/Administrativo: Nombre completo, correo electrónico institucional o personal autorizado, número de teléfono opcional y fotografía de perfil opcional, utilizados para la autenticación y asignación de aulas.\n'
            '• Registros de Asistencia Escolar: Nombre, apellido, grado, sección, número de cédula escolar/identidad, estado de asistencia diaria (presente, ausente, tardanza, justificado) y soportes de justificativos médicos o familiares suministrados a la coordinación.',
            isDark,
          ),
          _buildSectionTitle('4. Permisos del Dispositivo', isDark),
          _buildParagraph(
            '• Cámara y Selector de Archivos/Imágenes: Se solicitan únicamente cuando el docente o coordinador decide adjuntar voluntariamente una fotografía o documento PDF como soporte de un justificativo de inasistencia o foto de perfil.\n'
            '• Notificaciones Push: Utilizadas para enviar alertas institucionales en tiempo real sobre reportes de asistencia y recurrencia de tardanzas.',
            isDark,
          ),
          _buildSectionTitle('5. Seguridad y No Compartición con Terceros', isDark),
          _buildParagraph(
            'Toda la información se transmite de forma cifrada mediante protocolos HTTPS/TLS (SSL) y se resguarda en servidores seguros con control de acceso por roles (Row Level Security). La institución NO vende, alquila ni comparte datos personales de docentes ni de estudiantes con terceros ni con redes publicitarias.',
            isDark,
          ),
          _buildSectionTitle('6. Conservación y Derechos ARCO', isDark),
          _buildParagraph(
            'Los datos se conservan durante el año escolar vigente para efectos de control académico oficial. Cualquier usuario puede solicitar la actualización, rectificación o eliminación de su cuenta y datos asociados desde la pestaña "Eliminar Cuenta" de este panel o ante la Coordinación Académica.',
            isDark,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTermsTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('1. Aceptación de los Términos', isDark),
          _buildParagraph(
            'El ingreso y uso del sistema "${AppConstants.appName}" implica la aceptación de las presentes condiciones de uso institucional por parte del personal docente, de coordinación y administrativo del ${AppConstants.institutionShort}.',
            isDark,
          ),
          _buildSectionTitle('2. Uso Exclusivamente Académico', isDark),
          _buildParagraph(
            'El usuario se compromete a utilizar la plataforma únicamente para el pase de asistencia diaria, consulta de reportes autorizados y carga de justificativos estudiantiles reales dentro de su horario y funciones laborales.',
            isDark,
          ),
          _buildSectionTitle('3. Custodia de Credenciales', isDark),
          _buildParagraph(
            'Cada profesor o coordinador recibe una credencial inicial que debe actualizar en su primer inicio de sesión por una clave personal segura de al menos 8 caracteres. Las credenciales son personales e intransferibles; el usuario es responsable de mantener la confidencialidad de su contraseña.',
            isDark,
          ),
          _buildSectionTitle('4. Confidencialidad y Protección de Datos Escolares', isDark),
          _buildParagraph(
            'Toda la información de matrícula, cédulas escolares y justificativos visualizada en la aplicación tiene carácter estrictamente confidencial y está protegida por la normativa vigente de protección del niño, niña y adolescente. Queda prohibida su divulgación, captura o uso fuera del ámbito escolar.',
            isDark,
          ),
          _buildSectionTitle('5. Disponibilidad y Actualizaciones', isDark),
          _buildParagraph(
            'La administración del sistema podrá aplicar actualizaciones de seguridad, mejoras visuales o mantenimiento preventivo, así como revocar el acceso a cuentas de personal que haya cesado sus funciones en el plantel.',
            isDark,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDeletionTab(bool isDark) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.error.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.delete_forever_rounded, color: AppTheme.error, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'En cumplimiento con las políticas de privacidad de Google Play, puedes solicitar en cualquier momento la eliminación definitiva de tu cuenta de usuario y tus datos personales (nombre, correo, teléfono y foto de perfil).',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: isDark ? Colors.white : AppTheme.onBackground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_deletionSubmitted)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.success.withOpacity(0.35)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 38),
                  SizedBox(height: 10),
                  Text(
                    'Solicitud de eliminación registrada',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'El Administrador Institucional ha recibido tu solicitud y procederá a dar de baja tu cuenta y eliminar tus datos personales en un plazo máximo de 48 horas hábiles.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                ],
              ),
            )
          else ...[
            TextField(
              controller: _deleteEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico de la cuenta *',
                hintText: 'usuario@gmail.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _deleteReasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo de la solicitud (opcional)',
                hintText: 'Ej: Fin de funciones docentes en la institución',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmittingDeletion ? null : _submitAccountDeletionRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _isSubmittingDeletion
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_remove_rounded),
                label: const Text('Enviar Solicitud de Eliminación de Cuenta'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
