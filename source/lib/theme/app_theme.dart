import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// GardeFlow — global visual system.
///
/// The business colors used by guards are intentionally preserved. The app
/// chrome follows a darker, calmer clinical hierarchy: neutral surfaces first,
/// one strong accent, subtle separators and consistent semantic colors.
class AppColors {
  AppColors._();

  static String _appearanceTheme = 'black';

  static void setAppearanceTheme(String value) {
    const allowed = <String>{'green', 'red', 'white', 'black'};
    _appearanceTheme = allowed.contains(value) ? value : 'black';
  }

  static String get appearanceTheme => _appearanceTheme;
  static bool get _isGreen => _appearanceTheme == 'green';
  static bool get _isRed => _appearanceTheme == 'red';
  static bool get _isWhite => _appearanceTheme == 'white';
  static bool get _isBlack => _appearanceTheme == 'black';
  static bool get isDarkMode => !_isWhite;

  // Surfaces / text.
  static Color get paper {
    if (_isRed) return const Color(0xFF241011);
    if (_isWhite) return const Color(0xFFF4F7F5);
    if (_isBlack) return const Color(0xFF071526);
    return const Color(0xFF071F18);
  }

  static Color get paperAlt {
    if (_isRed) return const Color(0xFF301516);
    if (_isWhite) return const Color(0xFFEDF2EF);
    if (_isBlack) return const Color(0xFF10243A);
    return const Color(0xFF0A291F);
  }

  static Color get card {
    if (_isRed) return const Color(0xFF3B1B1D);
    if (_isWhite) return const Color(0xFFFFFFFF);
    if (_isBlack) return const Color(0xFF10243A);
    return const Color(0xFF0E3025);
  }

  static Color get surfaceRaised {
    if (_isRed) return const Color(0xFF482326);
    if (_isWhite) return const Color(0xFFF9FBFA);
    if (_isBlack) return const Color(0xFF17314E);
    return const Color(0xFF14392C);
  }

  static Color get ink =>
      _isWhite ? const Color(0xFF142A21) : const Color(0xFFF4F8F6);

  static Color get inkSoft {
    if (_isRed) return const Color(0xFFD8BFC0);
    if (_isWhite) return const Color(0xFF617168);
    if (_isBlack) return const Color(0xFFB9CBE0);
    return const Color(0xFFB6CAC0);
  }

  static Color get inkFaint {
    if (_isRed) return const Color(0xFFA78486);
    if (_isWhite) return const Color(0xFF92A099);
    if (_isBlack) return const Color(0xFF87A4BB);
    return const Color(0xFF789388);
  }

  static Color get line {
    if (_isRed) return const Color(0xFF653236);
    if (_isWhite) return const Color(0xFFDCE5DF);
    if (_isBlack) return const Color(0xFF244B68);
    return const Color(0xFF1B4A38);
  }

  // Brand / adaptive accents.
  static Color get brand {
    if (_isRed) return const Color(0xFFE65B55);
    if (_isGreen) return const Color(0xFF22D985);
    if (_isBlack) return const Color(0xFF5BE7B0);
    return const Color(0xFF15965B);
  }

  static Color get brandDark {
    if (_isRed) return const Color(0xFFA83C38);
    if (_isGreen) return const Color(0xFF13784E);
    return const Color(0xFF0C6841);
  }

  static Color get brandBright {
    if (_isRed) return const Color(0xFFFF7A73);
    if (_isGreen) return const Color(0xFF4AE9A0);
    if (_isBlack) return const Color(0xFF5BE7B0);
    return const Color(0xFF2AB66F);
  }

  static Color get brandSoft {
    if (_isRed) return const Color(0xFF55262A);
    if (_isWhite) return const Color(0xFFE4F5EC);
    if (_isBlack) return const Color(0xFF143D37);
    return const Color(0xFF123F2F);
  }

  static Color get onBrand {
    if (_isRed) return Colors.white;
    return const Color(0xFF032117);
  }

  // Semantic UI accents. One color = one meaning everywhere.
  static const cyan = Color(0xFF35C3D8);
  static const info = Color(0xFF5AA8FF);
  static const violet = Color(0xFF9A7BFF);

  static Color get navy {
    if (_isRed) return const Color(0xFF241011);
    if (_isWhite) return const Color(0xFF173D2E);
    if (_isBlack) return const Color(0xFF071526);
    return const Color(0xFF071F18);
  }

  // Business semantics — Service (blue).
  static const serviceJour = Color(0xFFDCEEFF);
  static const serviceJourText = Color(0xFF0A4F91);
  static const service24h = Color(0xFF4C91DF);
  static const service24hText = Color(0xFFFFFFFF);
  static const serviceNuit = Color(0xFF153A70);
  static const serviceNuitText = Color(0xFFF3F8FF);

  // Business semantics — Urgences (orange / red).
  static const urgJour = Color(0xFFFFE3C4);
  static const urgJourText = Color(0xFF9A4B00);
  static const urg24h = Color(0xFFF56B52);
  static const urg24hText = Color(0xFFFFFFFF);
  static const urgNuit = Color(0xFF922F36);
  static const urgNuitText = Color(0xFFFFFFFF);

  // Leave / states.
  static const conge = Color(0xFFD7F2E1);
  static const congeText = Color(0xFF22623B);
  static const catService = Color(0xFF287CD7);
  static const catUrgence = Color(0xFFF06449);
  static const danger = Color(0xFFE25A56);
  static const success = Color(0xFF2BC878);
  static const warning = Color(0xFFF2AD45);
}

class AppSpace {
  AppSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const xxxl = 40.0;
}

class AppRadius {
  AppRadius._();
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const pill = 999.0;

