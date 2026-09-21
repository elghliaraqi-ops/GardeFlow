import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// GardeFlow V11.6.24 — identité visuelle vert / rouge.
///
/// La logique fonctionnelle et les couleurs métier des gardes sont conservées.
/// Le chrome de l'application utilise une identité vert / blanc, avec accent rouge,
/// proche d'une application médicale native moderne.
class AppColors {
  AppColors._();

  // Palette complète choisie par l'utilisateur.
  static String _appearanceTheme = 'green';

  static void setAppearanceTheme(String value) {
    const allowed = <String>{'green', 'red', 'white', 'black'};
    _appearanceTheme = allowed.contains(value) ? value : 'green';
  }

  static String get appearanceTheme => _appearanceTheme;
  static bool get _isGreen => _appearanceTheme == 'green';
  static bool get _isRed => _appearanceTheme == 'red';
  static bool get _isWhite => _appearanceTheme == 'white';
  static bool get _isBlack => _appearanceTheme == 'black';
  static bool get isDarkMode => !_isWhite;

  // Surfaces / texte.
  static Color get paper {
    if (_isRed) return const Color(0xFF2D0F10);
    if (_isWhite) return const Color(0xFFF5F8F6);
    if (_isBlack) return const Color(0xFF080A09);
    return const Color(0xFF0E2B1E);
  }

  static Color get paperAlt {
    if (_isRed) return const Color(0xFF3A1516);
    if (_isWhite) return const Color(0xFFEDF3EF);
    if (_isBlack) return const Color(0xFF101311);
    return const Color(0xFF143725);
  }

  static Color get card {
    if (_isRed) return const Color(0xFF481B1D);
    if (_isWhite) return const Color(0xFFFFFFFF);
    if (_isBlack) return const Color(0xFF171A18);
    return const Color(0xFF19452F);
  }

  static Color get ink =>
      _isWhite ? const Color(0xFF173127) : const Color(0xFFF6FAF8);
  static Color get inkSoft {
    if (_isRed) return const Color(0xFFE2C2C2);
    if (_isWhite) return const Color(0xFF66776D);
    if (_isBlack) return const Color(0xFFBDC5C0);
    return const Color(0xFFC3D8CD);
  }

  static Color get inkFaint {
    if (_isRed) return const Color(0xFFB98E90);
    if (_isWhite) return const Color(0xFF97A59D);
    if (_isBlack) return const Color(0xFF838D87);
    return const Color(0xFF8EAD9C);
  }

  static Color get line {
    if (_isRed) return const Color(0xFF733236);
    if (_isWhite) return const Color(0xFFE0E9E3);
    if (_isBlack) return const Color(0xFF303632);
    return const Color(0xFF2B6247);
  }

  // Marque / accents adaptatifs.
  static Color get brand {
    if (_isRed) return const Color(0xFFE2534D);
    if (_isGreen) return const Color(0xFF2CBF75);
    return const Color(0xFF138A55);
  }

  static Color get brandDark {
    if (_isRed) return const Color(0xFF9E312E);
    if (_isGreen) return const Color(0xFF0B633D);
    return const Color(0xFF0B633D);
  }

  static Color get brandBright {
    if (_isRed) return const Color(0xFFF36C66);
    if (_isGreen) return const Color(0xFF49D590);
    return const Color(0xFF25A968);
  }

  static Color get brandSoft {
    if (_isRed) return const Color(0xFF68282A);
    if (_isWhite) return const Color(0xFFE8F6EE);
    if (_isBlack) return const Color(0xFF173126);
    return const Color(0xFF205B3E);
  }

  static const cyan = Color(0xFFD94A43);

  static Color get navy {
    if (_isRed) return const Color(0xFF3A1012);
    if (_isWhite) return const Color(0xFF173D2E);
    if (_isBlack) return const Color(0xFF080A09);
    return const Color(0xFF0A3524);
  }

  // Sémantique métier — Service (bleu).
  static const serviceJour = Color(0xFFDCEEFF);
  static const serviceJourText = Color(0xFF0A4F91);
  static const service24h = Color(0xFF4C91DF);
  static const service24hText = Color(0xFFFFFFFF);
  static const serviceNuit = Color(0xFF153A70);
  static const serviceNuitText = Color(0xFFF3F8FF);

  // Sémantique métier — Urgences (orange / rouge).
  static const urgJour = Color(0xFFFFE3C4);
  static const urgJourText = Color(0xFF9A4B00);
  static const urg24h = Color(0xFFF56B52);
  static const urg24hText = Color(0xFFFFFFFF);
  static const urgNuit = Color(0xFF922F36);
  static const urgNuitText = Color(0xFFFFFFFF);

  // Congé / états.
  static const conge = Color(0xFFD7F2E1);
  static const congeText = Color(0xFF22623B);
  static const catService = Color(0xFF287CD7);
  static const catUrgence = Color(0xFFF06449);
  static const danger = Color(0xFFD64545);
  static const success = Color(0xFF27A164);
  static const warning = Color(0xFFF3A72F);
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
  static const md = 18.0;
  static const lg = 22.0;
  static const xl = 28.0;
  static const pill = 999.0;

