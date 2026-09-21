import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../services/supabase_backend_service.dart';
import '../widgets/brand_identity.dart';

Color get _recoveryGreen => AppColors.brand;
Color get _recoveryGreenDark => AppColors.brandDark;

class ForgotPasswordScreen extends StatefulWidget {
  final String initialPhone;
  const ForgotPasswordScreen({super.key, this.initialPhone = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _backend = SupabaseBackendService.instance;
  final _phoneCtrl = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = widget.initialPhone.trim();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  String _friendlyError(Object error) {
    final value = error.toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
    if (value.contains('SocketException') || value.contains('Failed host lookup')) {
      return 'Connexion Internet indisponible. Vérifiez votre réseau puis réessayez.';
    }
    if (value.contains('FunctionException') || value.contains('non-2xx')) {
      return 'Le service est momentanément indisponible. Réessayez dans quelques instants.';
    }
    return value;
  }

  Future<void> _sendRequest() async {
    if (_busy) return;
    if (_phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Saisissez votre numéro de téléphone.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _backend.requestPasswordResetHelp(_phoneCtrl.text);
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _recoveryGreenDark),
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Color(0xFFD6E1DB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _recoveryGreen, width: 1.7),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('Mot de passe oublié'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GardeFlowBrandBlock(compact: true),
                  SizedBox(height: 22),
                  Container(
                    padding: EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 10)),
                      ],
                    ),
                    child: _sent ? _buildSuccess() : _buildRequest(),
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.admin_panel_settings_rounded, color: _recoveryGreenDark, size: 21),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aucun code n’est envoyé. L’administrateur reçoit seulement votre demande et pourra définir un nouveau mot de passe depuis les réglages GardeFlow.',
                            style: TextStyle(fontSize: 12.5, height: 1.4, color: Theme.of(context).colorScheme.onPrimaryContainer),
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

  Widget _buildRequest() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.lock_reset_rounded, size: 52, color: _recoveryGreen),
          SizedBox(height: 12),
          Text(
            'Demander un nouveau mot de passe',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _recoveryGreenDark),
          ),
          SizedBox(height: 8),
          Text(
            'Saisissez le numéro utilisé pour votre compte. Une notification sera envoyée à l’administrateur pour lui signaler votre demande.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.inkSoft),
          ),
          SizedBox(height: 22),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendRequest(),
            decoration: _decoration('Numéro de téléphone', Icons.phone_android_rounded),
          ),
          if (_error != null) ...[
            SizedBox(height: 12),
            _MessageBanner(text: _error!, error: true),
          ],
          SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _sendRequest,
              style: FilledButton.styleFrom(
                backgroundColor: _recoveryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(Icons.notifications_active_rounded),
              label: Text(_busy ? 'Envoi en cours…' : 'Notifier l’administrateur'),
            ),
          ),
        ],
      );

  Widget _buildSuccess() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mark_email_read_rounded, size: 54, color: _recoveryGreen),
          SizedBox(height: 12),
          Text(
            'Demande envoyée',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _recoveryGreenDark),
          ),
          SizedBox(height: 10),
          Text(
            'L’administrateur GardeFlow a été notifié. Il pourra définir un nouveau mot de passe depuis Réglages > Administration des comptes, puis vous le communiquer.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.inkSoft),
          ),
          SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(false),
            style: FilledButton.styleFrom(backgroundColor: _recoveryGreen),
            icon: Icon(Icons.arrow_back_rounded),
            label: Text('Retour à la connexion'),
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
    final bg = error ? Theme.of(context).colorScheme.errorContainer : AppColors.brandSoft;
    final fg = error ? Theme.of(context).colorScheme.onErrorContainer : Theme.of(context).colorScheme.onPrimaryContainer;
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
