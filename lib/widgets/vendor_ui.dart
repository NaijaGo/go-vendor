import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class VendorUi {
  static const Color deepNavyBlue = AppColors.royalBlue;
  static const Color greenYellow = AppColors.lightBlue;
  static const Color whiteBackground = Colors.white;
  static const Color blue = AppColors.royalBlue;
  static const Color surface = AppColors.background;
  static const Color border = AppColors.border;
  static const Color softText = Color(0xFFD9E4F6);
  static const Color textMuted = AppColors.mutedText;
  static const Color success = AppColors.green;
  static const Color warning = Color(0xFFE0A325);
  static const Color danger = Color(0xFFC64848);

  static final ThemeData theme = AppTheme.lightTheme;

  static BoxDecoration panelDecoration({
    Color color = whiteBackground,
    double radius = 24,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
      boxShadow: [
        BoxShadow(
          color: deepNavyBlue.withValues(alpha: 0.06),
          blurRadius: 20,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  static BoxDecoration heroDecoration() {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [deepNavyBlue, blue],
      ),
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: deepNavyBlue.withValues(alpha: 0.18),
          blurRadius: 30,
          offset: const Offset(0, 16),
        ),
      ],
    );
  }
}

class VendorPageHero extends StatelessWidget {
  final String badge;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> stats;

  const VendorPageHero({
    super.key,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.stats = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: VendorUi.heroDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _VendorHeroBadge(label: badge)),
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: VendorUi.whiteBackground.withValues(alpha: 0.12),
                ),
                child: Icon(icon, color: VendorUi.whiteBackground, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              color: VendorUi.whiteBackground,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: VendorUi.softText,
              fontSize: 15,
              height: 1.55,
            ),
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 24),
            Wrap(spacing: 24, runSpacing: 14, children: stats),
          ],
        ],
      ),
    );
  }
}

class VendorPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const VendorPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: VendorUi.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: VendorUi.deepNavyBlue,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: VendorUi.textMuted, height: 1.5),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class VendorHeroStat extends StatelessWidget {
  final String label;
  final String value;

  const VendorHeroStat({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: VendorUi.softText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: VendorUi.whiteBackground,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _VendorHeroBadge extends StatelessWidget {
  final String label;

  const _VendorHeroBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: VendorUi.whiteBackground.withValues(alpha: 0.12),
          border: Border.all(
            color: VendorUi.whiteBackground.withValues(alpha: 0.14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: VendorUi.whiteBackground,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
