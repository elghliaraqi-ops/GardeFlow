import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/hospitals.dart';
import '../models/app_user.dart';
import '../models/planning_entry.dart';
import '../models/shift_type.dart';
import '../services/supabase_backend_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// Astreintes Juniors : lecture par jour, hôpital et service.
///
/// V11.6.14 : un seul établissement est affiché à la fois, la semaine est
/// navigable jour par jour et une liste permet de filtrer les services.
class JuniorOnCallScreen extends StatefulWidget {
  final bool embedded;

  const JuniorOnCallScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<JuniorOnCallScreen> createState() => _JuniorOnCallScreenState();
}

class _JuniorOnCallScreenState extends State<JuniorOnCallScreen> {
  static const _allServices = '__all_services__';

  late DateTime _weekStart;
  late int _selectedDayIndex;
  bool _loading = true;
  bool _hospitalInitialized = false;
  String? _error;
  String? _selectedHospital;
  String _selectedService = _allServices;
  List<_JuniorOnCallRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = _startOfWeek(now);
    _selectedDayIndex = now.weekday - DateTime.monday;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hospitalInitialized) return;
    _hospitalInitialized = true;
    final user = context.read<AppState>().currentUser;
    _selectedHospital = user != null && kHospitals.contains(user.hospital)
        ? user.hospital
        : kHospitals.first;
  }

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));
  DateTime get _selectedDay => _weekStart.add(Duration(days: _selectedDayIndex));
  String get _selectedDateStr => DateFormat('yyyy-MM-dd').format(_selectedDay);
  String get _activeHospital => _selectedHospital ?? kHospitals.first;

  static DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - DateTime.monday));
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final appState = context.read<AppState>();
      final List<_JuniorOnCallRow> rows;
      if (appState.backendEnabled) {
        final data = await SupabaseBackendService.instance.fetchJuniorOnCallRoster(
          from: _weekStart,
          to: _weekEnd,
        );
        rows = data.map(_JuniorOnCallRow.fromRpc).toList()..sort(_compareRows);
      } else {
        rows = _buildLocalRows(appState)..sort(_compareRows);
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _normalizeServiceFilter();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _error = 'Impossible de charger les Juniors d’astreinte.\n$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_JuniorOnCallRow> _buildLocalRows(AppState appState) {
    final usersById = <String, AppUser>{for (final user in appState.users) user.id: user};
    final usersByPhone = <String, AppUser>{for (final user in appState.users) user.phone: user};
    final result = <_JuniorOnCallRow>[];
    final start = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
    final endExclusive = _weekEnd.add(const Duration(days: 1));

    for (final PlanningEntry entry in appState.planning) {
      final isService = entry.shiftId.startsWith('service-');
      final isUrgences = entry.shiftId.startsWith('urg-');
      if (!isService && !isUrgences) continue;
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null || date.isBefore(start) || !date.isBefore(endExclusive)) continue;

      // Les gardes de service restent limitées aux calendriers validés.
      // Les gardes aux urgences proviennent du planning officiel PDF :
      // elles doivent être visibles dès leur import, même avant la validation
      // individuelle/automatique du mois.
      if (isService && !appState.isPlanningEntryApproved(entry)) continue;

      final user = usersById[entry.ownerId] ?? usersByPhone[entry.ownerPhone];
      if (user == null || user.grade != MedicalGrade.junior || user.accountStatus != AccountStatus.active) continue;

      result.add(_JuniorOnCallRow(
        dateStr: entry.dateStr,
        shiftId: entry.shiftId,
        ownerName: entry.ownerName,
        ownerPhone: user.phone,
        service: isUrgences ? 'Urgences' : user.service,
        hospital: user.hospital,
      ));
    }
    return result;
  }

  static int _compareRows(_JuniorOnCallRow a, _JuniorOnCallRow b) {
    var c = a.dateStr.compareTo(b.dateStr);
    if (c != 0) return c;
    c = _hospitalRank(a.hospital).compareTo(_hospitalRank(b.hospital));
    if (c != 0) return c;
    c = a.service.toLowerCase().compareTo(b.service.toLowerCase());
    if (c != 0) return c;
    c = _shiftRank(a.shiftId).compareTo(_shiftRank(b.shiftId));
    if (c != 0) return c;
    return a.ownerName.toLowerCase().compareTo(b.ownerName.toLowerCase());
  }

  static int _hospitalRank(String hospital) {
    final index = kHospitals.indexOf(hospital);
    return index < 0 ? 999 : index;
  }

  static int _shiftRank(String shiftId) {
    switch (shiftId) {
      case 'urg-jour':
        return 0;
      case 'urg-24h':
        return 1;
      case 'urg-nuit':
        return 2;
      case 'service-jour':
        return 3;
      case 'service-24h':
        return 4;
      case 'service-nuit':
        return 5;
      default:
        return 99;
    }
  }

  void _changeWeek(int delta) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * delta)));
    _load();
  }

  void _goToCurrentWeek() {
    final now = DateTime.now();
    final current = _startOfWeek(now);
    if (_sameDay(current, _weekStart) && _selectedDayIndex == now.weekday - DateTime.monday) return;
    setState(() {
      _weekStart = current;
      _selectedDayIndex = now.weekday - DateTime.monday;
    });
    _load();
  }

  void _selectHospital(String hospital) {
    if (!kHospitals.contains(hospital) || hospital == _selectedHospital) return;
    setState(() {
      _selectedHospital = hospital;
      _normalizeServiceFilter();
    });
  }

  void _selectDay(int index) {
    if (index < 0 || index > 6 || index == _selectedDayIndex) return;
    setState(() => _selectedDayIndex = index);
  }

  List<String> get _availableServices {
    final values = _rows
        .where((row) => row.hospital == _activeHospital)
        .map((row) => row.service.trim())
        .where((service) => service.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  void _normalizeServiceFilter() {
    if (_selectedService == _allServices) return;
    final available = _rows
        .where((row) => row.hospital == _activeHospital)
        .map((row) => row.service)
        .toSet();
    if (!available.contains(_selectedService)) _selectedService = _allServices;
  }

  List<_JuniorOnCallRow> get _visibleRows {
    return _rows.where((row) {
      if (row.hospital != _activeHospital) return false;
      if (row.dateStr != _selectedDateStr) return false;
      if (_selectedService != _allServices && row.service != _selectedService) return false;
      return true;
    }).toList(growable: false);
  }

  Future<void> _openMonthCalendar() async {
    final currentDate = _weekStart.add(
      Duration(days: _selectedDayIndex),
    );

    final picked = await showDatePicker(
      context: context,
      locale: const Locale('fr', 'FR'),
      initialDate: currentDate,
      firstDate: DateTime(currentDate.year - 1, 1, 1),
      lastDate: DateTime(currentDate.year + 2, 12, 31),
      initialDatePickerMode: DatePickerMode.day,
      helpText: 'Calendrier des astreintes juniors',
      cancelText: 'Fermer',
      confirmText: 'Afficher',
    );

    if (picked == null || !mounted) return;

    final monday = picked.subtract(
      Duration(days: picked.weekday - DateTime.monday),
    );

    setState(() {
      _weekStart = DateTime(monday.year, monday.month, monday.day);
      _selectedDayIndex = picked.weekday - DateTime.monday;
    });

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 10, 2),
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
                  icon: Icon(Icons.calendar_month_rounded, size: 20),
                  color: AppColors.brand,
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading ? null : _load,
                  icon: Icon(Icons.refresh_rounded, size: 20),
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
        color: theme.scaffoldBackgroundColor,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: GardeFlowTitle('Astreintes Juniors'),
        actions: [
          IconButton(
            tooltip: 'Calendrier du mois',
            onPressed: _loading ? null : _openMonthCalendar,
            icon: Icon(Icons.calendar_month_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _load,
            icon: Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _JuniorErrorState(message: _error!, onRetry: _load);

    final rows = _visibleRows;
    if (rows.isEmpty) {
      final day = DateFormat('EEEE d MMMM', 'fr_FR').format(_selectedDay);
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: AppSpace.xl),
          children: [
            SizedBox(height: 78),
            Icon(Icons.event_available_outlined, size: 50, color: AppColors.inkFaint),
            SizedBox(height: AppSpace.md),
            Text(
              'Aucune garde ou astreinte Junior $day\nà ${_juniorHospitalLabel(_activeHospital)}${_selectedService == _allServices ? '' : ' · $_selectedService'}.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft, height: 1.45),
            ),
          ],
        ),
      );
    }

    final groups = _groupRowsByServiceForDay(rows);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 36),
        itemCount: groups.length,
        itemBuilder: (context, index) => _ServiceDayCard(group: groups[index]),
      ),
    );
  }
}

