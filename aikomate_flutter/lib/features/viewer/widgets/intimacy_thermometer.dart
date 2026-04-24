import 'package:flutter/material.dart';
import 'package:aikomate_flutter/reusable_widgets/glass.dart';

/// Horizontal intimacy meter (0–5) inside a liquid-glass card: red fill to the
/// current level and a solid red heart at that point.
class IntimacyThermometer extends StatelessWidget {
  const IntimacyThermometer({
    super.key,
    required this.value,
    this.max = 5,
  });

  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final m = max <= 0 ? 1 : max;
    final v = value.clamp(0, m);
    final t = v / m;
    const trackHeight = 9.0;
    const heartSize = 36.0;
    const cardRadius = 20.0;

    return GlassContainer(
      style: GlassPresets.panel,
      radius: cardRadius,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final trackTop = (h - trackHeight) / 2;
          final inset = heartSize / 2;
          final trackWidth = (w - heartSize).clamp(0.0, double.infinity);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: inset,
                width: trackWidth,
                top: trackTop,
                height: trackHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(trackHeight / 2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: Colors.black.withValues(alpha: 0.22),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: t,
                          alignment: Alignment.centerLeft,
                          heightFactor: 1,
                          child: const ColoredBox(color: Color.fromARGB(255, 144, 25, 17)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: inset + t * trackWidth - heartSize / 2,
                top: (h - heartSize) / 2,
                width: heartSize,
                height: heartSize,
                child: const Icon(
                  Icons.favorite,
                  size: heartSize,
                  color: Colors.red,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
