import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospitals.dart';
import '../data/intern_promotions.dart';
import '../data/services.dart';
import '../models/app_user.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_identity.dart';
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
  String? _error;
  String? _info;
  String _hospital = kHospitals.first;

  late final AnimationController _entranceController;
  late final Animation<double> _contentOpacity;
  late final Animation<Offset> _contentSlide;

  // Connexion
  final _loginPhoneCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();

  // Inscription
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
      duration: const Duration(milliseconds: 1250),
    );
    _contentOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.18, 1, curve: Curves.easeOutCubic),
    );
    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.12, 1, curve: Curves.easeOutCubic),
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
    if (err == null) {
      setState(() {
        _error = null;
        _info = 'Compte créé. Un administrateur doit maintenant valider votre inscription avant la première connexion.';
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
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
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
      _info = 'Mot de passe modifié. Vous pouvez maintenant vous connecter avec votre nouveau mot de passe.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      resizeToAvoidBottomInset: true,
      body: Stack(
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
              final t = Curves.easeInOutCubic.transform(
                _entranceController.value,
              );
              final sigma = 8.5 * t;
              return BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: Container(
                  color: AppColors.isDarkMode
                      ? AppColors.paper.withOpacity(0.42 + (0.16 * t))
                      : Colors.white.withOpacity(0.05 + (0.10 * t)),
                ),
              );
            },
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: AppColors.isDarkMode
                    ? [
                        AppColors.paper.withOpacity(0.96),
                        AppColors.paperAlt.withOpacity(0.88),
                        AppColors.card.withOpacity(0.92),
                        AppColors.paper.withOpacity(0.98),
                      ]
                    : [
                        Colors.white.withOpacity(0.68),
                        Colors.white.withOpacity(0.34),
                        Colors.white.withOpacity(0.54),
                        Color(0xFFEAF7EF).withOpacity(0.78),
                      ],
                stops: [0, 0.28, 0.70, 1],
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _contentOpacity,
              child: SlideTransition(
                position: _contentSlide,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_showRegister) {
                      return Center(
                        child: SingleChildScrollView(
                          physics: BouncingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(18, 16, 18, 20),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: 460),
                            child: _buildAuthContent(
                              register: true,
                              compactLogin: false,
                            ),
                          ),
                        ),
                      );
                    }

                    final availableWidth = constraints.maxWidth - 28;
                    final contentWidth = availableWidth > 440
                        ? 440.0
                        : availableWidth;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: contentWidth,
                            child: _buildAuthContent(
                              register: false,
                              compactLogin: true,
                            ),
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
    );
  }

  Widget _buildAuthContent({
    required bool register,
    required bool compactLogin,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GardeFlowBrandBlock(compact: true, subtitleColor: _loginGreen),
        SizedBox(height: compactLogin ? 10 : 18),
        if (_info != null) ...[
          _Banner(
            text: _info!,
            background: Color(0xFFE7F6ED),
            foreground: _loginGreenDark,
            icon: Icons.check_circle_rounded,
          ),
          SizedBox(height: 7),
        ],
        if (_error != null) ...[
          _Banner(
            text: _error!,
            background: Color(0xFFFFE7E3),
            foreground: AppColors.danger,
            icon: Icons.error_rounded,
          ),
          SizedBox(height: 7),
        ],
        _GlassCard(
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: register ? _buildRegisterForm() : _buildLoginForm(),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Column(
      key: ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Bienvenue',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 27,
            fontWeight: FontWeight.w700,
            color: _loginGreenDark,
          ),
        ),
        SizedBox(height: 7),
        Text(
          'Connectez-vous pour accéder\nà votre planning de gardes',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: AppColors.inkSoft,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 15),
        TextField(
          controller: _loginPhoneCtrl,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          decoration: _glassInputDecoration(
            hint: 'Numéro de téléphone',
            icon: Icons.phone_android_rounded,
          ),
        ),
        SizedBox(height: 12),
        TextField(
          controller: _loginPasswordCtrl,
          obscureText: _obscureLoginPassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitLogin(),
          decoration: _glassInputDecoration(
            hint: 'Mot de passe',
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              onPressed: () => setState(
                () => _obscureLoginPassword = !_obscureLoginPassword,
              ),
              icon: Icon(
                _obscureLoginPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.inkFaint,
              ),
              tooltip: _obscureLoginPassword
                  ? 'Afficher le mot de passe'
                  : 'Masquer le mot de passe',
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showPasswordHelp,
            style: TextButton.styleFrom(
              foregroundColor: _loginGreenDark,
              padding: EdgeInsets.fromLTRB(8, 10, 2, 8),
            ),
            child: Text('Mot de passe oublié ?'),
          ),
        ),
        SizedBox(height: 2),
        _GradientPrimaryButton(
          label: 'Se connecter',
          icon: Icons.arrow_forward_rounded,
          onPressed: _submitLogin,
        ),
        SizedBox(height: 12),
        _OrDivider(),
        SizedBox(height: 11),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: () => setState(() {
              _showRegister = true;
              _error = null;
              _info = null;
            }),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.isDarkMode
                  ? Colors.white
                  : _loginGreenDark,
              backgroundColor: AppColors.isDarkMode
                  ? AppColors.brand.withOpacity(0.18)
                  : Colors.white.withOpacity(0.28),
              side: BorderSide(
                color: AppColors.isDarkMode ? AppColors.brand : _loginGreen,
                width: 1.4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Text(
              'Créer un compte',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
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
      key: ValueKey('register'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: 14),
          padding: EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: AppColors.brandSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.brand.withOpacity(0.16)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.brand,
                size: 20,
              ),
              SizedBox(width: 9),
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
            fontSize: 27,
            fontWeight: FontWeight.w700,
            color: AppColors.isDarkMode ? AppColors.brand : _loginGreenDark,
          ),
        ),
        SizedBox(height: 6),
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
        SizedBox(height: 20),
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
            SizedBox(width: 10),
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
        SizedBox(height: 12),
        TextField(
          controller: _regPhoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: _glassInputDecoration(
            hint: 'Numéro de téléphone',
            icon: Icons.phone_android_rounded,
          ),
        ),
        SizedBox(height: 12),
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
        SizedBox(height: 12),
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
                    style: TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _hospital = v ?? _hospital),
        ),
        SizedBox(height: 12),
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
                    style: TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _regService = v ?? _regService),
        ),
        SizedBox(height: 16),
        Text(
          'Grade médical',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AppColors.inkSoft,
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _gradeOption(MedicalGrade.junior, 'Junior')),
            SizedBox(width: 10),
            Expanded(child: _gradeOption(MedicalGrade.senior, 'Senior')),
          ],
        ),
        if (_regGrade == MedicalGrade.junior) ...[
          SizedBox(height: 16),
          Text(
            'Promotion d’internat',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.inkSoft,
            ),
          ),
          SizedBox(height: 8),
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
          SizedBox(height: 7),
          Text(
            'La Promo $latestPromotion est actuellement la 1re année. Une nouvelle promotion n’apparaît ici qu’après son ajout par un administrateur.',
            style: TextStyle(
              fontSize: 10.8,
              height: 1.35,
              color: AppColors.inkFaint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        SizedBox(height: 20),
        _GradientPrimaryButton(
          label: 'Créer mon compte',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: _submitRegister,
        ),
        SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() {
            _showRegister = false;
            _error = null;
            _info = null;
          }),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.isDarkMode
                ? AppColors.brand
                : _loginGreenDark,
          ),
          child: Text('Déjà inscrit ? Se connecter'),
        ),
      ],
    );
  }

  InputDecoration _glassInputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(17),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.82), width: 1.2),
    );
    return InputDecoration(
      hintText: hint,
      labelText: null,
      prefixIcon: Icon(icon, color: AppColors.inkFaint, size: 21),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.paperAlt.withOpacity(0.70),
      hintStyle: TextStyle(
        color: AppColors.inkFaint,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide(color: _loginGreen, width: 1.5),
      ),
    );
  }

  Widget _gradeOption(MedicalGrade value, String label) {
    final selected = _regGrade == value;
    return GestureDetector(
      onTap: () => setState(() => _regGrade = value),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 170),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _loginGreen : Colors.white.withOpacity(0.62),
          border: Border.all(
            color: selected ? _loginGreen : Colors.white.withOpacity(0.92),
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 13, sigmaY: 13),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 22),
          decoration: BoxDecoration(
            color: (AppColors.isDarkMode ? AppColors.card : Colors.white)
                .withOpacity(0.72),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: (AppColors.isDarkMode ? AppColors.card : Colors.white)
                  .withOpacity(0.90),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.11),
                blurRadius: 30,
                offset: Offset(0, 14),
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
  final VoidCallback onPressed;

  const _GradientPrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.brandBright, _loginGreenDark],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _loginGreen.withOpacity(0.25),
                blurRadius: 14,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 10),
              Icon(icon, color: Colors.white, size: 21),
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
        Expanded(child: Divider(color: AppColors.inkFaint.withOpacity(0.45))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'ou',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.inkFaint.withOpacity(0.45))),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: background.withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.72)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
