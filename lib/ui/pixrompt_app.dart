import 'package:flutter/material.dart';

import '../app/pixrompt_controller.dart';
import '../app/pixrompt_sync_controller.dart';
import '../platform/pixrompt_file_actions.dart';
import 'gallery_shell.dart';
import 'pixrompt_design.dart';

class PixromptApp extends StatelessWidget {
  const PixromptApp({
    super.key,
    required this.controller,
    required this.syncController,
    PixromptFileActions? fileActions,
  }) : fileActions = fileActions ?? const _DefaultFileActions();

  final PixromptController controller;
  final PixromptSyncController syncController;
  final PixromptFileActions fileActions;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pixrompt',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: GalleryShell(
        controller: controller,
        syncController: syncController,
        fileActions: fileActions,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: PixromptPalette.seed,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFFA78BFA) : PixromptPalette.seed,
      secondary: dark ? PixromptPalette.accent : const Color(0xFF0891B2),
      surface:
          dark ? PixromptPalette.darkSurface : PixromptPalette.lightSurface,
      outline: dark
          ? PixromptPalette.darkOutlineStrong
          : PixromptPalette.lightOutline,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: dark
          ? PixromptPalette.darkBackground
          : PixromptPalette.lightBackground,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(
        color:
            dark ? PixromptPalette.darkOutline : PixromptPalette.lightOutline,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        modalBackgroundColor: dark
            ? PixromptPalette.darkBackgroundRaised
            : PixromptPalette.lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(PixromptRadius.xl),
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: dark
            ? PixromptPalette.darkBackgroundRaised
            : PixromptPalette.lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? PixromptPalette.darkSurfaceHigh.withOpacity(0.62)
            : const Color(0xFFF8F6FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PixromptRadius.md),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PixromptRadius.md),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PixromptRadius.md),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PixromptRadius.md),
        ),
        side: BorderSide(color: colorScheme.outline),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? PixromptPalette.darkBackground
            : PixromptPalette.lightBackground,
        foregroundColor: dark ? Colors.white : const Color(0xFF1E1B4B),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

class _DefaultFileActions extends PixromptFileActions {
  const _DefaultFileActions();
}
