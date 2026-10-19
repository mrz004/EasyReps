import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'theme.dart';

/// iOS-style "glass" look: a soft gradient with coloured glows behind every
/// page, and translucent frosted panels on top.

/// Fill and edge colours for glass surfaces in the current brightness.
class GlassColors {
  const GlassColors._(this.fill, this.border, this.sheen);

  factory GlassColors.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? GlassColors._(
          Colors.white.withValues(alpha: 0.07),
          Colors.white.withValues(alpha: 0.14),
          Colors.white.withValues(alpha: 0.10),
        )
      : GlassColors._(
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.80),
          Colors.white.withValues(alpha: 0.65),
        );

  final Color fill;
  final Color border;

  /// Top-left highlight of the sheen gradient.
  final Color sheen;
}

/// Gradient backdrop with a few blurred colour glows. Static and cheap: the
/// glows are radial gradients, not blur filters.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glowAlpha = dark ? 0.30 : 0.35;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF23211C), CHARCOAL, Color(0xFF25303A)]
                  : const [Color(0xFFF6F3EA), Color(0xFFEDE9DD), FOG],
            ),
          ),
        ),
        _Glow(
          color: SLATE_BLUE.withValues(alpha: glowAlpha * 0.7),
          size: 420,
          top: -140,
          right: -120,
        ),
        _Glow(
          color: ALOE.withValues(alpha: glowAlpha),
          size: 380,
          top: 260,
          left: -170,
        ),
        _Glow(
          color: SLATE_BLUE.withValues(alpha: glowAlpha * 0.5),
          size: 420,
          bottom: -170,
          right: -110,
        ),
        child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.color,
    required this.size,
    this.top,
    this.left,
    this.right,
    this.bottom,
  });
  final Color color;
  final double size;
  final double? top, left, right, bottom;

  @override
  Widget build(BuildContext context) => Positioned(
    top: top,
    left: left,
    right: right,
    bottom: bottom,
    child: IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    ),
  );
}

/// A frosted-glass panel: blurs what is behind it. Use sparingly (blur is
/// costly on Android); plain cards get a translucent look from the theme.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = CARD_RADIUS,
    this.blur = 18,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final glass = GlassColors.of(context);
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: shape,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: shape,
                border: Border.all(color: glass.border),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [glass.sheen, glass.fill],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps every page in [GlassBackground] inside the platform's default page
/// transition, so pages stay opaque while they animate.
class GlassPageTransitionsBuilder extends PageTransitionsBuilder {
  const GlassPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final platform = Theme.of(context).platform;
    final base =
        const PageTransitionsTheme().builders[platform] ??
        const ZoomPageTransitionsBuilder();
    return base.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      GlassBackground(child: child),
    );
  }
}
