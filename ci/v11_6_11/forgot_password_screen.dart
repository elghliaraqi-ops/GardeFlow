import 'dart:async';

import 'package:flutter/material.dart';

import '../services/supabase_backend_service.dart';
import '../widgets/brand_identity.dart';

const _recoveryGreen = Color(0xFF0F7C49);
const _recoveryGreenDark = Color(0xFF075B38);

class ForgotPasswordScreen extends StatefulWidget {
  final String initialPhone;
  const ForgotPasswordScreen({super.key, this.initialPhone = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _backend = SupabaseBackendService.instance;
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _codeStep = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _info;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = widget.initialPhone.trim();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  String _friendlyError(Object error) {
    final value = error.toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
    if (value.contains('SocketException') || value.contains('Failed host lookup')) {
      return 'Connexion Internet indisponible. Vérifiez votre réseau puis réessayez.';
    }
    if (value.contains('FunctionException') || value.contains('non-2xx')) {
      return 'Le service de récupération est momentanément indisponible.';
    }
    return value;
  }

  Future<void> _requestCode({bool resend = false}) async {
    if (_busy || (resend && _resendSeconds > 0)) return;
    if (_phoneCtrl.text.trim().isEmpty) {
      setState(() {
        _error = 'Saisissez votre numéro de téléphone.';
        _info = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await _backend.requestPasswordResetCode(_phoneCtrl.text);
      if (!mounted) return;
      setState(() {
        _codeStep = true;
        _info = resend
            ? 'Un nouveau code a été demandé.'
            : 'Si ce numéro correspond à un compte actif, un code à 6 chiffres a été envoyé sur un appareil GardeFlow déjà associé au compte.';
      });
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReset() async {
    if (_busy) return;
    final code = _codeCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Le code doit contenir exactement 6 chiffres.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Le nouveau mot de passe doit contenir au moins 8 caractères.');
      return;
    }
    if (password != _confirmCtrl.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await _backend.confirmPasswordReset(
        rawPhone: _phoneCtrl.text,
        code: code,
        newPassword: password,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changePhone() {
    _resendTimer?.cancel();
    setState(() {
      _codeStep = false;
      _resendSeconds = 0;
      _codeCtrl.clear();
      _passwordCtrl.clear();
      _confirmCtrl.clear();
      _error = null;
      _info = null;
    });
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _recoveryGreenDark),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD6E1DB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _recoveryGreen, width: 1.7),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F8F5),
        elevation: 0,
        title: const Text('Mot de passe oublié'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const GardeFlowBrandBlock(compact: true),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 10)),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _codeStep ? _buildCodeStep() : _buildPhoneStep(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F3EC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.security_rounded, color: _recoveryGreenDark, size: 21),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Le code expire après 10 minutes et le nombre de tentatives est limité. GardeFlow ne vous demandera jamais votre ancien mot de passe.',
                            style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF3E5C4B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() => Column(
        key: const ValueKey('phone-step'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_reset_rounded, size: 52, color: _recoveryGreen),
          const SizedBox(height: 12),
          const Text(
            'Récupérer votre compte',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _recoveryGreenDark),
          ),
          const SizedBox(height: 8),
          const Text(
            'Saisissez le numéro de téléphone utilisé pour votre compte GardeFlow.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFF68757A)),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _requestCode(),
            decoration: _decoration('Numéro de téléphone', Icons.phone_android_rounded),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _MessageBanner(text: _error!, error: true),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _requestCode(),
              style: FilledButton.styleFrom(
                backgroundColor: _recoveryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sms_rounded),
              label: Text(_busy ? 'Envoi…' : 'Recevoir mon code'),
            ),
          ),
        ],
      );

  Widget _buildCodeStep() => Column(
        key: const ValueKey('code-step'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.verified_user_rounded, size: 48, color: _recoveryGreen),
          const SizedBox(height: 10),
          const Text(
            'Saisissez votre code',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _recoveryGreenDark),
          ),
          const SizedBox(height: 6),
          Text(
            'Code envoyé pour ${_phoneCtrl.text.trim()}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF68757A)),
          ),
          TextButton(onPressed: _busy ? null : _changePhone, child: const Text('Modifier le numéro')),
          if (_info != null) ...[
            _MessageBanner(text: _info!, error: false),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            maxLength: 6,
            decoration: _decoration('Code à 6 chiffres', Icons.pin_rounded).copyWith(counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            decoration: _decoration(
              'Nouveau mot de passe',
              Icons.lock_outline_rounded,
              suffix: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _confirmReset(),
            decoration: _decoration(
              'Confirmer le mot de passe',
              Icons.lock_rounded,
              suffix: IconButton(
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _MessageBanner(text: _error!, error: true),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _confirmReset,
              style: FilledButton.styleFrom(
                backgroundColor: _recoveryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(_busy ? 'Modification…' : 'Changer mon mot de passe'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _busy || _resendSeconds > 0 ? null : () => _requestCode(resend: true),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_resendSeconds > 0 ? 'Renvoyer dans ${_resendSeconds}s' : 'Renvoyer un code'),
          ),
          const Text(
            'Si vous n’avez plus accès à aucun appareil déjà associé à votre compte, contactez un administrateur GardeFlow.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.35, color: Color(0xFF7A8589)),
          ),
        ],
      );
}

class _MessageBanner extends StatelessWidget {
  final String text;
  final bool error;
  const _MessageBanner({required this.text, required this.error});

  @override
  Widget build(BuildContext context) {
    final bg = error ? const Color(0xFFF9E1DD) : const Color(0xFFE0F1E6);
    final fg = error ? const Color(0xFF812E23) : const Color(0xFF245E3D);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(error ? Icons.error_outline_rounded : Icons.info_outline_rounded, color: fg, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
