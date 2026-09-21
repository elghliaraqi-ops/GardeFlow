import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// All application surfaces and foregrounds are derived from one ColorScheme.
/// AppColors is a compatibility facade for the pre-existing screens only.
class AppColors {
  AppColors._();
  static String _appearanceTheme = 'green';
  static void setAppearanceTheme(String value) {
    _appearanceTheme = const {'green', 'red', 'white', 'black'}.contains(value)
        ? value : 'green';
  }
  static String get appearanceTheme => _appearanceTheme;
  static bool get isDarkMode => _appearanceTheme != 'white';
  static ColorScheme get scheme => AppTheme.schemeFor(_appearanceTheme);
  static Color get paper => scheme.surface;
  static Color get paperAlt => scheme.surfaceContainerLow;
  static Color get card => scheme.surfaceContainer;
  static Color get ink => scheme.onSurface;
  static Color get inkSoft => scheme.onSurfaceVariant;
  static Color get inkFaint => scheme.onSurfaceVariant;
  static Color get line => scheme.outlineVariant;
  static Color get brand => scheme.primary;
  static Color get brandBright => scheme.primary;
  static Color get brandSoft => scheme.primaryContainer;
  static Color get brandDark => _appearanceTheme == 'red'
      ? const Color(0xFF922F3C) : const Color(0xFF17624B);
  static Color get navy => const Color(0xFF142622);
  static const cyan = Color(0xFFB8424F);
  // Catalogue colors are presentation tokens; shift IDs and schedules stay intact.
  static const serviceJour = Color(0xFFE2EDF6);
  static const serviceJourText = Color(0xFF254C6A);
  static const service24h = Color(0xFF356588);
  static const service24hText = Colors.white;
  static const serviceNuit = Color(0xFF263D58);
  static const serviceNuitText = Color(0xFFF4F7FC);
  static const urgJour = Color(0xFFFFEBDC);
  static const urgJourText = Color(0xFF774621);
  static const urg24h = Color(0xFFA54831);
  static const urg24hText = Colors.white;
  static const urgNuit = Color(0xFF703941);
  static const urgNuitText = Colors.white;
  static const conge = Color(0xFFDFEFE4);
  static const congeText = Color(0xFF27543C);
  static const catService = Color(0xFF507FA3);
  static const catUrgence = Color(0xFFB85A40);
  static Color get danger => scheme.error;
  static Color get success => isDarkMode ? const Color(0xFF9AD8BD) : const Color(0xFF256C4F);
  static Color get warning => isDarkMode ? const Color(0xFFEFC686) : const Color(0xFF7B501C);
}

typedef ShiftTone = ({Color background, Color foreground});

/// Shift meaning is expressed by labels/icons as well as these shared colors.
/// Keeping the palette in the theme also makes theme transitions consistent.
class AppShiftTheme extends ThemeExtension<AppShiftTheme> {
  final Map<String, ShiftTone> tones;
  const AppShiftTheme(this.tones);

  factory AppShiftTheme.forBrightness(Brightness brightness) => AppShiftTheme(
    brightness == Brightness.dark ? const {
      'service-jour': (background: Color(0xFF273D36), foreground: Color(0xFFC7EBD9)),
      'service-nuit': (background: Color(0xFF223041), foreground: Color(0xFFD0E7FF)),
      'service-24h': (background: Color(0xFF35313F), foreground: Color(0xFFE5DCF2)),
      'urg-jour': (background: Color(0xFF473728), foreground: Color(0xFFF9DFC3)),
      'urg-nuit': (background: Color(0xFF3F2C39), foreground: Color(0xFFF1CCE0)),
      'urg-24h': (background: Color(0xFF44302B), foreground: Color(0xFFFFD6C5)),
      'conge': (background: Color(0xFF263E32), foreground: Color(0xFFC5E9D0)),
    } : const {
      'service-jour': (background: AppColors.serviceJour, foreground: AppColors.serviceJourText),
      'service-nuit': (background: AppColors.serviceNuit, foreground: AppColors.serviceNuitText),
      'service-24h': (background: AppColors.service24h, foreground: AppColors.service24hText),
      'urg-jour': (background: AppColors.urgJour, foreground: AppColors.urgJourText),
      'urg-nuit': (background: AppColors.urgNuit, foreground: AppColors.urgNuitText),
      'urg-24h': (background: AppColors.urg24h, foreground: AppColors.urg24hText),
      'conge': (background: AppColors.conge, foreground: AppColors.congeText),
    },
  );

  @override
  AppShiftTheme copyWith({Map<String, ShiftTone>? tones}) => AppShiftTheme(tones ?? this.tones);

  @override
  AppShiftTheme lerp(covariant AppShiftTheme? other, double t) {
    if (other == null) return this;
    return AppShiftTheme({for (final key in tones.keys) key: (
      background: Color.lerp(tones[key]!.background, other.tones[key]!.background, t)!,
      foreground: Color.lerp(tones[key]!.foreground, other.tones[key]!.foreground, t)!,
    )});
  }
}

