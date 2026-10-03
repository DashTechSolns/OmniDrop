import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;

  const GlassCard({
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.padding = const EdgeInsets.all(20),
    this.radius = glassRadiusMajor,
    this.blur = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _GlassSurface(
        child: child,
        margin: margin,
        padding: padding,
        radius: radius,
        blur: blur,
        tone: _GlassTone.standard,
      );
}

class ElevatedGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;

  const ElevatedGlass({
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.padding = const EdgeInsets.all(20),
    this.radius = glassRadiusModal,
    this.blur = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _GlassSurface(
        child: child,
        margin: margin,
        padding: padding,
        radius: radius,
        blur: blur,
        tone: _GlassTone.elevated,
      );
}

class SecurityGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double radius;

  const SecurityGlass({
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.padding = const EdgeInsets.all(20),
    this.radius = glassRadiusCard,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _GlassSurface(
        child: child,
        margin: margin,
        padding: padding,
        radius: radius,
        blur: false,
        tone: _GlassTone.security,
      );
}

enum _GlassTone { standard, elevated, security }

class _GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;
  final _GlassTone tone;

  const _GlassSurface({
    required this.child,
    required this.margin,
    required this.padding,
    required this.radius,
    required this.blur,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final fill = switch ((tone, light)) {
      (_GlassTone.standard, true) => Colors.white.withValues(alpha: 0.82),
      (_GlassTone.standard, false) => const Color(0xD9101C28),
      (_GlassTone.elevated, true) => Colors.white.withValues(alpha: 0.82),
      (_GlassTone.elevated, false) => const Color(0xE012202D),
      (_GlassTone.security, true) => const Color(0xFFE6F8F2),
      (_GlassTone.security, false) => const Color(0x8C003730),
    };
    final border = switch ((tone, light)) {
      (_GlassTone.standard, true) => const Color(0x400096BE),
      (_GlassTone.standard, false) => glassCyan.withValues(alpha: 0.18),
      (_GlassTone.elevated, true) => const Color(0x550096BE),
      (_GlassTone.elevated, false) => glassCyan.withValues(alpha: 0.25),
      (_GlassTone.security, true) => const Color(0x4D00B67A),
      (_GlassTone.security, false) => const Color(0x4D00E59A),
    };
    final radiusValue = BorderRadius.circular(radius);

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radiusValue,
        border: Border.all(color: border),
        gradient: tone == _GlassTone.security
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  glassCyan.withValues(alpha: light ? 0.035 : 0.07),
                  glassViolet.withValues(alpha: light ? 0.025 : 0.07),
                ],
              ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: light ? 0.08 : 0.22),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );

    if (blur) {
      content = ClipRRect(
        borderRadius: radiusValue,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: content,
        ),
      );
    }

    return Padding(padding: margin, child: content);
  }
}