  static BorderRadius get smR => BorderRadius.circular(sm);
  static BorderRadius get mdR => BorderRadius.circular(md);
  static BorderRadius get lgR => BorderRadius.circular(lg);
  static BorderRadius get xlR => BorderRadius.circular(xl);
  static BorderRadius get pillR => BorderRadius.circular(pill);
}

class AppShadow {
  AppShadow._();

  static Color get _shadowColor => AppColors.isDarkMode
      ? Colors.black.withOpacity(0.20)
      : const Color(0xFF173127).withOpacity(0.07);

  static List<BoxShadow> get low => [
    BoxShadow(color: _shadowColor, blurRadius: 16, offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> get mid => [
    BoxShadow(color: _shadowColor, blurRadius: 28, offset: const Offset(0, 12)),
  ];

  static List<BoxShadow> get high => [
    BoxShadow(color: _shadowColor, blurRadius: 40, offset: const Offset(0, 18)),
  ];
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.brand,
          brightness: brightness,
          primary: AppColors.brand,
          secondary: AppColors.cyan,
          surface: AppColors.card,
          error: AppColors.danger,
        ).copyWith(
          surfaceContainerLowest: AppColors.paper,
          surfaceContainerLow: AppColors.paperAlt,
          surfaceContainer: AppColors.card,
          surfaceContainerHigh: AppColors.surfaceRaised,
          outline: AppColors.line,
          outlineVariant: AppColors.line.withOpacity(0.70),
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.inkSoft,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.paper,
      canvasColor: AppColors.paper,
      dividerColor: AppColors.line,
      splashFactory: InkRipple.splashFactory,
      fontFamily: 'Inter',
    );

    final displayBase = TextStyle(
      fontFamily: 'SpaceGrotesk',
      color: AppColors.ink,
      height: 1.08,
    );

    final textTheme = base.textTheme.copyWith(
      displayLarge: displayBase.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
      ),
      displayMedium: displayBase.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      displaySmall: displayBase.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      headlineSmall: displayBase.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: displayBase.copyWith(
        fontSize: 18.5,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 15.5,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      titleSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.ink,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: AppColors.ink,
        height: 1.42,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 11.8,
        fontWeight: FontWeight.w500,
        color: AppColors.inkSoft,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      labelMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.inkSoft,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: AppColors.inkSoft,
        letterSpacing: 0.2,
      ),
    );

    final enabledInput = OutlineInputBorder(
      borderRadius: AppRadius.mdR,
      borderSide: BorderSide(
        color: AppColors.line.withOpacity(0.78),
        width: 0.9,
      ),
    );

    return base.copyWith(
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: AppColors.ink),
        actionsIconTheme: IconThemeData(color: AppColors.ink),
        systemOverlayStyle:
            (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: AppColors.paperAlt,
                  systemNavigationBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.line.withOpacity(0.72),
        thickness: 0.8,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paperAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: TextStyle(
          color: AppColors.inkFaint,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: TextStyle(
          color: AppColors.inkSoft,
          fontWeight: FontWeight.w700,
        ),
        helperStyle: TextStyle(
          color: AppColors.inkFaint,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: AppColors.brandBright,
          fontWeight: FontWeight.w800,
        ),
        border: enabledInput,
        enabledBorder: enabledInput,
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdR,
          borderSide: BorderSide(color: AppColors.brand, width: 1.35),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdR,
          borderSide: const BorderSide(color: AppColors.danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdR,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.35),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.onBrand,
          disabledBackgroundColor: AppColors.brand.withOpacity(0.30),
          disabledForegroundColor: AppColors.inkFaint,
          elevation: 0,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.onBrand,
          disabledBackgroundColor: AppColors.brand.withOpacity(0.30),
          disabledForegroundColor: AppColors.inkFaint,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w900,
            fontSize: 13.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: BorderSide(color: AppColors.line.withOpacity(0.86), width: 0.9),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brandBright,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: AppColors.paperAlt,
          foregroundColor: AppColors.inkSoft,
          hoverColor: AppColors.brandSoft,
          highlightColor: AppColors.brandSoft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.paperAlt,
        selectedColor: AppColors.brandSoft,
        disabledColor: AppColors.paperAlt.withOpacity(0.55),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
          color: AppColors.inkSoft,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w900,
          fontSize: 11.5,
          color: AppColors.brandBright,
        ),
        checkmarkColor: AppColors.brandBright,
        side: BorderSide(color: AppColors.line.withOpacity(0.58), width: 0.7),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.pillR),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlR),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: AppColors.line,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        contentTextStyle: TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        actionTextColor: AppColors.brandBright,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: AppColors.paperAlt,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColors.brandSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: AppColors.brandBright, size: 24);
          }
          return IconThemeData(color: AppColors.inkSoft, size: 23);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Inter',
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            color: selected ? AppColors.brandBright : AppColors.inkSoft,
          );
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.paperAlt,
        selectedItemColor: AppColors.brandBright,
        unselectedItemColor: AppColors.inkSoft,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 10.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 10.5,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected))
            return AppColors.brand.withOpacity(0.55);
          return AppColors.line;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected))
            return AppColors.brandBright;
          return AppColors.inkSoft;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.brand;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(AppColors.onBrand),
        side: BorderSide(color: AppColors.line, width: 1.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected))
            return AppColors.brandBright;
          return AppColors.inkSoft;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.brand,
        linearTrackColor: AppColors.paperAlt,
        circularTrackColor: AppColors.paperAlt,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.inkSoft,
        textColor: AppColors.ink,
        subtitleTextStyle: textTheme.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
        textStyle: textTheme.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: AppRadius.smR,
        ),
        textStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
