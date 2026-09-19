from pathlib import Path

backend = Path("lib/services/supabase_backend_service.dart")
b = backend.read_text()
insert_at = b.rfind("\n}")
if insert_at < 0:
    raise SystemExit("V11.6.38 backend class end missing")

method = """
  Future<int> clearAudit() async {
    final result = await client.rpc('admin_clear_audit_log');
    if (result is num) return result.toInt();
    return int.tryParse(result?.toString() ?? '') ?? 0;
  }
"""
b = b[:insert_at] + method + b[insert_at:]
backend.write_text(b)

audit = Path("lib/screens/audit_screen.dart")
a = audit.read_text()

if "  String _filter = 'all';" not in a:
    raise SystemExit("V11.6.38 audit filter anchor missing")
a = a.replace(
    "  String _filter = 'all';",
    "  String _filter = 'all';\n  bool _clearing = false;",
    1,
)

refresh = """  void _refresh() {
    setState(() {
      _future = SupabaseBackendService.instance.fetchAudit();
    });
  }"""

clear_method = r"""  void _refresh() {
    setState(() {
      _future = SupabaseBackendService.instance.fetchAudit();
    });
  }

  Future<void> _clearAudit() async {
    if (_clearing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nettoyer l’historique ?'),
        content: const Text(
          'Toutes les entrées du journal administratif seront supprimées définitivement. '
          'Cette action est réservée aux administrateurs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text('Nettoyer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      final count = await SupabaseBackendService.instance.clearAudit();
      if (!mounted) return;
      setState(() {
        _future = SupabaseBackendService.instance.fetchAudit();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Historique déjà vide.'
                : '$count entrée${count > 1 ? 's' : ''} supprimée${count > 1 ? 's' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nettoyage impossible : $e')),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }"""

if refresh not in a:
    raise SystemExit("V11.6.38 audit refresh anchor missing")
a = a.replace(refresh, clear_method, 1)

old_actions = """        actions: [
          SoftIconButton(
            icon: Icons.refresh_rounded,
            onTap: _refresh,
            tooltip: 'Actualiser',
          ),
          const SizedBox(width: 6),
        ],"""

new_actions = """        actions: [
          SoftIconButton(
            icon: Icons.delete_sweep_rounded,
            onTap: _clearing ? () {} : _clearAudit,
            tooltip: 'Nettoyer l’historique',
          ),
          const SizedBox(width: 4),
          SoftIconButton(
            icon: Icons.refresh_rounded,
            onTap: _refresh,
            tooltip: 'Actualiser',
          ),
          const SizedBox(width: 6),
        ],"""

if old_actions not in a:
    raise SystemExit("V11.6.38 audit actions anchor missing")
a = a.replace(old_actions, new_actions, 1)

audit.write_text(a)
print("V11.6.38 part 5 applied")
