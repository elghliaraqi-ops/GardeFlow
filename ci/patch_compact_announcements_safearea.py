from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def find_matching_paren(text: str, open_index: int) -> int:
    depth = 0
    i = open_index
    quote = None
    triple = False
    line_comment = False
    block_comment = False
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""

        if line_comment:
            if c == "\n":
                line_comment = False
            i += 1
            continue
        if block_comment:
            if c == "*" and n == "/":
                block_comment = False
                i += 2
                continue
            i += 1
            continue
        if quote is not None:
            if triple:
                if text.startswith(quote * 3, i):
                    quote = None
                    triple = False
                    i += 3
                    continue
                i += 1
                continue
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue

        if c == "/" and n == "/":
            line_comment = True
            i += 2
            continue
        if c == "/" and n == "*":
            block_comment = True
            i += 2
            continue
        if c in ("'", '"'):
            if text.startswith(c * 3, i):
                quote = c
                triple = True
                i += 3
                continue
            quote = c
            i += 1
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise RuntimeError("Unmatched parenthesis")


def wrap_scaffold_body_call(text: str, call_name: str) -> str:
    if "body: SafeArea(" in text:
        return text
    marker = f"body: {call_name}("
    body_index = text.find(marker)
    if body_index < 0:
        raise RuntimeError(f"Could not find {marker}")
    expr_start = body_index + len("body: ")
    open_index = text.find("(", expr_start)
    close_index = find_matching_paren(text, open_index)
    expr = text[expr_start : close_index + 1]
    return (
        text[:body_index]
        + "body: SafeArea(\n"
        + "        top: false,\n"
        + "        bottom: true,\n"
        + "        child: "
        + expr
        + ",\n"
        + "      )"
        + text[close_index + 1 :]
    )


def patch_home() -> None:
    path = "source/lib/screens/home_screen.dart"
    text = read(path)

    if "package:shared_preferences/shared_preferences.dart" not in text:
        text = text.replace(
            "import 'package:provider/provider.dart';\n",
            "import 'package:provider/provider.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n",
            1,
        )
    if "../services/supabase_backend_service.dart" not in text:
        text = text.replace(
            "import '../services/push_notification_service.dart';\n",
            "import '../services/push_notification_service.dart';\nimport '../services/supabase_backend_service.dart';\n",
            1,
        )

    if "class _AnnouncementsCompactButton" not in text:
        start_marker = (
            "        Padding(\n"
            "          padding: EdgeInsets.fromLTRB(12, 8, 12, 4),\n"
            "          child: Wrap("
        )
        month_marker = "        _MonthBar(appState: appState),"
        start = text.find(start_marker)
        if start < 0:
            raise RuntimeError("Planning header start marker not found")
        end = text.find(month_marker, start)
        if end < 0:
            raise RuntimeError("Planning month marker not found")

        new_header = """        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Row(
            children: [
              Expanded(
                flex: 10,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => OfficialPlanningScreen()),
                    ),
                    borderRadius: BorderRadius.circular(999),
                    child: Ink(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.line),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navy.withOpacity(0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 17,
                            color: AppColors.urg24h,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Planning officiel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (promotionLabel != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  flex: 11,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.brandBright,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.school_rounded,
                          size: 16,
                          color: AppColors.brandBright,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            promotionLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 10.8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              const _AnnouncementsCompactButton(),
            ],
          ),
        ),
"""
        text = text[:start] + new_header + text[end:]

        insert_marker = "class _PlanningShortcut extends StatelessWidget {"
        insert_at = text.find(insert_marker)
        if insert_at < 0:
            raise RuntimeError("Planning shortcut marker not found")

        widget_code = r'''class _AnnouncementsCompactButton extends StatefulWidget {
  const _AnnouncementsCompactButton();

  @override
  State<_AnnouncementsCompactButton> createState() =>
      _AnnouncementsCompactButtonState();
}

class _AnnouncementsCompactButtonState
    extends State<_AnnouncementsCompactButton> {
  StreamSubscription? _realtime;
  int _newCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    final backend = SupabaseBackendService.instance;
    if (backend.enabled) {
      _realtime = backend.client
          .from('public_announcements')
          .stream(primaryKey: ['id'])
          .listen((_) => _refresh(), onError: (_) {});
    }
  }

  @override
  void dispose() {
    _realtime?.cancel();
    super.dispose();
  }

  String? _seenKey() {
    final userId = context.read<AppState>().currentUser?.id;
    if (userId == null || userId.isEmpty) return null;
    return 'guardeflow_announcements_seen_$userId';
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final backend = SupabaseBackendService.instance;
    final key = _seenKey();
    if (!backend.enabled || key == null) {
      if (mounted && _newCount != 0) setState(() => _newCount = 0);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenRaw = prefs.getString(key);
      final seenAt = seenRaw == null ? null : DateTime.tryParse(seenRaw);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final rows = await backend.client
          .from('public_announcements')
          .select('created_at')
          .isFilter('closed_at', null)
          .gte('date_str', today)
          .order('created_at', ascending: false)
          .limit(150);
      var count = 0;
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final createdAt = DateTime.tryParse('${row['created_at']}');
        if (createdAt != null &&
            (seenAt == null || createdAt.isAfter(seenAt))) {
          count++;
        }
      }
      if (!mounted || count == _newCount) return;
      setState(() => _newCount = count);
    } catch (_) {
      // Le badge ne doit jamais bloquer l'ouverture du planning.
    }
  }

  Future<void> _openAnnouncements() async {
    final key = _seenKey();
    if (key != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, DateTime.now().toUtc().toIso8601String());
    }
    if (!mounted) return;
    setState(() => _newCount = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Annonces',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openAnnouncements,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.campaign_rounded,
                  size: 20,
                  color: AppColors.brandBright,
                ),
              ),
            ),
          ),
          if (_newCount > 0)
            Positioned(
              right: -5,
              top: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.paper, width: 2),
                ),
                child: Text(
                  _newCount > 99 ? '99+' : '$_newCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

'''
        text = text[:insert_at] + widget_code + text[insert_at:]

    write(path, text)


def patch_announcements() -> None:
    path = "source/lib/screens/announcements_screen.dart"
    text = read(path)
    old = "18 + MediaQuery.viewInsetsOf(context).bottom,"
    new = (
        "18 +\n"
        "                  MediaQuery.viewInsetsOf(context).bottom +\n"
        "                  MediaQuery.viewPaddingOf(context).bottom,"
    )
    if "MediaQuery.viewPaddingOf(context).bottom" not in text:
        if old not in text:
            raise RuntimeError("Announcement sheet bottom padding marker not found")
        text = text.replace(old, new, 1)
    write(path, text)


def patch_settings() -> None:
    path = "source/lib/screens/settings_screen.dart"
    text = read(path)
    text = wrap_scaffold_body_call(text, "ListView")
    write(path, text)


def patch_accounts() -> None:
    path = "source/lib/screens/admin_password_reset_screen.dart"
    text = read(path)
    text = wrap_scaffold_body_call(text, "Column")
    write(path, text)


patch_home()
patch_announcements()
patch_settings()
patch_accounts()
print("Compact announcements + safe-area patch applied")