class AppSpace {
  AppSpace._();
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0;
  static const xl = 24.0, xxl = 32.0, xxxl = 48.0;
}
class AppRadius {
  AppRadius._();
  static const sm = 10.0, md = 16.0, lg = 20.0, xl = 24.0, pill = 999.0;
  static BorderRadius get smR => BorderRadius.circular(sm);
  static BorderRadius get mdR => BorderRadius.circular(md);
  static BorderRadius get lgR => BorderRadius.circular(lg);
  static BorderRadius get xlR => BorderRadius.circular(xl);
  static BorderRadius get pillR => BorderRadius.circular(pill);
}
class AppMotion {
  AppMotion._();
  static const short = Duration(milliseconds: 180);
  static Duration duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : short;
}
class AppShadow {
  AppShadow._();
  static List<BoxShadow> get low => const [];
  static List<BoxShadow> get mid => const [
    BoxShadow(color: Color(0x0A000000), blurRadius: 18, offset: Offset(0, 5)),
  ];
  static List<BoxShadow> get high => mid;
}
class AppTypography {
  AppTypography._();
  static TextTheme build(ColorScheme c) => TextTheme(
    displayLarge: TextStyle(fontSize: 40, height: 1.12, fontWeight: FontWeight.w600, letterSpacing: -1.2, color: c.onSurface),
    displayMedium: TextStyle(fontSize: 32, height: 1.16, fontWeight: FontWeight.w600, letterSpacing: -0.8, color: c.onSurface),
    displaySmall: TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: c.onSurface),
    headlineSmall: TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: c.onSurface),
    titleLarge: TextStyle(fontSize: 21, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: c.onSurface),
    titleMedium: TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w600, color: c.onSurface),
    titleSmall: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600, color: c.onSurface),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: c.onSurface),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: c.onSurface),
    bodySmall: TextStyle(fontSize: 12, height: 1.4, color: c.onSurfaceVariant),
    labelLarge: TextStyle(fontSize: 14, height: 1.25, fontWeight: FontWeight.w600, color: c.onSurface),
    labelMedium: TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w600, color: c.onSurfaceVariant),
    labelSmall: TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w600, color: c.onSurfaceVariant),
  ).apply(fontFamily: 'Inter');
}
class AppTheme {
  AppTheme._();
  static final _schemes = <String, ColorScheme>{};
  static ColorScheme schemeFor(String name) => _schemes.putIfAbsent(name, () => _createScheme(name));
  static ColorScheme _createScheme(String name) {
    final light = name == 'white';
    final red = name == 'red';
    final black = name == 'black';
    return ColorScheme.fromSeed(
      seedColor: red ? const Color(0xFF922F3C) : const Color(0xFF17624B),
      brightness: light ? Brightness.light : Brightness.dark,
    ).copyWith(
      primary: light ? const Color(0xFF17624B) : red ? const Color(0xFFFFAFB6) : const Color(0xFF9AD8BD),
      onPrimary: light ? Colors.white : red ? const Color(0xFF451722) : const Color(0xFF103B2C),
      primaryContainer: light ? const Color(0xFFE3EFE8) : red ? const Color(0xFF41272F) : const Color(0xFF243D33),
      onPrimaryContainer: light ? const Color(0xFF174D39) : red ? const Color(0xFFFFD8DC) : const Color(0xFFC7EBD9),
      surface: light ? const Color(0xFFF7F8F5) : black ? const Color(0xFF0D0F10) : red ? const Color(0xFF1B1719) : const Color(0xFF14211D),
      surfaceContainerLow: light ? const Color(0xFFF0F2ED) : black ? const Color(0xFF16191B) : red ? const Color(0xFF242022) : const Color(0xFF1B2A24),
      surfaceContainer: light ? Colors.white : black ? const Color(0xFF1D2022) : red ? const Color(0xFF2C2528) : const Color(0xFF22322B),
      surfaceContainerHigh: light ? const Color(0xFFE8ECE5) : black ? const Color(0xFF292C2E) : red ? const Color(0xFF392D33) : const Color(0xFF2D4036),
      onSurface: light ? const Color(0xFF1D2D25) : const Color(0xFFF1F4F0),
      onSurfaceVariant: light ? const Color(0xFF58655D) : const Color(0xFFBFCAC2),
      outline: light ? const Color(0xFF79867D) : const Color(0xFF7C8C81),
      outlineVariant: light ? const Color(0xFFDAE0D8) : black ? const Color(0xFF3A4042) : red ? const Color(0xFF51434B) : const Color(0xFF3E5146),
      error: light ? const Color(0xFFAC2637) : const Color(0xFFFFAFB6),
      onError: light ? Colors.white : const Color(0xFF551823),
      errorContainer: light ? const Color(0xFFFFE3E6) : const Color(0xFF4C2832),
      onErrorContainer: light ? const Color(0xFF7E2030) : const Color(0xFFFFD8DC),
    );
  }
  static ThemeData light() => forAppearance('white');
  static ThemeData dark() => forAppearance(AppColors.appearanceTheme == 'white' ? 'black' : AppColors.appearanceTheme);
  static ThemeData forAppearance(String name) {
    final c = schemeFor(name);
    final t = AppTypography.build(c);
    final shape = RoundedRectangleBorder(borderRadius: AppRadius.mdR);
    final input = OutlineInputBorder(borderRadius: AppRadius.mdR, borderSide: BorderSide.none);
    final button = FilledButton.styleFrom(
      minimumSize: const Size(48, 52), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: shape, backgroundColor: c.primary, foregroundColor: c.onPrimary,
      disabledBackgroundColor: c.surfaceContainerHigh, disabledForegroundColor: c.onSurfaceVariant,
      textStyle: t.labelLarge, elevation: 0,
    );
    return ThemeData(
      useMaterial3: true, colorScheme: c, textTheme: t, fontFamily: 'Inter',
      extensions: [AppShiftTheme.forBrightness(c.brightness)],
      scaffoldBackgroundColor: c.surface, canvasColor: c.surfaceContainer,
      dividerColor: c.outlineVariant, visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface, foregroundColor: c.onSurface, elevation: 0,
        surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0,
        centerTitle: false, titleTextStyle: t.titleLarge,
        systemOverlayStyle: (c.brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: c.surface),
      ),
      cardTheme: CardThemeData(color: c.surfaceContainer, elevation: 0, margin: EdgeInsets.zero, shape: shape, surfaceTintColor: Colors.transparent),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: c.surfaceContainerHigh, border: input, enabledBorder: input,
        focusedBorder: input.copyWith(borderSide: BorderSide(color: c.primary, width: 1.5)),
        errorBorder: input.copyWith(borderSide: BorderSide(color: c.error)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: t.bodyMedium?.copyWith(color: c.onSurfaceVariant), labelStyle: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
        floatingLabelStyle: t.bodyMedium?.copyWith(color: c.primary), errorMaxLines: 3,
      ),
      filledButtonTheme: FilledButtonThemeData(style: button),
      elevatedButtonTheme: ElevatedButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: shape, foregroundColor: c.primary, side: BorderSide(color: c.outline), textStyle: t.labelLarge,
      )),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        minimumSize: const Size(48, 48), foregroundColor: c.primary, textStyle: t.labelLarge,
      )),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(
        minimumSize: const Size(48, 48), foregroundColor: c.onSurface, disabledForegroundColor: c.onSurfaceVariant.withValues(alpha: .5),
      )),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceContainer, selectedColor: c.primaryContainer,
        labelStyle: t.labelLarge, side: BorderSide.none, shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        textStyle: WidgetStatePropertyAll(t.labelLarge),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onPrimaryContainer : c.onSurfaceVariant),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primaryContainer : c.surfaceContainer),
        side: const WidgetStatePropertyAll(BorderSide.none),
      )),
      dialogTheme: DialogThemeData(backgroundColor: c.surfaceContainer, surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlR), titleTextStyle: t.titleLarge, contentTextStyle: t.bodyLarge),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surfaceContainer, surfaceTintColor: Colors.transparent,
        showDragHandle: true, dragHandleColor: c.outline, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)))),
      snackBarTheme: SnackBarThemeData(backgroundColor: c.inverseSurface, contentTextStyle: t.bodyMedium?.copyWith(color: c.onInverseSurface),
        behavior: SnackBarBehavior.floating, shape: shape),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface, surfaceTintColor: Colors.transparent, elevation: 0, height: 76,
        indicatorColor: c.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(t.labelMedium?.copyWith(color: c.onSurface)),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.onPrimaryContainer : c.onSurfaceVariant)),
      ),
      listTileTheme: ListTileThemeData(iconColor: c.primary, textColor: c.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), minVerticalPadding: 12,
        titleTextStyle: t.titleMedium, subtitleTextStyle: t.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
      tabBarTheme: TabBarThemeData(labelColor: c.primary, unselectedLabelColor: c.onSurfaceVariant,
        labelStyle: t.labelLarge, unselectedLabelStyle: t.labelLarge, indicatorColor: c.primary, dividerColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(color: c.surfaceContainer, shape: shape, textStyle: t.bodyMedium),
      dropdownMenuTheme: DropdownMenuThemeData(textStyle: t.bodyMedium, menuStyle: MenuStyle(backgroundColor: WidgetStatePropertyAll(c.surfaceContainer))),
      datePickerTheme: DatePickerThemeData(backgroundColor: c.surfaceContainer, headerBackgroundColor: c.primaryContainer,
        headerForegroundColor: c.onPrimaryContainer, surfaceTintColor: Colors.transparent),
      dividerTheme: DividerThemeData(color: c.outlineVariant, thickness: .7, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
    );
  }
}
