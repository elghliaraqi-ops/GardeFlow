from pathlib import Path
import re

# Home -----------------------------------------------------------------------
path = Path('source/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')

old = """              onNotifications: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NotificationsScreen()),
              ),
              onAccount: () => Navigator.push(
"""
new = """              onNotifications: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NotificationsScreen()),
              ),
              onDirectory: _tab == 3
                  ? () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DirectoryScreen()),
                    )
                  : null,
              onAccount: () => Navigator.push(
"""
if old in text:
    text = text.replace(old, new, 1)

old = """  final VoidCallback onNotifications;
  final VoidCallback onAccount;

  const _GlobalTopBar({
    required this.title,
    required this.appState,
    required this.onNotifications,
    required this.onAccount,
  });
"""
new = """  final VoidCallback onNotifications;
  final VoidCallback? onDirectory;
  final VoidCallback onAccount;

  const _GlobalTopBar({
    required this.title,
    required this.appState,
    required this.onNotifications,
    this.onDirectory,
    required this.onAccount,
  });
"""
if old in text:
    text = text.replace(old, new, 1)

bell_anchor = """          Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: AppColors.card,
"""
directory_button = """          if (onDirectory != null) ...[
            Tooltip(
              message: 'Annuaire',
              child: Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  onTap: onDirectory,
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.contacts_rounded,
                      color: AppColors.brand,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 9),
          ],
"""
if directory_button not in text:
    if bell_anchor not in text:
        raise SystemExit('Global top-bar bell anchor not found')
    text = text.replace(bell_anchor, directory_button + bell_anchor, 1)

pattern = re.compile(
    r"class _AstreintesHubViewState extends State<_AstreintesHubView> \{.*?\n\}\n\nclass _AstreinteModeSwitch",
    re.S,
)
replacement = """class _AstreintesHubViewState extends State<_AstreintesHubView> {
  bool _showSenior = false;

  Widget _scrollingModeSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: _AstreinteModeSwitch(
        showSenior: _showSenior,
        onChanged: (senior) {
          if (senior == _showSenior) return;
          setState(() => _showSenior = senior);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.paper,
      child: IndexedStack(
        index: _showSenior ? 0 : 1,
        children: [
          SeniorOnCallScreen(
            embedded: true,
            embeddedHeader: _scrollingModeSwitch(),
          ),
          JuniorOnCallScreen(
            embedded: true,
            embeddedHeader: _scrollingModeSwitch(),
          ),
        ],
      ),
    );
  }
}

class _AstreinteModeSwitch"""
if 'embeddedHeader: _scrollingModeSwitch()' not in text:
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit('Astreintes hub block not found')

path.write_text(text, encoding='utf-8')

# Juniors --------------------------------------------------------------------
path = Path('source/lib/screens/junior_oncall_screen.dart')
text = path.read_text(encoding='utf-8')
text = text.replace(
    """class JuniorOnCallScreen extends StatefulWidget {
  final bool embedded;

  const JuniorOnCallScreen({super.key, this.embedded = false});
""",
    """class JuniorOnCallScreen extends StatefulWidget {
  final bool embedded;
  final Widget? embeddedHeader;

  const JuniorOnCallScreen({
    super.key,
    this.embedded = false,
    this.embeddedHeader,
  });
""",
    1,
)

old_build = re.compile(
    r"  @override\n  Widget build\(BuildContext context\) \{\n    final theme = Theme\.of\(context\);.*?\n  \}\n\n  Widget _buildBody\(\) \{",
    re.S,
)
new_build = '''  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.embedded) {
      return ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 44),
            children: [
              if (widget.embeddedHeader != null) widget.embeddedHeader!,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
                child: Row(
                  children: [
                    Expanded(
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
                      tooltip: 'Calendrier du mois',
                      visualDensity: VisualDensity.compact,
                      onPressed: _loading ? null : _openMonthCalendar,
                      icon: const Icon(Icons.calendar_month_rounded, size: 20),
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
              _buildEmbeddedContent(),
            ],
          ),
        ),
      );
    }

    final body = Column(
      children: [
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: GardeFlowTitle('Astreintes Juniors'),
        actions: [
          IconButton(
            tooltip: 'Calendrier du mois',
            onPressed: _loading ? null : _openMonthCalendar,
            icon: const Icon(Icons.calendar_month_rounded),
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

  Widget _buildEmbeddedContent() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 54),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: AppColors.danger,
            ),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }

    final rows = _visibleRows;
    if (rows.isEmpty) {
      final day = DateFormat('EEEE d MMMM', 'fr_FR').format(_selectedDay);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 46, 24, 22),
        child: Column(
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 50,
              color: AppColors.inkFaint,
            ),
            const SizedBox(height: 14),
            Text(
              'Aucune garde ou astreinte Junior $day\\nà ${_juniorHospitalLabel(_activeHospital)}${_selectedService == _allServices ? '' : ' · $_selectedService'}.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.inkSoft,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    final groups = _groupRowsByServiceForDay(rows);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        0,
      ),
      child: Column(
        children: [for (final group in groups) _ServiceDayCard(group: group)],
      ),
    );
  }

  Widget _buildBody() {'''