String _juniorHospitalLabel(String hospital) {
  if (hospital == kHospitalCasa) return 'HUICK de Casablanca';
  return hospitalDisplayName(hospital);
}

class _WeekSelector extends StatelessWidget {
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
      padding: EdgeInsets.fromLTRB(16, 2, 16, 7),
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
              icon: Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                _label(),
                textAlign: TextAlign.center,
                style: TextStyle(
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
              icon: Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
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
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, index) => _DayChip(
          date: weekStart.add(Duration(days: index)),
          selected: index == selectedIndex,
          onTap: () => onSelected(index),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
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
      width: 47,
      child: Material(
        color: selected ? AppColors.brand : AppColors.card,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
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
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : AppColors.inkSoft,
                  ),
                ),
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.05,
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
}

class _HospitalFilter extends StatelessWidget {
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
            padding: EdgeInsets.symmetric(horizontal: 7),
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
}

class _ServiceFilter extends StatelessWidget {
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
      padding: EdgeInsets.fromLTRB(16, 5, 16, 2),
      child: SizedBox(
        height: 48,
        child: DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.filter_alt_outlined,
              color: AppColors.brand,
              size: 19,
            ),
            labelText: 'Service',
            labelStyle: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            filled: true,
            fillColor: AppColors.card,
          ),
          dropdownColor: Theme.of(context).colorScheme.surface,
          items: [
            DropdownMenuItem(
              value: allValue,
              child: Text(
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
}

class _ServiceDayCard extends StatelessWidget {
  final _ServiceDayGroup group;

  const _ServiceDayCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final total = group.rows.length;
    final isUrgences = group.service == 'Urgences';
    return Container(
      margin: EdgeInsets.only(bottom: 14),
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
            padding: EdgeInsets.fromLTRB(15, 12, 13, 11),
            decoration: BoxDecoration(
              color: isUrgences ? AppColors.urgJour : AppColors.brandSoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                Icon(
                  isUrgences ? Icons.emergency_rounded : Icons.medical_services_rounded,
                  size: 19,
                  color: isUrgences ? AppColors.urgJourText : AppColors.brand,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.service,
                    style: TextStyle(
                      color: isUrgences ? AppColors.urgJourText : AppColors.brandDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '$total',
                  style: TextStyle(
                    color: isUrgences ? AppColors.urgJourText : AppColors.brand,
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
}

class _JuniorDutyLine extends StatelessWidget {
  final _JuniorOnCallRow row;
  const _JuniorDutyLine({required this.row});

  Future<void> _callDoctor(BuildContext context) async {
    final phone = row.ownerPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Numéro de téléphone indisponible pour ce médecin.'),
        ),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible d’ouvrir l’appel vers $phone.'),
        ),
      );
    }
  }

  String _timeLabel(ShiftType shift) {
    String compact(String? value) => (value ?? '').replaceAll(':00', 'h');
    if (shift.id.endsWith('-24h')) return '08h - 08h';
    return '${compact(shift.start)} - ${compact(shift.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final shift = ShiftCatalog.byId(row.shiftId);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: shift.color, shape: BoxShape.circle),
            child: Icon(shift.icon, color: shift.textColor, size: 23),
          ),
          SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shift.label, style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink)),
                SizedBox(height: 2),
                Text(_timeLabel(shift), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
              ],
            ),
          ),
          Container(width: 1, height: 42, color: AppColors.line),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.ownerName,
                  style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  row.shiftId.startsWith('urg-') ? 'Junior · Urgences' : 'Junior',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Tooltip(
            message: row.ownerPhone.trim().isEmpty
                ? 'Numéro indisponible'
                : 'Appeler \${row.ownerName}',
            child: Material(
              color: AppColors.brandSoft,
              shape: CircleBorder(),
              child: InkWell(
                customBorder: CircleBorder(),
                onTap: row.ownerPhone.trim().isEmpty
                    ? null
                    : () => _callDoctor(context),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(
                    Icons.phone_rounded,
                    color: row.ownerPhone.trim().isEmpty
                        ? AppColors.inkFaint
                        : AppColors.brand,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JuniorErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _JuniorErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: AppColors.danger),
            const SizedBox(height: AppSpace.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.md),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

class _JuniorOnCallRow {
  final String dateStr;
  final String shiftId;
  final String ownerName;
  final String ownerPhone;
  final String service;
  final String hospital;

  const _JuniorOnCallRow({
    required this.dateStr,
    required this.shiftId,
    required this.ownerName,
    required this.ownerPhone,
    required this.service,
    required this.hospital,
  });

  factory _JuniorOnCallRow.fromRpc(Map<String, dynamic> json) => _JuniorOnCallRow(
        dateStr: json['date_str'].toString(),
        shiftId: json['shift_id'] as String,
        ownerName: json['owner_name'] as String,
        ownerPhone: (json['owner_phone'] as String?) ?? '',
        service: json['service'] as String,
        hospital: json['hospital'] as String,
      );
}

class _ServiceDayGroup {
  final String service;
  final List<_JuniorOnCallRow> rows;
  const _ServiceDayGroup(this.service, this.rows);
}

List<_ServiceDayGroup> _groupRowsByServiceForDay(List<_JuniorOnCallRow> rows) {
  final map = <String, List<_JuniorOnCallRow>>{};
  for (final row in rows) {
    map.putIfAbsent(row.service, () => []).add(row);
  }
  final services = map.keys.toList()
    ..sort((a, b) {
      if (a == 'Urgences' && b != 'Urgences') return -1;
      if (b == 'Urgences' && a != 'Urgences') return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return services.map((service) {
    final members = map[service]!
      ..sort((a, b) {
        final c = _JuniorOnCallScreenState._shiftRank(a.shiftId).compareTo(_JuniorOnCallScreenState._shiftRank(b.shiftId));
        return c != 0 ? c : a.ownerName.toLowerCase().compareTo(b.ownerName.toLowerCase());
      });
    return _ServiceDayGroup(service, members);
  }).toList(growable: false);
}
