import 'package:flutter/material.dart';

class PixromptPalette {
  const PixromptPalette._();

  static const seed = Color(0xFF7C3AED);
  static const accent = Color(0xFF22D3EE);
  static const danger = Color(0xFFFF6B6B);

  static const darkBackground = Color(0xFF0B0D13);
  static const darkBackgroundRaised = Color(0xFF10131B);
  static const darkSurface = Color(0xFF151A24);
  static const darkSurfaceHigh = Color(0xFF1E2532);
  static const darkSurfaceHighest = Color(0xFF283244);
  static const darkOutline = Color(0x29FFFFFF);
  static const darkOutlineStrong = Color(0x3DFFFFFF);

  static const lightBackground = Color(0xFFF7F4FF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightOutline = Color(0xFFE3DDF4);
}

class PixromptRadius {
  const PixromptRadius._();

  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
}

class PixromptSpace {
  const PixromptSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

BoxDecoration pixromptSurfaceDecoration({
  Color? color,
  double radius = PixromptRadius.lg,
  Color borderColor = PixromptPalette.darkOutline,
  bool elevated = true,
}) {
  return BoxDecoration(
    color: color ?? PixromptPalette.darkSurface.withOpacity(0.86),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor),
    boxShadow: elevated
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.34),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ]
        : null,
  );
}

ButtonStyle pixromptIconButtonStyle({
  bool destructive = false,
  Color? backgroundColor,
  double radius = PixromptRadius.md,
}) {
  final foreground =
      destructive ? const Color(0xFFFFB4B4) : const Color(0xFFF7F8FC);
  final background = backgroundColor ??
      (destructive
          ? PixromptPalette.danger.withOpacity(0.16)
          : Colors.white.withOpacity(0.10));
  return IconButton.styleFrom(
    backgroundColor: background,
    foregroundColor: foreground,
    fixedSize: const Size.square(48),
    minimumSize: const Size.square(48),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
  );
}

EdgeInsets pixromptSheetPadding(BuildContext context) {
  return EdgeInsets.fromLTRB(
    PixromptSpace.xl,
    PixromptSpace.xs,
    PixromptSpace.xl,
    MediaQuery.viewInsetsOf(context).bottom + PixromptSpace.xl,
  );
}

class PixromptSheetFrame extends StatelessWidget {
  const PixromptSheetFrame({
    super.key,
    required this.child,
    this.scrollable = true,
  });

  final Widget child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: pixromptSheetPadding(context),
      child: child,
    );
    if (!scrollable) return content;
    return SingleChildScrollView(child: content);
  }
}
