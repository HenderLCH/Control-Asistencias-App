import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:contro_asistencias/core/theme/app_theme.dart';
import 'package:contro_asistencias/core/constants/app_constants.dart';

/// Encabezado / Hero institucional oficial con el logo del colegio
class InstitutionalHeader extends StatelessWidget {
  final bool compact;
  final bool isDarkBackground;
  final Widget? trailing;

  const InstitutionalHeader({
    super.key,
    this.compact = false,
    this.isDarkBackground = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDarkBackground ? Colors.white : Theme.of(context).textTheme.titleLarge?.color;
    final subtextColor = isDarkBackground
        ? Colors.white.withOpacity(0.85)
        : Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.textSecondary;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 20,
        vertical: compact ? 12 : 18,
      ),
      decoration: BoxDecoration(
        color: isDarkBackground
            ? Colors.transparent
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: isDarkBackground
            ? null
            : Border.all(color: Theme.of(context).dividerColor),
        boxShadow: isDarkBackground
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        children: [
          // Logo del colegio
          Container(
            width: compact ? 46 : 60,
            height: compact ? 46 : 60,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                AppConstants.logoAsset,
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) => const Icon(
                  Icons.school_rounded,
                  color: AppTheme.primary,
                  size: 30,
                ),
              ),
            ),
          )
              .animate()
              .scale(begin: const Offset(0.9, 0.9), duration: 400.ms)
              .fadeIn(),

          SizedBox(width: compact ? 12 : 16),

          // Textos institucionales
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppConstants.institutionName,
                  style: TextStyle(
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: compact ? 12 : 14,
                      color: isDarkBackground ? AppTheme.accent : AppTheme.primary,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        AppConstants.institutionLocation,
                        style: TextStyle(
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                          color: subtextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Hero Banner oficial completo para la pantalla de Inicio
class InstitutionalHeroBanner extends StatelessWidget {
  const InstitutionalHeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E3A8A),
            Color(0xFF2563EB),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decoración geométrica de fondo
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: -40,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent.withOpacity(0.12),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                // Logo enmarcado
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      AppConstants.logoAsset,
                      fit: BoxFit.contain,
                    ),
                  ),
                ).animate().scale(begin: const Offset(0.85, 0.85)).fadeIn(),

                const SizedBox(width: 16),

                // Textos
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
                        ),
                        child: const Text(
                          'SISTEMA DE ASISTENCIA',
                          style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        AppConstants.institutionName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 13, color: AppTheme.accent),
                          const SizedBox(width: 4),
                          Text(
                            AppConstants.institutionLocation,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05);
  }
}
