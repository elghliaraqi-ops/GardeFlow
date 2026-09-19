from pathlib import Path

EXPECTED = "version: 11.6.38+198"
TARGET = "version: 11.6.39+199"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.39: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.39: {class_name} not found")
    brace = source.find("{", start)
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
        raise SystemExit(f"V11.6.39: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

def replace_method_in_class(source: str, class_name: str, signature: str, replacement: str) -> str:
    class_marker = f"class {class_name} "
    class_start = source.find(class_marker)
    if class_start < 0:
        raise SystemExit(f"V11.6.39: {class_name} not found")
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
        raise SystemExit(f"V11.6.39: end missing for {class_name}")
    method_start = source.find(signature, class_start, class_end)
    if method_start < 0:
        raise SystemExit(f"V11.6.39: method missing in {class_name}")
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
        raise SystemExit(f"V11.6.39: method end missing in {class_name}")
    return source[:method_start] + replacement.rstrip() + source[method_end:]

home = Path("lib/screens/home_screen.dart")
h = home.read_text()

hub = r"""class _AstreintesHubView extends StatefulWidget {
  const _AstreintesHubView();

  @override
  State<_AstreintesHubView> createState() => _AstreintesHubViewState();
}

class _AstreintesHubViewState extends State<_AstreintesHubView> {
  bool _showSenior = false;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.paper,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
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
}"""

h = replace_class(h, "_AstreintesHubView", hub)

switch_cls = r"""class _AstreinteModeSwitch extends StatelessWidget {
  final bool showSenior;
  final ValueChanged<bool> onChanged;

  const _AstreinteModeSwitch({
    required this.showSenior,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AstreinteModeButton(
              label: 'Juniors',
              icon: Icons.calendar_view_week_rounded,
              selected: !showSenior,
              onTap: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: _AstreinteModeButton(
              label: 'Séniors',
              icon: Icons.photo_library_rounded,
              selected: showSenior,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}"""

h = replace_class(h, "_AstreinteModeSwitch", switch_cls)
home.write_text(h)

junior = Path("lib/screens/junior_oncall_screen.dart")
j = junior.read_text()

junior_build = r"""  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Astreinte Junior',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Aujourd’hui',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading ? null : _goToCurrentWeek,
                  icon: const Icon(Icons.today_rounded, size: 20),
                  color: AppColors.brand,
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
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
        const SizedBox(height: 4),
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
  }"""

j = replace_method_in_class(
    j,
    "_JuniorOnCallScreenState",
    "  @override
  Widget build(BuildContext context)",
    junior_build,
)

week = r"""class _WeekSelector extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _WeekSelector({
    required this.start,
    required this.end,
    this.onPrevious,
    this.onNext,
  });

  String _label() {
    final startDay = DateFormat('d', 'fr_FR').format(start);
    final endDay = DateFormat('d', 'fr_FR').format(end);
    final month = DateFormat('MMMM', 'fr_FR').format(end);
    if (start.month == end.month) {
      return '$startDay – $endDay $month';
    }
    final startMonth = DateFormat('MMM', 'fr_FR').format(start);
    final endMonth = DateFormat('MMM', 'fr_FR').format(end);
    return '$startDay $startMonth – $endDay $endMonth';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 7),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onPrevious,
              tooltip: 'Semaine précédente',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                _label(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              onPressed: onNext,
              tooltip: 'Semaine suivante',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}"""
j = replace_class(j, "_WeekSelector", week)

days = r"""class _DaySelector extends StatelessWidget {
  final DateTime weekStart;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _DaySelector({
    required this.weekStart,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) => _DayChip(
          date: weekStart.add(Duration(days: index)),
          selected: index == selectedIndex,
          onTap: () => onSelected(index),
        ),
      ),
    );
  }
}"""
j = replace_class(j, "_DaySelector", days)

day_chip = r"""class _DayChip extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final day = DateFormat('EEE', 'fr_FR').format(date).replaceAll('.', '');
    final label = day.isEmpty
        ? ''
        : day[0].toUpperCase() + day.substring(1);

    return SizedBox(
      width: 62,
      child: Material(
        color: selected ? AppColors.brand : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.brand : AppColors.line,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: selected ? Colors.white : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}"""
j = replace_class(j, "_DayChip", day_chip)

hospital = r"""class _HospitalFilter extends StatelessWidget {
  final String selectedHospital;
  final ValueChanged<String> onChanged;

  const _HospitalFilter({
    required this.selectedHospital,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        itemCount: kHospitals.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final hospital = kHospitals[index];
          final selected = selectedHospital == hospital;
          return ChoiceChip(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            label: Text(
              _juniorHospitalLabel(hospital),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.brandDark : AppColors.inkSoft,
              ),
            ),
            selected: selected,
            onSelected: (_) => onChanged(hospital),
          );
        },
      ),
    );
  }
}"""
j = replace_class(j, "_HospitalFilter", hospital)

service = r"""class _ServiceFilter extends StatelessWidget {
  final List<String> services;
  final String value;
  final String allValue;
  final ValueChanged<String?> onChanged;

  const _ServiceFilter({
    required this.services,
    required this.value,
    required this.allValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 2),
      child: SizedBox(
        height: 48,
        child: DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.filter_alt_outlined,
              color: AppColors.brand,
              size: 19,
            ),
            labelText: 'Service',
            labelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            filled: true,
            fillColor: AppColors.card,
          ),
          dropdownColor: Colors.white,
          items: [
            DropdownMenuItem(
              value: allValue,
              child: const Text(
                'Tous les services',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final service in services)
              DropdownMenuItem(
                value: service,
                child: Text(service, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}"""
j = replace_class(j, "_ServiceFilter", service)

service_card = r"""class _ServiceDayCard extends StatelessWidget {
  final _ServiceDayGroup group;

  const _ServiceDayCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final total = group.rows.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadow.low,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(15, 12, 13, 11),
            decoration: const BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.medical_services_rounded,
                  size: 19,
                  color: AppColors.brand,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.service,
                    style: const TextStyle(
                      color: AppColors.brandDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '$total',
                  style: const TextStyle(
                    color: AppColors.brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < group.rows.length; i++) ...[
            _JuniorDutyLine(row: group.rows[i]),
            if (i != group.rows.length - 1)
              const Divider(height: 1, indent: 15, endIndent: 15),
          ],
        ],
      ),
    );
  }
}"""
j = replace_class(j, "_ServiceDayCard", service_card)

junior.write_text(j)

print("GardeFlow V11.6.39: Astreinte Junior aérée, jours scrollables et contenu lisible")
