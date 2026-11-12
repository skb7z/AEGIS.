import 'dart:ui' show PointMode;
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/assistant_controller.dart';

/// Holographic orb. One CustomPainter, driven by two AnimationControllers only (no widget rebuilds per
/// frame), no blur masks: gradients + arcs + a handful of points keep it smooth on low-end phones.
class OrbView extends StatefulWidget {
  const OrbView({super.key, required this.state, required this.palette});
  final AssistantState state;
  final AegisPalette palette;

  @override
  State<OrbView> createState() => _OrbViewState();
}

class _OrbViewState extends State<OrbView> with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  late final AnimationController _level = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: _target(widget.state),
  );

  double _target(AssistantState s) {
    switch (s) {
      case AssistantState.idle:
        return .25;
      case AssistantState.listening:
        return .8;
      case AssistantState.thinking:
        return .55;
      case AssistantState.speaking:
        return 1.0;
      case AssistantState.offline:
        return .15;
    }
  }

  Color _color(AssistantState s) {
    final p = widget.palette;
    switch (s) {
      case AssistantState.idle:
        return p.accent;
      case AssistantState.listening:
        return p.listen;
      case AssistantState.thinking:
        return p.think;
      case AssistantState.speaking:
        return p.accent;
      case AssistantState.offline:
        return const Color(0xFFFF5252);
    }
  }

  @override
  void didUpdateWidget(OrbView old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _level.animateTo(_target(widget.state), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final col = _color(widget.state);
    return RepaintBoundary(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: col),
        duration: const Duration(milliseconds: 500),
        builder: (context, value, _) => CustomPaint(
          size: Size.infinite,
          painter: _OrbPainter(
            loop: _loop,
            level: _level,
            color: value ?? col,
            dark: widget.palette.dark,
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.loop,
    required this.level,
    required this.color,
    required this.dark,
  }) : super(repaint: Listenable.merge([loop, level]));

  final Animation<double> loop;
  final Animation<double> level;
  final Color color;
  final bool dark;

  final Paint _fill = Paint();
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _dot = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    final t = loop.value;
    final l = level.value;
    final c = size.center(Offset.zero);
    final base = min(size.width, size.height) * 0.27;
    final pulse = 1 + 0.035 * sin(t * 2 * pi * 4) * (0.4 + l);
    final r = base * pulse;

    // Outer halo
    final haloR = r * 2.15;
    _fill.shader = RadialGradient(
      colors: [color.op(.30 * (.5 + l * .5)), color.op(.08), color.op(0)],
      stops: const [0, .55, 1],
    ).createShader(Rect.fromCircle(center: c, radius: haloR));
    canvas.drawCircle(c, haloR, _fill);

    // Expanding ripples (stronger while listening / speaking)
    _line.strokeWidth = 1.5;
    for (var k = 0; k < 3; k++) {
      final ph = (t * 3 + k / 3) % 1.0;
      final rr = r * (1.05 + ph * 0.9);
      _line.color = color.op((1 - ph) * 0.28 * l);
      canvas.drawCircle(c, rr, _line);
    }

    // Core sphere
    _fill.shader = RadialGradient(
      center: const Alignment(-.3, -.35),
      colors: [
        dark ? Colors.white.op(.95) : color.op(.55),
        color.op(.95),
        color.op(.28),
      ],
      stops: const [0, .45, 1],
    ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, _fill);

    // Rotating arc rings
    for (var i = 0; i < 3; i++) {
      final rr = r * (1.22 + 0.16 * i) + 2 * sin(t * 2 * pi * (1 + i));
      final dir = i.isEven ? 1 : -1;
      final start = t * 2 * pi * dir * (1 + i * .45) + i * 1.3;
      _line
        ..strokeWidth = 2.2 - i * .4
        ..color = color.op(.85 - i * .2);
      canvas.drawArc(Rect.fromCircle(center: c, radius: rr), start, 1.3 + .55 * i, false, _line);
      canvas.drawArc(Rect.fromCircle(center: c, radius: rr), start + pi, .7 + .3 * i, false, _line);
    }

    // Orbiting particles
    final pts = <Offset>[];
    for (var i = 0; i < 18; i++) {
      final a = t * 2 * pi * (.6 + (i % 3) * .25) + i * 0.349;
      final rr = r * (1.55 + .35 * sin(t * 2 * pi * 2 + i)) + l * 10;
      pts.add(c + Offset(cos(a) * rr, sin(a) * rr));
    }
    _dot.color = color.op(.75);
    canvas.drawPoints(PointMode.points, pts, _dot);
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.color != color || old.dark != dark;
}
