import 'package:flutter/material.dart';

/// Le contrôleur appartient à la route jusqu'à son démontage effectif, y compris
/// pendant l'animation de fermeture et le retrait du clavier Android.
class AdminReasonDialog extends StatefulWidget {
  final String title;
  final String subject;
  final String explanation;
  final String actionLabel;
  const AdminReasonDialog({super.key, required this.title, required this.subject,
    required this.explanation, required this.actionLabel});

  @override
  State<AdminReasonDialog> createState() => _AdminReasonDialogState();
}

class _AdminReasonDialogState extends State<AdminReasonDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _closing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([String? reason]) {
    if (_closing) return;
    _closing = true;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subject, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(widget.explanation),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('admin-reason'),
              controller: _controller,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              scrollPadding: const EdgeInsets.all(24),
              decoration: const InputDecoration(
                labelText: 'Motif obligatoire',
                hintText: 'Ex. correction du planning',
                errorMaxLines: 2,
              ),
              validator: (value) => (value?.trim().length ?? 0) < 3
                  ? 'Saisissez au moins 3 caractères.' : null,
            ),
          ],
        ),
      ),
    ),
    actionsOverflowButtonSpacing: 4,
    actions: [
      TextButton(onPressed: () => _close(), child: const Text('Annuler')),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) _close(_controller.text.trim());
        },
        child: Text(widget.actionLabel),
      ),
    ],
  );
}