  static BorderRadius get smR => BorderRadius.circular(sm);
  static BorderRadius get mdR => BorderRadius.circular(md);
  static BorderRadius get lgR => BorderRadius.circular(lg);
  static BorderRadius get xlR => BorderRadius.circular(xl);
  static BorderRadius get pillR => BorderRadius.circular(pill);
}

class AppShadow {
  AppShadow._();
  static List<BoxShadow> get low => [
        BoxShadow(
          color: AppColors.brandDark.withOpacity(0.08),
          blurRadius: 14,
          offset: Offset(0, 5),
        ),
      ];
  static List<BoxShadow> get mid => [
        BoxShadow(
          color: AppColors.brandDark.withOpacity(0.12),
          blurRadius: 28,
          offset: Offset(0, 12),
        ),
      ];
  static List<BoxShadow> get high => [
        BoxShadow(
          color: AppColors.brandDark.withOpacity(0.22),
          blurRadius: 38,
          offset: Offset(0, 18),
        ),
      ];
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: brightness,
      primary: AppColors.brand,
      secondary: AppColors.cyan,
      surface: AppColors.card,
      error: AppColors.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.paper,
      canvasColor: AppColors.card,
      dividerColor: AppColors.line,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: 'Inter',
    );

    final displayBase = TextStyle(
      fontFamily: 'SpaceGrotesk',
      color: AppColors.ink,
      height: 1.08,
    );

    final textTheme = base.textTheme.copyWith(
      displayLarge: displayBase.copyWith(fontSize: 35, fontWeight: FontWeight.w700, letterSpacing: -0.8),
      displayMedium: displayBase.copyWith(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6),
      displaySmall: displayBase.copyWith(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.35),
      headlineSmall: displayBase.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
      titleLarge: displayBase.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontFamily: 'Inter', fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.ink),
      titleSmall: TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.ink),
      bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink, height: 1.45),
      bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.ink, height: 1.42),
      bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 11.8, fontWeight: FontWeight.w500, color: AppColors.inkSoft, height: 1.4),
      labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.ink),
      labelMedium: TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.inkSoft),
      labelSmall: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.inkSoft, letterSpacing: 0.2),
    );

    final roundedInput = OutlineInputBorder(
      borderRadius: AppRadius.mdR,
      borderSide: BorderSide(color: AppColors.line, width: 1.2),
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle:
            (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: AppColors.card,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgR,
          side: BorderSide(color: AppColors.line),
        ),
      ),
      dividerTheme: DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(color: AppColors.inkFaint, fontWeight: FontWeight.w500),
        labelStyle: TextStyle(color: AppColors.inkSoft, fontWeight: FontWeight.w700),
        floatingLabelStyle: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800),
        border: roundedInput,
        enabledBorder: roundedInput,
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdR,
          borderSide: BorderSide(color: AppColors.brand, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdR,
          borderSide: BorderSide(color: AppColors.danger),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandDark,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.brandDark.withOpacity(0.34),
          elevation: 0,
          minimumSize: Size(0, 52),
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
          textStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandDark,
          foregroundColor: Colors.white,
          minimumSize: Size(0, 50),
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
          textStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brand,
          side: BorderSide(color: AppColors.line, width: 1.2),
          minimumSize: Size(0, 50),
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
          textStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
          textStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13.5),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: AppColors.brandSoft,
          foregroundColor: AppColors.brand,
          side: BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.brandSoft,
        selectedColor: AppColors.brandDark,
        labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11.5, color: isDark ? AppColors.ink : AppColors.brandDark),
        secondaryLabelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11.5, color: Colors.white),
        side: BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.pillR),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
        insetPadding: EdgeInsets.all(14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.brand;
          return isDark ? const Color(0xFF46554D) : const Color(0xFFCBD6E2);
        }),
        trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.brand),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.brand,
        unselectedLabelColor: AppColors.inkFaint,
        indicatorColor: AppColors.brand,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.brandSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              color: states.contains(WidgetState.selected) ? AppColors.brand : AppColors.inkSoft,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected) ? AppColors.brand : AppColors.inkSoft,
            )),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: AppColors.card,
        iconColor: AppColors.brand,
        textColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.brandDark,
        headerForegroundColor: Colors.white,
        weekdayStyle: TextStyle(
          color: AppColors.inkSoft,
          fontWeight: FontWeight.w800,
        ),
        dayStyle: TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) return AppColors.inkFaint;
          return AppColors.ink;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.brandDark;
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStatePropertyAll(AppColors.brand),
        todayBorder: BorderSide(color: AppColors.brand),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return AppColors.ink;
        }),
        yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.brandDark;
          return Colors.transparent;
        }),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.card),
          surfaceTintColor:
              WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
    );
  }
}
