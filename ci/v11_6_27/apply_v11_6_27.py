from pathlib import Path

EXPECTED = "version: 11.6.26+186"
TARGET = "version: 11.6.27+187"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.27: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.27: class {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.27: opening brace missing for {class_name}")
    depth = 0
    end = None
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"V11.6.27: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

def replace_method_in_class(source: str, class_name: str, signature: str, replacement: str) -> str:
    class_marker = f"class {class_name} "
    class_start = source.find(class_marker)
    if class_start < 0:
        raise SystemExit(f"V11.6.27: class {class_name} not found")
    class_brace = source.find("{", class_start)
    depth = 0
    class_end = None
    for i in range(class_brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                class_end = i + 1
                break
    if class_end is None:
        raise SystemExit(f"V11.6.27: class end missing for {class_name}")

    method_start = source.find(signature, class_start, class_end)
    if method_start < 0:
        raise SystemExit(f"V11.6.27: method {signature} not found in {class_name}")
    brace = source.find("{", method_start, class_end)
    depth = 0
    method_end = None
    for i in range(brace, class_end):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                method_end = i + 1
                break
    if method_end is None:
        raise SystemExit(f"V11.6.27: method end missing in {class_name}")
    return source[:method_start] + replacement.rstrip() + source[method_end:]

# ---------------------------------------------------------------------------
# Home: replace the oversized Astreintes cards with a compact Junior/Senior
# segmented switch and embed the existing screens underneath.
# ---------------------------------------------------------------------------
home = Path("lib/screens/home_screen.dart")
h = home.read_text()

hub = r"""class _AstreintesHubView extends StatefulWidget {
  const _AstreintesHubView();

  @override
  State<_AstreintesHubView> createState() => _AstreintesHubViewState();
}

class _AstreintesHubViewState extends State<_AstreintesHubView> {
  bool _showSenior = true;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.paper,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: _AstreinteModeSwitch(
              showSenior: _showSenior,
              onChanged: (senior) {
                if (senior == _showSenior) return;
                setState(() => _showSenior = senior);
              },
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _showSenior ? 0 : 1,
              children: const [
                AstreinteScreen(embedded: true),
                JuniorOnCallScreen(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AstreinteModeSwitch extends StatelessWidget {
  final bool showSenior;
  final ValueChanged<bool> onChanged;

  const _AstreinteModeSwitch({
    required this.showSenior,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AstreinteModeButton(
              label: 'Astreinte Senior',
              icon: Icons.photo_library_rounded,
              selected: showSenior,
              onTap: () => onChanged(true),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: _AstreinteModeButton(
              label: 'Astreinte Junior',
              icon: Icons.calendar_view_week_rounded,
              selected: !showSenior,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _AstreinteModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AstreinteModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.brand.withOpacity(0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
"""

h = replace_class(h, "_AstreintesHubView", hub)
home.write_text(h)

# ---------------------------------------------------------------------------
# Senior astreinte: add an embedded mode. No duplicated data or new backend:
# same gallery, filters, zoom, admin upload/delete logic.
# ---------------------------------------------------------------------------
senior = Path("lib/screens/astreinte_screen.dart")
s = senior.read_text()

old_widget = """class AstreinteScreen extends StatefulWidget {
  const AstreinteScreen({super.key});

  @override
  State<AstreinteScreen> createState() => _AstreinteScreenState();
}"""
new_widget = """class AstreinteScreen extends StatefulWidget {
  final bool embedded;

  const AstreinteScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<AstreinteScreen> createState() => _AstreinteScreenState();
}"""
if old_widget not in s:
    raise SystemExit("V11.6.27: AstreinteScreen constructor anchor missing")
s = s.replace(old_widget, new_widget, 1)

senior_build = r"""  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    final isAdmin = user?.role == UserRole.admin;
    final hospital = _selectedHospital ??
        (user != null && kHospitals.contains(user.hospital)
            ? user.hospital
            : kHospitals.first);

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = _ErrorState(message: _error!, onRetry: _load);
    } else if (_photos.isEmpty && !isAdmin) {
      content = _EmptyHospitalGallery(hospital: hospital);
    } else {
      content = RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 600
                    ? 3
                    : 2;
            return GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                widget.embedded ? 28 : 100,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: AppSpace.md,
                crossAxisSpacing: AppSpace.md,
                childAspectRatio: 0.78,
              ),
              itemCount: _photos.length + (isAdmin ? 1 : 0),
              itemBuilder: (context, i) {
                if (isAdmin && i == 0) {
                  return _AdminAddTile(
                    uploading: _uploading,
                    hospital: hospital,
                    onTap: _pickImage,
                  );
                }
                final photo = _photos[i - (isAdmin ? 1 : 0)];
                return _AstreintePhotoCard(
                  resource: photo,
                  imageFuture: _bytesFor(photo),
                  canDelete: isAdmin,
                  onTap: () => _openPhoto(photo),
                  onDelete: () => _delete(photo),
                );
              },
            );
          },
        ),
      );
    }

    final body = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Photos par établissement',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppColors.brand,
                ),
                if (isAdmin)
                  IconButton(
                    tooltip:
                        'Ajouter une photo pour ${hospitalDisplayName(hospital)}',
                    onPressed: _uploading ? null : _pickImage,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_rounded),
                    color: AppColors.brand,
                  ),
              ],
            ),
          ),
        _HospitalAstreinteHeader(
          hospital: hospital,
          isAdmin: isAdmin,
          onSelectHospital: _selectHospital,
        ),
        Expanded(child: content),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.paper,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const GardeFlowTitle('Médecins Séniors de Garde / Astreinte'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (isAdmin)
            IconButton(
              tooltip:
                  'Ajouter une photo pour ${hospitalDisplayName(hospital)}',
              onPressed: _uploading ? null : _pickImage,
              icon: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_rounded),
            ),
        ],
      ),
      body: body,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.sm,
            AppSpace.lg,
            AppSpace.md,
          ),
          child: Text(
            isAdmin
                ? 'Vous gérez actuellement les photos de ${hospitalDisplayName(hospital)}. Changez d’établissement en haut pour publier dans une autre galerie.'
                : 'Tous les médecins peuvent consulter les photos des trois hôpitaux. Sélectionnez l’établissement en haut.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.inkSoft,
                  height: 1.4,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
"""
s = replace_method_in_class(
    s,
    "_AstreinteScreenState",
    "  @override\n  Widget build(BuildContext context)",
    senior_build,
)
senior.write_text(s)

# ---------------------------------------------------------------------------
# Junior astreinte: same existing roster/calendar logic, embedded directly.
# ---------------------------------------------------------------------------
junior = Path("lib/screens/junior_oncall_screen.dart")
j = junior.read_text()

old_junior_widget = """class JuniorOnCallScreen extends StatefulWidget {
  const JuniorOnCallScreen({super.key});

  @override
  State<JuniorOnCallScreen> createState() => _JuniorOnCallScreenState();
}"""
new_junior_widget = """class JuniorOnCallScreen extends StatefulWidget {
  final bool embedded;

  const JuniorOnCallScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<JuniorOnCallScreen> createState() => _JuniorOnCallScreenState();
}"""
if old_junior_widget not in j:
    raise SystemExit("V11.6.27: JuniorOnCallScreen constructor anchor missing")
j = j.replace(old_junior_widget, new_junior_widget, 1)

junior_build = r"""  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 10, 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Calendrier des gardes',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _loading ? null : _goToCurrentWeek,
                  icon: const Icon(Icons.today_rounded, size: 17),
                  label: const Text('Aujourd’hui'),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  color: AppColors.brand,
                ),
              ],
            ),
          ),
        _WeekSelector(
          start: _weekStart,
          end: _weekEnd,
          onPrevious: _loading ? null : () => _changeWeek(-1),
          onNext: _loading ? null : () => _changeWeek(1),
        ),
        _DaySelector(
          weekStart: _weekStart,
          selectedIndex: _selectedDayIndex,
          onSelected: _selectDay,
        ),
        _HospitalFilter(
          selectedHospital: _activeHospital,
          onChanged: _selectHospital,
        ),
        _ServiceFilter(
          services: _availableServices,
          value: _selectedService,
          allValue: _allServices,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedService = value);
          },
        ),
        Expanded(child: _buildBody()),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.paper,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const GardeFlowTitle('Astreintes Juniors'),
        actions: [
          IconButton(
            tooltip: 'Aujourd’hui',
            onPressed: _loading ? null : _goToCurrentWeek,
            icon: const Icon(Icons.today_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: body,
    );
  }
"""
j = replace_method_in_class(
    j,
    "_JuniorOnCallScreenState",
    "  @override\n  Widget build(BuildContext context)",
    junior_build,
)
junior.write_text(j)

print("GardeFlow V11.6.27: Astreintes Junior/Senior en bascule avec contenu intégré")
