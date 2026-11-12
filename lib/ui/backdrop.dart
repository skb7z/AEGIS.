import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/theme.dart';

/// Static (cached) background layer: palette colour or the custom wallpaper with adjustable blur
/// (0 = sharp, 100 = maximum blur). The wallpaper is decoded at 540 px width and blurred inside its
/// own RepaintBoundary, so the animated orb above never forces it to repaint.
/// It listens to the settings itself, so theme / wallpaper / blur changes apply instantly.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: S.settings,
      builder: (context, _) {
        final s = S.settings;
        final pal = AegisPalette.byId(s.themeId);
        final path = s.wallpaper;
        final hasWp = path != null && File(path).existsSync();
        final sigma = s.blurSigma;
        final img = hasWp
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 540,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            : null;
        return RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: pal.bg),
              if (img != null) ...[
                if (sigma < 0.5)
                  img
                else
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: sigma,
                      sigmaY: sigma,
                      tileMode: TileMode.clamp,
                    ),
                    child: img,
                  ),
                ColoredBox(color: pal.bg.op(.5)),
              ] else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -.1),
                      radius: 1.1,
                      colors: [pal.accent.op(pal.dark ? .10 : .06), pal.bg],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
