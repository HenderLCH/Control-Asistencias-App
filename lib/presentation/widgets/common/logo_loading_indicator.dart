import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/constants/app_constants.dart';

/// Un indicador de carga premium con el logo en miniatura titilando y un loader abajo.
class LogoLoadingIndicator extends StatelessWidget {
  final double size;
  final String? message;
  final Color? messageColor;

  const LogoLoadingIndicator({
    super.key,
    this.size = 56,
    this.message,
    this.messageColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. Logo en miniatura cargando / titilando (logo limpio sin recorte circular)
        SizedBox(
          width: size,
          height: size,
          child: Image.asset(
            AppConstants.logoAsset,
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => const Icon(
              Icons.school_rounded,
              color: AppTheme.primary,
              size: 36,
            ),
          ),
        )
            // Animación de respiración / titileo del logo en miniatura
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              begin: const Offset(0.92, 0.92),
              end: const Offset(1.08, 1.08),
              duration: 700.ms,
              curve: Curves.easeInOut,
            )
            .fade(begin: 0.70, end: 1.0, duration: 700.ms),

        const SizedBox(height: 16),

        // 2. Loader abajo del logo (Spinner circular moderno)
        const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.8,
            strokeCap: StrokeCap.round,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        ),

        // 3. Mensaje de carga
        if (message != null && message!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: messageColor ?? Theme.of(context).textTheme.bodyMedium?.color,
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fade(begin: 0.75, end: 1.0, duration: 800.ms),
        ],
      ],
    );
  }
}

BuildContext? _currentLoadingContext;

/// Muestra un modal de carga bloqueante (anti-doble clic) con el logo titilando y el loader abajo.
void showAppLoading(BuildContext context, {String message = 'Cargando...'}) {
  showDialog(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (ctx) {
      _currentLoadingContext = ctx;
      return PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
            margin: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Theme.of(ctx).dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: LogoLoadingIndicator(
              size: 58,
              message: message,
            ),
          ),
        ),
      );
    },
  );
}

/// Oculta el modal de carga si está abierto
void hideAppLoading(BuildContext context) {
  if (_currentLoadingContext != null && _currentLoadingContext!.mounted) {
    Navigator.of(_currentLoadingContext!).pop();
    _currentLoadingContext = null;
  } else {
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {}
  }
}

/// Ejecuta una acción asíncrona previniendo clics repetidos y mostrando el modal con logo.
Future<T> runWithLoading<T>(
  BuildContext context,
  Future<T> Function() asyncAction, {
  String message = 'Procesando...',
}) async {
  showAppLoading(context, message: message);
  try {
    final result = await asyncAction();
    return result;
  } finally {
    if (context.mounted) {
      hideAppLoading(context);
    }
  }
}
