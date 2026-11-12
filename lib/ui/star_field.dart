import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class _Star {
  _Star(this.x, this.y, this.size, this.speed, this.dir, this.phase, this.twinkle, this.tint);
  final double x;
  final double y;
  final double size;
  final double speed; // screen heights per second
  final double dir; // +1 falls down, -1 rises up
  final double phase;
  final double twinkle;
  final Color tint;
}

/// Space background: stars drifting down and up, twinkling. One CustomPainter, no widget rebuilds.
class StarField extends StatefulWidget {
  const StarField({super.key, this.count = 80});
  final int count;

  @override
  State<StarField> createState() => _StarFieldState();
}

class _StarFieldState extends State<StarField> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier<double>(0);
  late final List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    final r = math.Random(11);
    const tints = [Color(0xFFFFFFFF), Color(0xFFBFD9FF), Color(0xFFCFF6FF), Color(0xFFE3D4FF)];
    _stars = List.generate(widget.count, (i) {
      return _Star(
        r.nextDouble(),
        r.nextDouble(),
        0.6 + r.nextDouble() * 1.9,
        0.012 + r.nextDouble() * 0.05,
        r.nextBool() ? 1 : -1,
        r.nextDouble() * math.pi * 2,
        0.8 + r.nextDouble() * 2.2,
        tints[r.nextInt(tints.length)],
      );
    });
    _ticker = createTicker((d) => _t.value = d.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _StarPainter(_stars, _t),
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.stars, this.time) : super(repaint: time);
  final List<_Star> stars;
  final ValueNotifier<double> time;
  final Paint _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    for (final s in stars) {
      var y = (s.y + s.dir * s.speed * t) % 1.0;
      if (y < 0) y += 1.0;
      final x = (s.x + math.sin(t * 0.25 + s.phase) * 0.012) % 1.0;
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * s.twinkle + s.phase));
      final c = Offset(x * size.width, y * size.height);
      _p.color = s.tint.withAlpha((tw * 255).round().clamp(0, 255));
      canvas.drawCircle(c, s.size, _p);
      if (s.size > 1.9) {
        _p.color = s.tint.withAlpha((tw * 60).round().clamp(0, 255));
        canvas.drawCircle(c, s.size * 2.6, _p);
      }
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}
