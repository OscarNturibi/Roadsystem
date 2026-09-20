import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/detection_painter.dart';

// ══════════════════════════════════════════════════════════════
//  RSCard — premium glass-border card
// ══════════════════════════════════════════════════════════════
class RSCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? accentColor; // draws a subtle top-edge highlight

  const RSCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.border, width: 0.5),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 20, offset: const Offset(0, 4)),
                  if (accentColor != null)
                    BoxShadow(
                      color: accentColor!.withValues(alpha: 0.10),
                      blurRadius: 24, offset: const Offset(0, 2)),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16, offset: const Offset(0, 2)),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(children: [
            // Inner top highlight line
            if (isDark)
              Positioned(
                top: 0, left: 20, right: 20, height: 0.5,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: 0.12),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            Padding(
              padding: padding ?? const EdgeInsets.all(18),
              child: child,
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  GlowCard — card with colored ambient glow
// ══════════════════════════════════════════════════════════════
class GlowCard extends StatelessWidget {
  final Widget child;
  final Color glowColor;
  final EdgeInsetsGeometry? padding;

  const GlowCard({
    super.key,
    required this.child,
    required this.glowColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return RSCard(child: child, padding: padding, accentColor: glowColor);
  }
}

// ══════════════════════════════════════════════════════════════
//  StatCard — metric tile with icon blob, value, label, chip
// ══════════════════════════════════════════════════════════════
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color  valueColor;
  final Widget? icon;
  final String? chipLabel;
  final Color?  chipColor;
  final Color?  accentBorder;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
    this.icon,
    this.chipLabel,
    this.chipColor,
    this.accentBorder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentBorder ?? context.border,
          width: accentBorder != null ? 1 : 0.5,
        ),
        boxShadow: isDark
            ? [
                BoxShadow(color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 16, offset: const Offset(0, 3)),
                if (accentBorder != null)
                  BoxShadow(color: accentBorder!.withValues(alpha: 0.12),
                      blurRadius: 20, offset: const Offset(0, 2)),
              ]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12, offset: const Offset(0, 2)),
              ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[icon!, const SizedBox(height: 10)],
        Text(value, style: TextStyle(
          fontSize: 32, fontWeight: FontWeight.w800,
          color: valueColor, letterSpacing: -1.8, height: 1,
        )),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(
          fontSize: 12, color: context.muted, fontWeight: FontWeight.w500,
        )),
        if (chipLabel != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: (chipColor ?? valueColor).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                  color: (chipColor ?? valueColor).withValues(alpha: 0.22),
                  width: 0.5),
            ),
            child: Text(chipLabel!, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: chipColor ?? valueColor,
              fontFamily: 'monospace', letterSpacing: 0.3,
            )),
          ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  SectionLabel
// ══════════════════════════════════════════════════════════════
class SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 22, left: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(width: 3, height: 14,
              decoration: BoxDecoration(
                color: AppColors.lime,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(text.toUpperCase(), style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: context.muted, letterSpacing: 1.0,
            )),
          ]),
          if (trailing != null)
            Text(trailing!, style: TextStyle(
              fontSize: 12, color: context.muted, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  IosRow — settings / input list row
// ══════════════════════════════════════════════════════════════
class IosRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool isLast;
  const IosRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            leading,
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500, color: context.text)),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(
                    fontSize: 12, color: context.muted, fontFamily: 'monospace')),
              ],
            )),
            if (trailing != null) trailing!,
            if (showChevron && trailing == null)
              Icon(Icons.chevron_right_rounded, color: context.muted, size: 18),
          ]),
        ),
        if (!isLast)
          Divider(height: 0, indent: 62, thickness: 0.5, color: context.sep),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  RowIcon — coloured icon blob for list rows
// ══════════════════════════════════════════════════════════════
class RowIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const RowIcon({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Icon(icon, color: color, size: 17),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  GpsStrip — location display card
// ══════════════════════════════════════════════════════════════
class GpsStrip extends StatelessWidget {
  final String street;
  final String? area;
  final String coords;
  const GpsStrip({
    super.key,
    required this.street,
    required this.coords,
    this.area,
  });

  @override
  Widget build(BuildContext context) {
    return RSCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      accentColor: AppColors.amber,
      child: Row(children: [
        // Amber location blob
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.amber.withValues(alpha: 0.22), width: 1),
          ),
          child: const Icon(Icons.location_on_rounded,
              color: AppColors.amber, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(street, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: context.text)),
            if (area != null && area!.isNotEmpty)
              Text(area!, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.text2,
                      fontWeight: FontWeight.w500)),
            Text(coords, style: TextStyle(
                fontSize: 11, color: context.muted, fontFamily: 'monospace')),
          ],
        )),
        const SizedBox(width: 8),
        // Live GPS badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.lime.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: AppColors.lime.withValues(alpha: 0.28), width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _Blinker(color: AppColors.lime),
            const SizedBox(width: 5),
            const Text('LIVE', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: AppColors.lime, fontFamily: 'monospace', letterSpacing: 0.5)),
          ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  SeverityBadge
// ══════════════════════════════════════════════════════════════
class SeverityBadge extends StatelessWidget {
  final String severity;
  const SeverityBadge(this.severity, {super.key});

  Color get _color => severity == 'High'
      ? AppColors.red
      : severity == 'Medium'
          ? AppColors.orange
          : AppColors.lime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.28), width: 0.5),
      ),
      child: Text(severity.toUpperCase(), style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700, color: _color,
        fontFamily: 'monospace', letterSpacing: 0.5,
      )),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  _Blinker — animated green dot
// ══════════════════════════════════════════════════════════════
class _Blinker extends StatefulWidget {
  final Color color;
  const _Blinker({required this.color});
  @override State<_Blinker> createState() => _BlinkerState();
}
class _BlinkerState extends State<_Blinker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Container(
      width: 6, height: 6,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.4 + 0.6 * _c.value),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(
          color: widget.color.withValues(alpha: 0.5 * _c.value),
          blurRadius: 6,
        )],
      ),
    ),
  );
}
