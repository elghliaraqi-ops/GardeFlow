import 'dart:ui' as ui;

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
const Color _flowRed = Color(0xFFE25A56);

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
  String? _error;
  String? _info;
  String _hospital = kHospitals.first;

  late final AnimationController _entranceController;
  late final Animation<double> _contentOpacity;
  late final Animation<Offset> _contentSlide;

  final _loginPhoneCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  final _loginPhoneFocus = FocusNode(debugLabel: 'login-phone');
  final _loginPasswordFocus = FocusNode(debugLabel: 'login-password');

  final _regNomCtrl = TextEditingController();
  final _regPrenomCtrl = TextEditingController();
  final _regPhoneCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  int? _regPromotion;
  String _regService = kServices.first;
  MedicalPosition? _regPosition;
  TrainingLanguage? _regTrainingLanguage;
  int? _regTrainingYear;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _contentOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.08, 1, curve: Curves.easeOutCubic),
    );
    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.022), end: Offset.zero).animate(
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
    _loginPhoneFocus.dispose();
    _loginPasswordFocus.dispose();
    _regNomCtrl.dispose();
    _regPrenomCtrl.dispose();
    _regPhoneCtrl.dispose();
    _regPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    final appState = context.read<AppState>();
    final err = await appState.login(
      _loginPhoneCtrl.text,
      _loginPasswordCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _error = err;
      _info = null;
    });
    if (err == null) _goToApp();
  }

  Future<void> _submitRegister() async {
    final position = _regPosition;
    if (_regTrainingLanguage == null) {
      setState(() => _error = 'Sélectionnez votre langue de formation.');
      return;
    }
    if (position == null) {
      setState(() => _error = 'Sélectionnez votre statut médical.');
      return;
    }
    final appState = context.read<AppState>();
    final err = await appState.register(
      nom: _regNomCtrl.text,
      prenom: _regPrenomCtrl.text,
      rawPhone: _regPhoneCtrl.text,
      password: _regPasswordCtrl.text,
      service: _regService,
      medicalPosition: position,
      trainingLanguage: _regTrainingLanguage!,
      trainingYear: position.requiresPromotion ? null : _regTrainingYear,
      hospital: _hospital,
      promotionNumber: position.requiresPromotion
          ? (_regPromotion ?? appState.currentFirstYearPromotion)
          : null,
    );
    if (!mounted) return;
    if (err == null) {
      setState(() {
        _error = null;
        _info =
            'Compte créé. Un administrateur doit maintenant valider votre inscription avant la première connexion.';
        _showRegister = false;
        _loginPhoneCtrl.text = _regPhoneCtrl.text;
      });
    } else {
      setState(() {
        _error = err;
        _info = null;
      });
    }
  }

  void _goToApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _showPasswordHelp() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ForgotPasswordScreen(initialPhone: _loginPhoneCtrl.text),
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
    return DecorScaffold(
      scene: ScreenDecorScene.auth,
      backgroundColor: AppColors.paper,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),
          SafeArea(
            minimum: const EdgeInsets.symmetric(horizontal: 14),
            child: FadeTransition(
              opacity: _contentOpacity,
              child: SlideTransition(
                position: _contentSlide,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_showRegister) {
                      return Center(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 18),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: _buildRegisterContent(),
                          ),
                        ),
                      );
                    }

                    final keyboardOpen =
                        MediaQuery.viewInsetsOf(context).bottom > 0;
                    final density = _LoginDensity.resolve(
                      constraints.maxHeight,
                      keyboardOpen: keyboardOpen,
                    );
                    final maxWidth = constraints.maxWidth > 440
                        ? 440.0
                        : constraints.maxWidth;

                    return Center(
                      child: SizedBox(
                        width: maxWidth,
                        height: constraints.maxHeight,
                        child: _buildLoginContent(
                          density,
                          keyboardOpen: keyboardOpen,
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
    );
  }

  Widget _buildBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/branding/login_urgences.jpg',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
        ),
        AnimatedBuilder(
          animation: _entranceController,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_entranceController.value);
            return BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: 7.5 * t,
                sigmaY: 7.5 * t,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.isDarkMode
                  ? const [
                      Color(0xF2080B09),
                      Color(0xE70B1712),
                      Color(0xF50A0D0B),
                    ]
                  : [
                      Colors.white.withOpacity(.86),
                      const Color(0xFFE8F5EE).withOpacity(.80),
                      Colors.white.withOpacity(.90),
                    ],
              stops: const [0, .52, 1],
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(.78, -.82),
                radius: 1.08,
                colors: [
                  _loginGreen.withOpacity(AppColors.isDarkMode ? .15 : .10),
                  Colors.transparent,
                ],
                stops: const [0, .64],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _LoginAmbientPainter(
              green: _loginGreen.withOpacity(.10),
              red: _flowRed.withOpacity(.055),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginContent(
    _LoginDensity d, {
    required bool keyboardOpen,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LoginBrandHeader(density: d),
        SizedBox(height: d.headerToChips),
        _FeatureCapsules(density: d),
        SizedBox(height: d.chipsToCard),
        if (_info != null) ...[
          _Banner(
            text: _info!,
            background: const Color(0xFF123F2F),
            foreground: const Color(0xFF69E2A8),
            icon: Icons.check_circle_rounded,
          ),
          SizedBox(height: d.compactGap),
        ],
        if (_error != null) ...[
          _Banner(
            text: _error!,
            background: const Color(0xFF421C1E),
            foreground: const Color(0xFFFF908C),
            icon: Icons.error_rounded,
          ),
          SizedBox(height: d.compactGap),
        ],
        _LoginGlassCard(
          density: d,
          child: _buildLoginForm(d),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: d.outerVertical),
      child: Align(
        alignment: keyboardOpen ? Alignment.topCenter : Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: d.designWidth,
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _LoginBrandHeader(
          density: _LoginDensity.regular,
        ),
        const SizedBox(height: 14),
        if (_info != null) ...[
          _Banner(
            text: _info!,
            background: const Color(0xFF123F2F),
            foreground: const Color(0xFF69E2A8),
            icon: Icons.check_circle_rounded,
          ),
          const SizedBox(height: 8),
        ],
        if (_error != null) ...[
          _Banner(
            text: _error!,
            background: const Color(0xFF421C1E),
            foreground: const Color(0xFFFF908C),
            icon: Icons.error_rounded,
          ),
          const SizedBox(height: 8),
        ],
        const _FeatureCapsules(density: _LoginDensity.regular),
        const SizedBox(height: 14),
        _LoginGlassCard(
          density: _LoginDensity.regular,
          child: _buildRegisterForm(),
        ),
      ],
    );
  }

  Widget _buildLoginForm(_LoginDensity d) {
    return AutofillGroup(
      child: Column(
        key: const ValueKey('login'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Connexion',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: d.cardTitleSize,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: -.35,
              color: AppColors.ink,
            ),
          ),
          SizedBox(height: d.titleGap),
          Text(
            'Votre planning, vos gardes et vos astreintes au même endroit.',
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              fontSize: d.subtitleSize,
              height: 1.35,
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: d.formGap),
          SizedBox(
            height: d.fieldHeight,
            child: TextField(
              controller: _loginPhoneCtrl,
              focusNode: _loginPhoneFocus,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              onSubmitted: (_) => _loginPasswordFocus.requestFocus(),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: _glassInputDecoration(
                hint: 'Numéro de téléphone',
                icon: Icons.phone_iphone_rounded,
                dense: d.isCompact,
              ),
            ),
          ),
          SizedBox(height: d.fieldGap),
          SizedBox(
            height: d.fieldHeight,
            child: TextField(
              controller: _loginPasswordCtrl,
              focusNode: _loginPasswordFocus,
              obscureText: _obscureLoginPassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submitLogin(),
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: _glassInputDecoration(
                hint: 'Mot de passe',
                icon: Icons.lock_outline_rounded,
                dense: d.isCompact,
                suffix: IconButton(
                  onPressed: () => setState(
                    () => _obscureLoginPassword = !_obscureLoginPassword,
                  ),
                  icon: Icon(
                    _obscureLoginPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: d.isCompact ? 19 : 21,
                    color: AppColors.inkFaint,
                  ),
                  tooltip: _obscureLoginPassword
                      ? 'Afficher le mot de passe'
                      : 'Masquer le mot de passe',
                ),
              ),
            ),
          ),
          SizedBox(height: d.forgotTop),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showPasswordHelp,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.isDarkMode
                    ? const Color(0xFF77E7B0)
                    : _loginGreenDark,
                minimumSize: Size(0, d.forgotHeight),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Mot de passe oublié ?',
                style: TextStyle(
                  fontSize: d.helperSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(height: d.buttonTop),
          _GradientPrimaryButton(
            label: 'Se connecter',
            icon: Icons.arrow_forward_rounded,
            height: d.primaryButtonHeight,
            onPressed: _submitLogin,
          ),
          SizedBox(height: d.dividerTop),
          const _OrDivider(),
          SizedBox(height: d.dividerBottom),
          SizedBox(
            height: d.secondaryButtonHeight,
            child: OutlinedButton(
              onPressed: () {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() {
                  _showRegister = true;
                  _error = null;
                  _info = null;
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                backgroundColor: AppColors.isDarkMode
                    ? const Color(0xFF13231C).withOpacity(.72)
                    : Colors.white.withOpacity(.55),
                side: BorderSide(
                  color: _loginGreen.withOpacity(.38),
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                'Créer un compte',
                style: TextStyle(
                  fontSize: d.secondaryButtonText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
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

    return Column(
      key: const ValueKey('register'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: AppColors.brandSoft.withOpacity(.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.brand.withOpacity(.20)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.success,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Important : renseignez vos nom et prénoms complets. GardeFlow rapproche automatiquement les variantes usuelles du planning officiel (par exemple un prénom composé abrégé).',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 11.5,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          'Créer un compte',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 25,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Votre inscription sera validée par un administrateur.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: AppColors.inkSoft,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _regNomCtrl,
                decoration: _glassInputDecoration(
                  hint: 'Nom',
                  icon: Icons.person_outline_rounded,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _regPrenomCtrl,
                decoration: _glassInputDecoration(
                  hint: 'Prénom',
                  icon: Icons.badge_outlined,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPhoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: _glassInputDecoration(
            hint: 'Numéro de téléphone',
            icon: Icons.phone_android_rounded,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPasswordCtrl,
          obscureText: _obscureRegisterPassword,
          decoration: _glassInputDecoration(
            hint: 'Mot de passe',
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              onPressed: () => setState(
                () => _obscureRegisterPassword = !_obscureRegisterPassword,
              ),
              icon: Icon(
                _obscureRegisterPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.inkFaint,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _hospital,
          isExpanded: true,
          decoration: _glassInputDecoration(
            hint: 'Établissement',
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
          onChanged: (v) => setState(() => _hospital = v ?? _hospital),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _regService,
          isExpanded: true,
          decoration: _glassInputDecoration(
            hint: 'Service actuel',
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
          onChanged: (v) => setState(() => _regService = v ?? _regService),
        ),
        const SizedBox(height: 16),
        Text(
          'Statut médical',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<MedicalPosition>(
          value: _regPosition,
          isExpanded: true,
          decoration: _glassInputDecoration(
            hint: 'Sélectionnez votre statut',
            icon: Icons.school_outlined,
          ),
          items: MedicalPosition.values
              .map((position) => DropdownMenuItem<MedicalPosition>(
                    value: position,
                    child: Text(
                      position.label,
                      style: const TextStyle(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (value) => setState(() {
            _regPosition = value;
            _regTrainingYear = null;
            _regPromotion = null;
            _error = null;
          }),
        ),
        const SizedBox(height: 16),
        Text(
          'Langue de formation',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<TrainingLanguage>(
          value: _regTrainingLanguage,
          isExpanded: true,
          decoration: _glassInputDecoration(
            hint: 'Anglophone ou Francophone',
            icon: Icons.language_rounded,
          ),
          items: TrainingLanguage.values
              .map((language) => DropdownMenuItem<TrainingLanguage>(
                    value: language,
                    child: Text(
                      language.label,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ))
              .toList(),
          onChanged: (value) => setState(() {
            _regTrainingLanguage = value;
            _error = null;
          }),
        ),
        if (_regPosition != null &&
            _regPosition!.trainingYears.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Année d’études',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: ValueKey(_regPosition),
            value: _regTrainingYear,
            isExpanded: true,
            decoration: _glassInputDecoration(
              hint: 'Sélectionnez votre année',
              icon: Icons.calendar_today_outlined,
            ),
            items: _regPosition!.trainingYears
                .map((year) => DropdownMenuItem<int>(
                      value: year,
                      child: Text(year == 1 ? '1re année' : '${year}e année'),
                    ))
                .toList(),
            onChanged: (value) =>
                setState(() => _regTrainingYear = value),
          ),
        ],
        if (_regPosition == MedicalPosition.interne) ...[
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
            decoration: _glassInputDecoration(
              hint: 'Promotion',
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
            onChanged: (value) => setState(() => _regPromotion = value),
          ),
        ],
        const SizedBox(height: 20),
        _GradientPrimaryButton(
          label: 'Créer mon compte',
          icon: Icons.person_add_alt_1_rounded,
          height: 52,
          onPressed: _submitRegister,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() {
            _showRegister = false;
            _error = null;
            _info = null;
          }),
          style: TextButton.styleFrom(
            foregroundColor:
                AppColors.isDarkMode ? AppColors.brandBright : _loginGreenDark,
          ),
          child: const Text('Déjà inscrit ? Se connecter'),
        ),
      ],
    );
  }

  InputDecoration _glassInputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
    bool dense = false,
  }) {
    final idle = AppColors.isDarkMode
        ? const Color(0xFF324139)
        : const Color(0xFFCEDDD5);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: idle.withOpacity(.78), width: 1),
    );
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color: AppColors.isDarkMode
            ? const Color(0xFF8EA69A)
            : AppColors.inkFaint,
        size: dense ? 19 : 21,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.isDarkMode
          ? const Color(0xB8141C18)
          : Colors.white.withOpacity(.72),
      hintStyle: TextStyle(
        color: AppColors.inkFaint,
        fontSize: dense ? 13 : 14,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 13,
        vertical: dense ? 10 : 14,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: _loginGreen, width: 1.35),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _flowRed, width: 1.15),
      ),
    );
  }


}

class _LoginDensity {
  final double designWidth;
  final double outerVertical;
  final double logoSize;
  final double logoPadding;
  final double logoRadius;
  final double logoToTitle;
  final double titleSize;
  final double sloganSize;
  final double sloganGap;
  final double headerToChips;
  final double chipHeight;
  final double chipFontSize;
  final double chipsToCard;
  final double cardPaddingH;
  final double cardPaddingV;
  final double cardRadius;
  final double cardTitleSize;
  final double subtitleSize;
  final double titleGap;
  final double formGap;
  final double fieldHeight;
  final double fieldGap;
  final double forgotTop;
  final double forgotHeight;
  final double helperSize;
  final double buttonTop;
  final double primaryButtonHeight;
  final double dividerTop;
  final double dividerBottom;
  final double secondaryButtonHeight;
  final double secondaryButtonText;
  final double compactGap;
  final bool isCompact;

  const _LoginDensity({
    required this.designWidth,
    required this.outerVertical,
    required this.logoSize,
    required this.logoPadding,
    required this.logoRadius,
    required this.logoToTitle,
    required this.titleSize,
    required this.sloganSize,
    required this.sloganGap,
    required this.headerToChips,
    required this.chipHeight,
    required this.chipFontSize,
    required this.chipsToCard,
    required this.cardPaddingH,
    required this.cardPaddingV,
    required this.cardRadius,
    required this.cardTitleSize,
    required this.subtitleSize,
    required this.titleGap,
    required this.formGap,
    required this.fieldHeight,
    required this.fieldGap,
    required this.forgotTop,
    required this.forgotHeight,
    required this.helperSize,
    required this.buttonTop,
    required this.primaryButtonHeight,
    required this.dividerTop,
    required this.dividerBottom,
    required this.secondaryButtonHeight,
    required this.secondaryButtonText,
    required this.compactGap,
    required this.isCompact,
  });

  static const regular = _LoginDensity(
    designWidth: 420,
    outerVertical: 10,
    logoSize: 62,
    logoPadding: 5,
    logoRadius: 20,
    logoToTitle: 7,
    titleSize: 35,
    sloganSize: 12.5,
    sloganGap: 3,
    headerToChips: 12,
    chipHeight: 31,
    chipFontSize: 10.5,
    chipsToCard: 14,
    cardPaddingH: 21,
    cardPaddingV: 20,
    cardRadius: 25,
    cardTitleSize: 24,
    subtitleSize: 12.8,
    titleGap: 5,
    formGap: 15,
    fieldHeight: 50,
    fieldGap: 10,
    forgotTop: 2,
    forgotHeight: 34,
    helperSize: 11.5,
    buttonTop: 2,
    primaryButtonHeight: 50,
    dividerTop: 12,
    dividerBottom: 10,
    secondaryButtonHeight: 45,
    secondaryButtonText: 13,
    compactGap: 7,
    isCompact: false,
  );

  static const compact = _LoginDensity(
    designWidth: 410,
    outerVertical: 5,
    logoSize: 50,
    logoPadding: 4,
    logoRadius: 17,
    logoToTitle: 5,
    titleSize: 30,
    sloganSize: 11,
    sloganGap: 2,
    headerToChips: 8,
    chipHeight: 27,
    chipFontSize: 9.5,
    chipsToCard: 9,
    cardPaddingH: 17,
    cardPaddingV: 15,
    cardRadius: 22,
    cardTitleSize: 21,
    subtitleSize: 11.5,
    titleGap: 4,
    formGap: 10,
    fieldHeight: 45,
    fieldGap: 8,
    forgotTop: 0,
    forgotHeight: 29,
    helperSize: 10.5,
    buttonTop: 1,
    primaryButtonHeight: 45,
    dividerTop: 9,
    dividerBottom: 8,
    secondaryButtonHeight: 40,
    secondaryButtonText: 12,
    compactGap: 5,
    isCompact: true,
  );

  static const keyboard = _LoginDensity(
    designWidth: 400,
    outerVertical: 2,
    logoSize: 42,
    logoPadding: 3,
    logoRadius: 15,
    logoToTitle: 3,
    titleSize: 27,
    sloganSize: 10.2,
    sloganGap: 1,
    headerToChips: 5,
    chipHeight: 24,
    chipFontSize: 8.7,
    chipsToCard: 6,
    cardPaddingH: 15,
    cardPaddingV: 12,
    cardRadius: 20,
    cardTitleSize: 19,
    subtitleSize: 10.5,
    titleGap: 3,
    formGap: 8,
    fieldHeight: 42,
    fieldGap: 7,
    forgotTop: 0,
    forgotHeight: 26,
    helperSize: 9.7,
    buttonTop: 0,
    primaryButtonHeight: 42,
    dividerTop: 7,
    dividerBottom: 6,
    secondaryButtonHeight: 36,
    secondaryButtonText: 11,
    compactGap: 4,
    isCompact: true,
  );

  static _LoginDensity resolve(
    double availableHeight, {
    required bool keyboardOpen,
  }) {
    if (keyboardOpen || availableHeight < 500) return keyboard;
    if (availableHeight < 690) return compact;
    return regular;
  }
}

class _LoginBrandHeader extends StatelessWidget {
  final _LoginDensity density;

  const _LoginBrandHeader({required this.density});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(density.logoPadding),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1712).withOpacity(.82),
            borderRadius: BorderRadius.circular(density.logoRadius),
            border: Border.all(
              color: Colors.white.withOpacity(.09),
              width: .8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: GardeFlowLogo(size: density.logoSize),
        ),
        SizedBox(height: density.logoToTitle),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: density.titleSize,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.25,
              ),
              children: [
                TextSpan(
                  text: 'Garde',
                  style: TextStyle(color: _loginGreen),
                ),
                const TextSpan(
                  text: 'Flow',
                  style: TextStyle(color: _flowRed),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: density.sloganGap),
        Text(
          'Le planning de garde pour garder le flow.',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            color: AppColors.isDarkMode
                ? const Color(0xFFC7D5CE)
                : AppColors.inkSoft,
            fontSize: density.sloganSize,
            fontWeight: FontWeight.w600,
            letterSpacing: .12,
          ),
        ),
      ],
    );
  }
}

class _FeatureCapsules extends StatelessWidget {
  final _LoginDensity density;

  const _FeatureCapsules({required this.density});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.calendar_month_rounded, 'Planning'),
      (Icons.swap_horiz_rounded, 'Échanges'),
      (Icons.notifications_active_outlined, 'Rappels'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Flexible(
            child: _FeatureCapsule(
              icon: items[i].$1,
              label: items[i].$2,
              height: density.chipHeight,
              fontSize: density.chipFontSize,
            ),
          ),
          if (i != items.length - 1)
            SizedBox(width: density.isCompact ? 6 : 8),
        ],
      ],
    );
  }
}

class _FeatureCapsule extends StatelessWidget {
  final IconData icon;
  final String label;
  final double height;
  final double fontSize;

  const _FeatureCapsule({
    required this.icon,
    required this.label,
    required this.height,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111A16).withOpacity(.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withOpacity(.095),
          width: .8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: fontSize + 4, color: const Color(0xFF67DDA2)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                color: const Color(0xFFD8E4DE),
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginGlassCard extends StatelessWidget {
  final Widget child;
  final _LoginDensity density;

  const _LoginGlassCard({
    required this.child,
    required this.density,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(density.cardRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: density.cardPaddingH,
            vertical: density.cardPaddingV,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.isDarkMode
                  ? [
                      const Color(0xE5161E1A),
                      const Color(0xE20D1511),
                    ]
                  : [
                      Colors.white.withOpacity(.83),
                      const Color(0xFFF0F8F3).withOpacity(.78),
                    ],
            ),
            borderRadius: BorderRadius.circular(density.cardRadius),
            border: Border.all(
              color: AppColors.isDarkMode
                  ? Colors.white.withOpacity(.10)
                  : Colors.white.withOpacity(.70),
              width: .9,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(
                  AppColors.isDarkMode ? .28 : .10,
                ),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GradientPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final double height;
  final VoidCallback onPressed;

  const _GradientPrimaryButton({
    required this.label,
    required this.icon,
    required this.height,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.brandBright,
                _loginGreenDark,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(.08),
              width: .8,
            ),
            boxShadow: [
              BoxShadow(
                color: _loginGreen.withOpacity(.18),
                blurRadius: 13,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.onBrand,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(icon, color: AppColors.onBrand, size: 20),
              const SizedBox(width: 15),
            ],
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
        Expanded(
          child: Divider(
            color: AppColors.line.withOpacity(.72),
            height: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Text(
            'ou',
            style: TextStyle(
              color: AppColors.inkFaint,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: AppColors.line.withOpacity(.72),
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  final IconData icon;

  const _Banner({
    required this.text,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: background.withOpacity(.90),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withOpacity(.16)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginAmbientPainter extends CustomPainter {
  final Color green;
  final Color red;

  const _LoginAmbientPainter({
    required this.green,
    required this.red,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final greenPaint = Paint()
      ..color = green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final y = size.height * .31;
    final path = Path()
      ..moveTo(size.width * .02, y)
      ..lineTo(size.width * .20, y)
      ..lineTo(size.width * .245, y - 7)
      ..lineTo(size.width * .275, y + 10)
      ..lineTo(size.width * .315, y - 22)
      ..lineTo(size.width * .355, y + 7)
      ..lineTo(size.width * .40, y)
      ..lineTo(size.width * .63, y);
    canvas.drawPath(path, greenPaint);

    final redPaint = Paint()
      ..color = red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * .88, size.height * .16),
      2.1,
      redPaint,
    );
    canvas.drawCircle(
      Offset(size.width * .91, size.height * .18),
      1.2,
      redPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LoginAmbientPainter oldDelegate) =>
      oldDelegate.green != green || oldDelegate.red != red;
}
