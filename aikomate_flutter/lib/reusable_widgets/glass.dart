import 'package:flutter/material.dart';

class GlassStyle {
  final double radius;
  final Gradient gradient;
  final List<BoxShadow> shadows;
  final Border? border;
  final Gradient? innerGradient;

  const GlassStyle({
    required this.radius,
    required this.gradient,
    required this.shadows,
    required this.border,
    this.innerGradient,
  });
}

class GlassPresets {
  static final chatBar = GlassStyle(
    radius: 30,
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color.fromARGB(255, 90, 90, 90).withOpacity(0.15),
        Colors.white.withOpacity(0.05),
      ],
    ),
    shadows: [
      BoxShadow(
        color: const Color.fromARGB(255, 46, 46, 46).withOpacity(1),
        blurRadius: 3,
        offset: const Offset(0, 0),
        blurStyle: BlurStyle.outer,
        spreadRadius: -2,
      ),
    ],
    border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.2),
    innerGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.center,
      colors: [
        const Color.fromARGB(255, 27, 27, 27).withOpacity(0.25),
        Colors.transparent,
        const Color.fromARGB(255, 27, 27, 27).withOpacity(0.25),
      ],
    ),
  );

  static final button = GlassStyle(
    radius: 0, // rounder
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white.withOpacity(0.25),
        const Color.fromARGB(255, 90, 90, 90).withOpacity(0.35),
      ],
    ),
    shadows: [
      BoxShadow(
        color: const Color.fromARGB(255, 46, 46, 46).withOpacity(.7),
        blurRadius: 3,
        offset: const Offset(0, 0),
        blurStyle: BlurStyle.outer,
        spreadRadius: -2,
      ),
    ],
    border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.2),
    innerGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        const Color.fromARGB(255, 27, 27, 27).withOpacity(0.35),
        const Color.fromARGB(255, 61, 61, 61).withOpacity(0.35),
        const Color.fromARGB(255, 27, 27, 27).withOpacity(0.35),
      ],
    ),
  );
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final GlassStyle style;
  final double? radius;

  const GlassContainer({
    super.key,
    required this.child,
    required this.style,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final r = radius ?? style.radius;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: style.gradient,
        boxShadow: style.shadows,
        border: style.border,
      ),
      child: Stack(
        children: [
          if (style.innerGradient != null)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(r),
                  gradient: style.innerGradient,
                ),
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final GlassStyle style;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool adaptiveIconSize;
  final double? iconSize;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.style,
    required this.size,
    required this.radius,
    required this.adaptiveIconSize,
    this.padding,
    this.iconSize
  });

  @override
Widget build(BuildContext context) {
  return GestureDetector(
    onTap: onPressed,
    child: SizedBox(
      width: size,
      height: size, 
      child: GlassContainer(
        style: style,
        padding: EdgeInsets.zero,
        radius: radius,
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final iconSize = adaptiveIconSize
                  ? constraints.maxWidth 
                  : 24.0;

              return Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: Colors.white.withOpacity(0.9),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
}