if 'Widget _buildEmbeddedContent()' not in text:
    text, count = old_build.subn(new_build, text, count=1)
    if count != 1:
        raise SystemExit('Junior build block not found')
path.write_text(text, encoding='utf-8')

# Seniors --------------------------------------------------------------------
path = Path('source/lib/screens/senior_oncall_screen.dart')
text = path.read_text(encoding='utf-8')
text = text.replace(
    """class SeniorOnCallScreen extends StatefulWidget {
  final bool embedded;

  const SeniorOnCallScreen({super.key, this.embedded = false});
""",
    """class SeniorOnCallScreen extends StatefulWidget {
  final bool embedded;
  final Widget? embeddedHeader;

  const SeniorOnCallScreen({
    super.key,
    this.embedded = false,
    this.embeddedHeader,
  });
""",
    1,
)

old_build = re.compile(
    r"  @override\n  Widget build\(BuildContext context\) \{\n    final body = Column\(.*?\n  \}\n\n  Widget _buildBody\(\) \{",
    re.S,
)
new_build = '''  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.paper,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 44),
            children: [
              if (widget.embeddedHeader != null) widget.embeddedHeader!,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Astreinte Sénior',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Photos des astreintes',
                      onPressed: _openPhotos,
                      icon: const Icon(Icons.photo_library_rounded, size: 20),
                      color: AppColors.brand,
                    ),
                    IconButton(
                      tooltip: 'Calendrier du mois',
                      onPressed: _loading ? null : _openMonthCalendar,
                      icon: const Icon(Icons.calendar_month_rounded, size: 20),
                      color: AppColors.brand,
                    ),
                    IconButton(
                      tooltip: 'Actualiser',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      color: AppColors.brand,
                    ),
                  ],
                ),
              ),
              _SeniorWeekSelector(
                start: _weekStart,
                end: _weekEnd,
                onPrevious: _loading ? null : () => _changeWeek(-1),
                onNext: _loading ? null : () => _changeWeek(1),
              ),
              _SeniorDaySelector(
                weekStart: _weekStart,
                selectedIndex: _selectedDayIndex,
                onSelected: (i) => setState(() => _selectedDayIndex = i),
              ),
              _SeniorHospitalFilter(
                selectedHospital: _activeHospital,
                onChanged: _selectHospital,
              ),
              _SeniorServiceFilter(
                services: _availableServices,
                value: _selectedService,
                onChanged: (value) {
                  if (value != null) setState(() => _selectedService = value);
                },
              ),
              const SizedBox(height: 4),
              _buildEmbeddedContent(),
            ],
          ),
        ),
      );
    }

    final body = Column(
      children: [
        _SeniorWeekSelector(
          start: _weekStart,
          end: _weekEnd,
          onPrevious: _loading ? null : () => _changeWeek(-1),
          onNext: _loading ? null : () => _changeWeek(1),
        ),
        _SeniorDaySelector(
          weekStart: _weekStart,
          selectedIndex: _selectedDayIndex,
          onSelected: (i) => setState(() => _selectedDayIndex = i),
        ),
        _SeniorHospitalFilter(
          selectedHospital: _activeHospital,
          onChanged: _selectHospital,
        ),
        _SeniorServiceFilter(
          services: _availableServices,
          value: _selectedService,
          onChanged: (value) {
            if (value != null) setState(() => _selectedService = value);
          },
        ),
        const SizedBox(height: 4),
        Expanded(child: _buildBody()),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Astreintes Séniors'),
        actions: [
          IconButton(
            tooltip: 'Photos',
            onPressed: _openPhotos,
            icon: const Icon(Icons.photo_library_rounded),
          ),
          IconButton(
            tooltip: 'Calendrier du mois',
            onPressed: _loading ? null : _openMonthCalendar,
            icon: const Icon(Icons.calendar_month_rounded),
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

  Widget _buildEmbeddedContent() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 54),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: AppColors.danger,
            ),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }

    final rows = _visibleRows;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 46, 24, 22),
        child: Column(
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 50,
              color: AppColors.inkFaint,
            ),
            const SizedBox(height: 14),
            Text(
              'Aucune astreinte sénior le ${DateFormat('d MMMM yyyy', 'fr_FR').format(_selectedDay)}.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft),
            ),
          ],
        ),
      );
    }

    final grouped = <String, List<_SeniorOnCallRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.service, () => []).add(row);
    }
    final services = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final isAdmin =
        context.watch<AppState>().currentUser?.role == UserRole.admin;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        0,
      ),
      child: Column(
        children: [
          for (final service in services)
            _SeniorServiceCard(
              service: service,
              rows: grouped[service]!,
              canAddContact: isAdmin,
              savingContacts: _savingContacts,
              onAddContact: _addContact,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {'''
if 'Widget _buildEmbeddedContent()' not in text:
    text, count = old_build.subn(new_build, text, count=1)
    if count != 1:
        raise SystemExit('Senior build block not found')
path.write_text(text, encoding='utf-8')
