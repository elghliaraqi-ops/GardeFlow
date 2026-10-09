import 'package:flutter/material.dart';

/// Tokens shared by all new Practice daily pages, aligned with the original
/// Practice UI (dark navy + violet/blue/teal gradient, mint primary CTA).
abstract final class PracticeDailyVisualTheme {
  static const background = Color(0xFF071526);
  static const surface = Color(0xFF10243A);
  static const elevated = Color(0xFF17314E);
  static const mint = Color(0xFF5BE7B0);
  static const purple = Color(0xFF8B6CFF);
  static const blue = Color(0xFF3295FF);
  static const gold = Color(0xFFFFD166);
  static const text = Color(0xFFF5F8FF);
  static const muted = Color(0xFFB9CBE0);
  static const border = Color(0xFF244B68);

  static const pageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF071526),
      Color(0xFF102E48),
      Color(0xFF142C45),
      Color(0xFF071526),
    ],
    stops: [0, .32, .63, 1],
  );
  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5D47D8), Color(0xFF1D5AA4), Color(0xFF087B6D)],
    stops: [0, .55, 1],
  );

  static ThemeData from(BuildContext context) {
    final base = Theme.of(context);
    final primary = FilledButton.styleFrom(
      backgroundColor: mint,
      foregroundColor: background,
      disabledBackgroundColor: elevated,
      disabledForegroundColor: muted,
      textStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: .15,
      ),
      minimumSize: const Size(0, 47),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    final secondary = OutlinedButton.styleFrom(
      foregroundColor: text,
      disabledForegroundColor: muted,
      backgroundColor: elevated.withOpacity(.50),
      side: const BorderSide(color: Color(0xFF55839A), width: 1.2),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      minimumSize: const Size(0, 46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: mint,
        onPrimary: background,
        secondary: gold,
        onSecondary: background,
        surface: surface,
        onSurface: text,
        error: Color(0xFFFF8D97),
        onError: background,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        iconTheme: IconThemeData(color: text),
        actionsIconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: .1,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: primary),
      outlinedButtonTheme: OutlinedButtonThemeData(style: secondary),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: mint,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text,
          backgroundColor: Colors.transparent,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? background : text,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? mint : elevated,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(color: text, fontSize: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? mint : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? mint.withOpacity(.35)
              : elevated,
        ),
      ),
    );
  }
}
