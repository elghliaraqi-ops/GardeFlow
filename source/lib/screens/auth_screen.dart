import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospitals.dart';
import '../data/intern_promotions.dart';
import '../data/services.dart';
import '../models/app_user.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/screen_decor.dart';
import '../theme/widgets.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';

Color get _loginGreen => AppColors.brand;
Color get _loginGreenDark => AppColors.brandDark;

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _showRegister = false;
  bool _obscureLoginPassword = true;
  bool _obscureRegisterPassword = true;
  bool _isSubmittingLogin = false;
  bool _isSubmittingRegister = false;
  String? _error;
  String? _info;
  String _hospital = kHospitals.first;

  late final AnimationController _entranceController;
  late final Animation<double> _contentOpacity;
  late final Animation<Offset> _contentSlide;

  final _loginPhoneCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();

  final _regNomCtrl = TextEditingController();
  final _regPrenomCtrl = TextEditingController();
  final _regPhoneCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  int? _regPromotion;
  String _regService = kServices.first;
  MedicalGrade _regGrade = MedicalGrade.junior;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _contentOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.05, 1, curve: Curves.easeOutCubic),
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.05, 1, curve: Curves.easeOutCubic),
      ),
    );
    _entranceController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshPromotionConfig();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _loginPhoneCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _regNomCtrl.dispose();
    _regPrenomCtrl.dispose();
    _regPhoneCtrl.dispose();
    _regPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    if (_isSubmittingLogin) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSubmittingLogin = true;
      _error = null;
      _info = null;
    });

    final appState = context.read<AppState>();
    final err = await appState.login(
      _loginPhoneCtrl.text,
      _loginPasswordCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _isSubmittingLogin = false;
      _error = err;
      _info = null;
    });
    if (err == null) _goToApp();
  }

  Future<void> _submitRegister() async {
    if (_isSubmittingRegister) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSubmittingRegister = true;
      _error = null;
      _info = null;
    });

    final appState = context.read<AppState>();
    final err = await appState.register(
      nom: _regNomCtrl.text,
      prenom: _regPrenomCtrl.text,
      rawPhone: _regPhoneCtrl.text,
      password: _regPasswordCtrl.text,
      service: _regService,
      grade: _regGrade,
      hospital: _hospital,
      promotionNumber: _regGrade == MedicalGrade.junior
          ? (_regPromotion ?? appState.currentFirstYearPromotion)
          : null,
    );
    if (!mounted) return;
    setState(() {
      _isSubmittingRegister = false;
      if (err == null) {
        _error = null;
        _info =
            'Compte créé. Un administrateur doit maintenant valider votre inscription avant la première connexion.';
        _showRegister = false;
        _loginPhoneCtrl.text = _regPhoneCtrl.text;
      } else {
        _error = err;
        _info = null;
      }
    });
  }

  void _goToApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _showPasswordHelp() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(initialPhone: _loginPhoneCtrl.text),
      ),
    );
    if (!mounted || changed != true) return;
    setState(() {
      _error = null;
      _info =
          'Mot de passe modifié. Vous pouvez maintenant vous connecter avec votre nouveau mot de passe.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardOpen = bottomInset > 0;

    return DecorScaffold(
      scene: ScreenDecorScene.auth,
      backgroundColor: AppColors.paper,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _LoginBackdrop(),
            SafeArea(
              child: FadeTransition(
                opacity: _contentOpacity,
                child: SlideTransition(
                  position: _contentSlide,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 820 && !keyboardOpen;
                      final horizontalPadding = constraints.maxWidth < 370
                          ? 14.0
                          : constraints.maxWidth < 600
                              ? 20.0
                              : 32.0;

                      return SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          14,
                          horizontalPadding,
                          24,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: (constraints.maxHeight - 38)
                                .clamp(0.0, double.infinity),
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1080),
                              child: wide
                                  ? _buildWideComposition()
                                  : _buildMobileComposition(keyboardOpen),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideComposition() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          flex: 10,
          child: Padding(
            padding: EdgeInsets.only(right: 52),
            child: _LoginBrandHero(expanded: true),
          ),
        ),
        Expanded(
          flex: 9,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470),
            child: _buildAuthSurface(),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileComposition(bool keyboardOpen) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!keyboardOpen || _showRegister) ...[
            _LoginBrandHero(expanded: !_showRegister),
            SizedBox(height: _showRegister ? 16 : 22),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _CompactBrandBar(),
            ),
          _buildAuthSurface(),
        ],
      ),
    );
  }

  Widget _buildAuthSurface() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_info != null)
          _Banner(
            text: _info!,
            tone: _BannerTone.success,
            icon: Icons.check_circle_rounded,
          ),
        if (_error != null)
          _Banner(
            text: _error!,
            tone: _BannerTone.error,
            icon: Icons.error_rounded,
          ),
        _AuthSurface(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.02, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _showRegister ? _buildRegisterForm() : _buildLoginForm(),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    final hasError = _error != null;
    return AutofillGroup(
      key: const ValueKey('login'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Connexion',
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 28,
              height: 1.05,
              letterSpacing: -0.5,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Votre planning, vos gardes et vos astreintes au même endroit.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _loginPhoneCtrl,
            enabled: !_isSubmittingLogin,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            autocorrect: false,
            decoration: _inputDecoration(
              label: 'Numéro de téléphone',
              icon: Icons.phone_iphone_rounded,
              hasError: hasError,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _loginPasswordCtrl,
            enabled: !_isSubmittingLogin,
            obscureText: _obscureLoginPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _submitLogin(),
            decoration: _inputDecoration(
              label: 'Mot de passe',
              icon: Icons.lock_outline_rounded,
              hasError: hasError,
              suffix: IconButton(
                onPressed: _isSubmittingLogin
                    ? null
                    : () => setState(
                          () => _obscureLoginPassword =
                              !_obscureLoginPassword,
                        ),
                icon: Icon(
                  _obscureLoginPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 21,
                ),
                tooltip: _obscureLoginPassword
                    ? 'Afficher le mot de passe'
                    : 'Masquer le mot de passe',
              ),
            ),
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isSubmittingLogin ? null : _showPasswordHelp,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.isDarkMode
                    ? AppColors.brandBright
                    : _loginGreenDark,
                disabledForegroundColor: AppColors.inkFaint,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text(
                'Mot de passe oublié ?',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _PrimaryAuthButton(
            label: 'Se connecter',
            icon: Icons.arrow_forward_rounded,
            loading: _isSubmittingLogin,
            onPressed: _submitLogin,
          ),
          const SizedBox(height: 20),
          const _OrDivider(),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: _isSubmittingLogin
                  ? null
                  : () => setState(() {
                        _showRegister = true;
                        _error = null;
                        _info = null;
                      }),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.isDarkMode
                    ? const Color(0xFFF3FAF6)
                    : _loginGreenDark,
                backgroundColor: AppColors.isDarkMode
                    ? AppColors.surfaceRaised.withOpacity(0.78)
                    : Colors.white.withOpacity(0.72),
                disabledForegroundColor: AppColors.inkFaint,
                side: BorderSide(
                  color: AppColors.isDarkMode
                      ? AppColors.brand.withOpacity(0.72)
                      : _loginGreen.withOpacity(0.55),
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text(
                'Créer un compte',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shield_outlined,
                size: 14,
                color: AppColors.inkFaint,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Accès sécurisé réservé aux utilisateurs GardeFlow',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: AppColors.inkFaint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm() {
    final appState = context.watch<AppState>();
    final latestPromotion = appState.currentFirstYearPromotion;
    final selectedPromotion =
        _regPromotion != null &&
            _regPromotion! >= 1 &&
            _regPromotion! <= latestPromotion
        ? _regPromotion!
        : latestPromotion;
    final promotions = List<int>.generate(
      latestPromotion,
      (index) => latestPromotion - index,
    );

    return AutofillGroup(
      key: const ValueKey('register'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Créer un compte',
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 27,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Retour à la connexion',
                onPressed: _isSubmittingRegister
                    ? null
                    : () => setState(() {
                          _showRegister = false;
                          _error = null;
                          _info = null;
                        }),
                icon: const Icon(Icons.close_rounded),
                color: AppColors.inkSoft,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Renseignez exactement vos informations de planning. Un administrateur validera ensuite votre inscription.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.brandSoft.withOpacity(
                AppColors.isDarkMode ? 0.82 : 0.72,
              ),
              borderRadius: AppRadius.mdR,
              border: Border.all(color: AppColors.brand.withOpacity(0.22)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.isDarkMode
                      ? AppColors.brandBright
                      : AppColors.brandDark,
                  size: 19,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Nom et prénoms complets : GardeFlow rapproche ensuite les variantes usuelles du planning officiel.',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w650,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 360) {
                return Column(
                  children: [
                    TextField(
                      controller: _regNomCtrl,
                      enabled: !_isSubmittingRegister,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.familyName],
                      decoration: _inputDecoration(
                        label: 'Nom',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _regPrenomCtrl,
                      enabled: !_isSubmittingRegister,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.givenName],
                      decoration: _inputDecoration(
                        label: 'Prénom',
                        icon: Icons.badge_outlined,
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _regNomCtrl,
                      enabled: !_isSubmittingRegister,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.familyName],
                      decoration: _inputDecoration(
                        label: 'Nom',
                        icon: Icons.person_outline_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _regPrenomCtrl,
                      enabled: !_isSubmittingRegister,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.givenName],
                      decoration: _inputDecoration(
                        label: 'Prénom',
                        icon: Icons.badge_outlined,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regPhoneCtrl,
            enabled: !_isSubmittingRegister,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: _inputDecoration(
              label: 'Numéro de téléphone',
              icon: Icons.phone_iphone_rounded,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regPasswordCtrl,
            enabled: !_isSubmittingRegister,
            obscureText: _obscureRegisterPassword,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            autocorrect: false,
            enableSuggestions: false,
            decoration: _inputDecoration(
              label: 'Mot de passe',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                onPressed: _isSubmittingRegister
                    ? null
                    : () => setState(
                          () => _obscureRegisterPassword =
                              !_obscureRegisterPassword,
                        ),
                icon: Icon(
                  _obscureRegisterPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 21,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _hospital,
            isExpanded: true,
            decoration: _inputDecoration(
              label: 'Établissement',
              icon: Icons.local_hospital_outlined,
            ),
            items: kHospitals
                .map(
                  (h) => DropdownMenuItem(
                    value: h,
                    child: Text(
                      hospitalDisplayName(h),
                      style: const TextStyle(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _isSubmittingRegister
                ? null
                : (v) => setState(() => _hospital = v ?? _hospital),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _regService,
            isExpanded: true,
            decoration: _inputDecoration(
              label: 'Service actuel',
              icon: Icons.medical_services_outlined,
            ),
            items: kServices
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(
                      s,
                      style: const TextStyle(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _isSubmittingRegister
                ? null
                : (v) => setState(() => _regService = v ?? _regService),
          ),
          const SizedBox(height: 16),
          Text(
            'Grade médical',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _gradeOption(MedicalGrade.junior, 'Junior')),
              const SizedBox(width: 10),
              Expanded(child: _gradeOption(MedicalGrade.senior, 'Senior')),
            ],
          ),
          if (_regGrade == MedicalGrade.junior) ...[
            const SizedBox(height: 16),
            Text(
              'Promotion d’internat',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: selectedPromotion,
              isExpanded: true,
              decoration: _inputDecoration(
                label: 'Promotion',
                icon: Icons.school_outlined,
              ),
              items: promotions.map((promo) {
                final year = InternPromotions.yearLabelForPromotion(
                  promo,
                  firstYearPromotion: latestPromotion,
                );
                return DropdownMenuItem<int>(
                  value: promo,
                  child: Text(
                    'Promo $promo${year == null ? '' : ' · $year'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _isSubmittingRegister
                  ? null
                  : (value) => setState(() => _regPromotion = value),
            ),
          ],
          const SizedBox(height: 20),
          _PrimaryAuthButton(
            label: 'Créer mon compte',
            icon: Icons.person_add_alt_1_rounded,
            loading: _isSubmittingRegister,
            onPressed: _submitRegister,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isSubmittingRegister
                ? null
                : () => setState(() {
                      _showRegister = false;
                      _error = null;
                      _info = null;
                    }),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.isDarkMode
                  ? AppColors.brandBright
                  : _loginGreenDark,
            ),
            child: const Text(
              'Déjà inscrit ? Se connecter',
              style: TextStyle(fontWeight: FontWeight.w750),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
    bool hasError = false,
  }) {
    final dark = AppColors.isDarkMode;
    final radius = BorderRadius.circular(AppRadius.md);
    final neutralBorder = dark
        ? AppColors.line.withOpacity(0.95)
        : const Color(0xFFD4E0D9);
    final focus = dark ? AppColors.brandBright : AppColors.brandDark;
    final errorColor = AppColors.danger;

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: dark
          ? AppColors.paperAlt.withOpacity(0.88)
          : const Color(0xFFF7FAF8),
      labelStyle: TextStyle(
        color: hasError ? errorColor : AppColors.inkSoft,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: TextStyle(
        color: hasError ? errorColor : focus,
        fontWeight: FontWeight.w800,
      ),
      prefixIconColor: hasError ? errorColor : AppColors.inkFaint,
      suffixIconColor: AppColors.inkFaint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
      border: border(neutralBorder, 1),
      enabledBorder:
          border(hasError ? errorColor.withOpacity(0.82) : neutralBorder, 1),
      focusedBorder: border(hasError ? errorColor : focus, 1.7),
      errorBorder: border(errorColor, 1.3),
      focusedErrorBorder: border(errorColor, 1.7),
      disabledBorder: border(neutralBorder.withOpacity(0.45), 1),
    );
  }

  Widget _gradeOption(MedicalGrade value, String label) {
    final selected = _regGrade == value;
    final disabled = _isSubmittingRegister;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: disabled ? null : () => setState(() => _regGrade = value),
        borderRadius: AppRadius.mdR,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: selected
                ? _loginGreen
                : AppColors.paperAlt.withOpacity(AppColors.isDarkMode ? 0.95 : 0.82),
            border: Border.all(
              color: selected ? _loginGreen : AppColors.line,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: AppRadius.mdR,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected ? AppColors.onBrand : AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDarkMode;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/branding/login_urgences.jpg',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [
                      AppColors.paper.withOpacity(0.98),
                      AppColors.paper.withOpacity(0.91),
                      AppColors.paperAlt.withOpacity(0.94),
                    ]
                  : [
                      const Color(0xFFF8FBF9).withOpacity(0.98),
                      const Color(0xFFF1F8F4).withOpacity(0.91),
                      const Color(0xFFE6F4EC).withOpacity(0.94),
                    ],
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -70,
          child: IgnorePointer(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brand.withOpacity(dark ? 0.13 : 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginBrandHero extends StatelessWidget {
  final bool expanded;
  const _LoginBrandHero({this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDarkMode;
    final logoSize = expanded ? 92.0 : 76.0;
    return Semantics(
      header: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            expanded ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            width: logoSize + 18,
            height: logoSize + 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.surfaceRaised.withOpacity(0.88)
                  : Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: dark
                    ? AppColors.line.withOpacity(0.9)
                    : Colors.white.withOpacity(0.95),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(dark ? 0.20 : 0.08),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: GardeFlowLogo(size: logoSize),
          ),
          SizedBox(height: expanded ? 26 : 16),
          RichText(
            textAlign: expanded ? TextAlign.left : TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: expanded ? 45 : 34,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: expanded ? -1.8 : -1.1,
              ),
              children: [
                TextSpan(text: 'Garde', style: TextStyle(color: AppColors.brand)),
                const TextSpan(
                  text: 'Flow',
                  style: TextStyle(color: AppColors.cyan),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Le planning de garde pour garder le flow.',
            textAlign: expanded ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              fontSize: expanded ? 16 : 13.5,
              height: 1.45,
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w650,
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 28),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _BrandCapability(icon: Icons.calendar_month_outlined, label: 'Planning'),
                _BrandCapability(icon: Icons.sync_alt_rounded, label: 'Échanges'),
                _BrandCapability(icon: Icons.notifications_active_outlined, label: 'Rappels'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactBrandBar extends StatelessWidget {
  const _CompactBrandBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const GardeFlowLogo(size: 38),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
            children: [
              TextSpan(text: 'Garde', style: TextStyle(color: AppColors.brand)),
              const TextSpan(text: 'Flow', style: TextStyle(color: AppColors.cyan)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandCapability extends StatelessWidget {
  final IconData icon;
  final String label;
  const _BrandCapability({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(AppColors.isDarkMode ? 0.58 : 0.78),
        borderRadius: AppRadius.pillR,
        border: Border.all(color: AppColors.line.withOpacity(0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.brandBright),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w750,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthSurface extends StatelessWidget {
  final Widget child;
  const _AuthSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDarkMode;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        MediaQuery.of(context).size.width < 370 ? 18 : 24,
        25,
        MediaQuery.of(context).size.width < 370 ? 18 : 24,
        22,
      ),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.card.withOpacity(0.96)
            : Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: dark
              ? AppColors.line.withOpacity(0.92)
              : Colors.white.withOpacity(0.95),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(dark ? 0.24 : 0.09),
            blurRadius: 34,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PrimaryAuthButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onPressed;

  const _PrimaryAuthButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !loading,
      label: loading ? '$label, chargement' : label,
      child: SizedBox(
        height: 56,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: loading ? null : onPressed,
            borderRadius: AppRadius.mdR,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.brandDark, AppColors.brand],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: AppRadius.mdR,
                boxShadow: loading
                    ? const []
                    : [
                        BoxShadow(
                          color: AppColors.brand.withOpacity(0.24),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 170),
                child: loading
                    ? Center(
                        key: const ValueKey('loading'),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppColors.onBrand,
                          ),
                        ),
                      )
                    : Row(
                        key: const ValueKey('label'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: AppColors.onBrand,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(icon, color: AppColors.onBrand, size: 20),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.line.withOpacity(0.8))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'ou',
            style: TextStyle(
              color: AppColors.inkFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.line.withOpacity(0.8))),
      ],
    );
  }
}

enum _BannerTone { success, error }

class _Banner extends StatelessWidget {
  final String text;
  final _BannerTone tone;
  final IconData icon;
  const _Banner({
    required this.text,
    required this.tone,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final success = tone == _BannerTone.success;
    final foreground = success ? AppColors.success : AppColors.danger;
    final background = success
        ? AppColors.success.withOpacity(AppColors.isDarkMode ? 0.13 : 0.10)
        : AppColors.danger.withOpacity(AppColors.isDarkMode ? 0.14 : 0.09);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: foreground.withOpacity(0.34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: foreground),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w650,
                height: 1.35,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
