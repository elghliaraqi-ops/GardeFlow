import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/hospitals.dart';
import '../services/supabase_backend_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'astreinte_screen.dart';

class SeniorOnCallScreen extends StatefulWidget {
  final bool embedded;

  const SeniorOnCallScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<SeniorOnCallScreen> createState() => _SeniorOnCallScreenState();
}

class _SeniorOnCallScreenState extends State<SeniorOnCallScreen> {
  static const _allServices = '__all_services__';

  late DateTime _weekStart;
  late int _selectedDayIndex;
  bool _loading = true;
  bool _hospitalInitialized = false;
  String? _error;
  String? _selectedHospital;
  String _selectedService = _allServices;
  List<_SeniorOnCallRow> _rows = const [];

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
  DateTime get _selectedDay =>
      _weekStart.add(Duration(days: _selectedDayIndex));
  String get _selectedDateStr =>
      DateFormat('yyyy-MM-dd').format(_selectedDay);
  String get _activeHospital => _selectedHospital ?? kHospitals.first;

  static DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(
      Duration(days: normalized.weekday - DateTime.monday),
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final backend = SupabaseBackendService.instance;
      if (!backend.enabled || backend.client.auth.currentUser == null) {
        throw StateError('Connexion Supabase requise.');
      }
      final data = await backend.fetchSeniorOnCallRoster(
        from: _weekStart,
        to: _weekEnd,
      );
      final rows = data.map(_SeniorOnCallRow.fromRpc).toList()
        ..sort(_compareRows);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _normalizeServiceFilter();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _error = 'Impossible de charger les Séniors d’astreinte.\n$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static int _compareRows(_SeniorOnCallRow a, _SeniorOnCallRow b) {
    var c = a.dateStr.compareTo(b.dateStr);
    if (c != 0) return c;
    c = a.hospital.toLowerCase().compareTo(b.hospital.toLowerCase());
    if (c != 0) return c;
    c = a.service.toLowerCase().compareTo(b.service.toLowerCase());
    if (c != 0) return c;
    return a.seniorName.toLowerCase().compareTo(b.seniorName.toLowerCase());
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
    final services = _rows
        .where((row) => row.hospital == _activeHospital)
        .map((row) => row.service)
        .toSet();
    if (!services.contains(_selectedService)) {
      _selectedService = _allServices;
    }
  }

  List<_SeniorOnCallRow> get _visibleRows {
    return _rows.where((row) {
      if (row.hospital != _activeHospital) return false;
      if (row.dateStr != _selectedDateStr) return false;
      if (_selectedService != _allServices &&
          row.service != _selectedService) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  void _changeWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * delta));
      _selectedDayIndex = 0;
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

  Future<void> _openMonthCalendar() async {
    final current = _selectedDay;
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('fr', 'FR'),
      initialDate: current,
      firstDate: DateTime(current.year - 1, 1, 1),
      lastDate: DateTime(current.year + 2, 12, 31),
      helpText: 'Calendrier des astreintes séniors',
      cancelText: 'Fermer',
      confirmText: 'Afficher',
    );
    if (picked == null || !mounted) return;
    final monday = _startOfWeek(picked);
    setState(() {
      _weekStart = monday;
      _selectedDayIndex = picked.weekday - DateTime.monday;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 10, 2),
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
          onSelected: (index) => setState(() => _selectedDayIndex = index),
        ),
        _SeniorHospitalFilter(
          selectedHospital: _activeHospital,
          onChanged: _selectHospital,
        ),
        _SeniorServiceFilter(
          services: _availableServices,
          value: _selectedService,
          allValue: _allServices,
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedService = value);
            }
          },
        ),
        const SizedBox(height: 4),
        Expanded(child: _buildBody()),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(color: AppColors.paper, child: body);
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Astreintes Séniors'),
        actions: [
          IconButton(
            tooltip: 'Photos / listes originales',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AstreinteScreen()),
            ),
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

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _SeniorErrorState(message: _error!, onRetry: _load);
    }

    final rows = _visibleRows;
    if (rows.isEmpty) {
      final day = DateFormat('EEEE d MMMM', 'fr_FR').format(_selectedDay);
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
          children: [
            const SizedBox(height: 70),
            Icon(
              Icons.medical_services_outlined,
              size: 48,
              color: AppColors.inkFaint,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              'Aucune astreinte sénior validée $day\nà ${hospitalDisplayName(_activeHospital)}${_selectedService == _allServices ? '' : ' · $_selectedService'}.',
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

    final grouped = <String, List<_SeniorOnCallRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.service, () => []).add(row);
    }
    final services = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          36,
        ),
        itemCount: services.length,
        itemBuilder: (context, index) {
          final service = services[index];
          return _SeniorServiceCard(
            service: service,
            rows: grouped[service]!,
          );
        },
      ),
    );
  }
}

class _SeniorServiceCard extends StatelessWidget {
  final String service;
  final List<_SeniorOnCallRow> rows;

  const _SeniorServiceCard({
    required this.service,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadow.low,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(15, 12, 13, 11),
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(17),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.medical_services_rounded,
                  size: 19,
                  color: AppColors.brand,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service,
                    style: TextStyle(
                      color: AppColors.brandDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '${rows.length}',
                  style: TextStyle(
                    color: AppColors.brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            _SeniorDutyLine(row: rows[i]),
            if (i != rows.length - 1)
              const Divider(height: 1, indent: 15, endIndent: 15),
          ],
        ],
      ),
    );
  }
}

class _SeniorDutyLine extends StatelessWidget {
  final _SeniorOnCallRow row;

  const _SeniorDutyLine({required this.row});

  Future<void> _callSenior(BuildContext context) async {
    final phone = row.seniorPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Numéro de téléphone indisponible pour ce médecin.'),
        ),
      );
      return;
    }
    final launched = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ouvrir l’appel vers $phone.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = row.seniorPhone.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: 12,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.conge,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              color: AppColors.congeText,
              size: 23,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.seniorName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPhone
                      ? 'Sénior · ${row.seniorPhone}'
                      : 'Sénior · numéro non renseigné',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: hasPhone
                ? 'Appeler ${row.seniorName}'
                : 'Numéro indisponible',
            child: Material(
              color: AppColors.brandSoft,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: hasPhone ? () => _callSenior(context) : null,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(
                    Icons.phone_rounded,
                    size: 21,
                    color: hasPhone ? AppColors.brand : AppColors.inkFaint,
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

class _SeniorWeekSelector extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _SeniorWeekSelector({
    required this.start,
    required this.end,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final label = start.month == end.month
        ? '${start.day} – ${end.day} ${DateFormat('MMMM', 'fr_FR').format(end)}'
        : '${start.day} ${DateFormat('MMM', 'fr_FR').format(start)} – ${end.day} ${DateFormat('MMM', 'fr_FR').format(end)}';
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
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                label,
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
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeniorDaySelector extends StatelessWidget {
  final DateTime weekStart;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _SeniorDaySelector({
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final date = weekStart.add(Duration(days: index));
          final selected = index == selectedIndex;
          final raw = DateFormat('EEE', 'fr_FR').format(date).replaceAll('.', '');
          final day = raw.isEmpty
              ? ''
              : raw[0].toUpperCase() + raw.substring(1);
          return SizedBox(
            width: 47,
            child: Material(
              color: selected ? AppColors.brand : AppColors.card,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                onTap: () => onSelected(index),
                borderRadius: BorderRadius.circular(11),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 3),
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
                        day,
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
        },
      ),
    );
  }
}

class _SeniorHospitalFilter extends StatelessWidget {
  final String selectedHospital;
  final ValueChanged<String> onChanged;

  const _SeniorHospitalFilter({
    required this.selectedHospital,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        itemCount: kHospitals.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final hospital = kHospitals[index];
          final selected = hospital == selectedHospital;
          return ChoiceChip(
            label: Text(
              hospitalDisplayName(hospital),
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

class _SeniorServiceFilter extends StatelessWidget {
  final List<String> services;
  final String value;
  final String allValue;
  final ValueChanged<String?> onChanged;

  const _SeniorServiceFilter({
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
            prefixIcon: Icon(
              Icons.filter_alt_outlined,
              color: AppColors.brand,
              size: 19,
            ),
            labelText: 'Service',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            filled: true,
            fillColor: AppColors.card,
          ),
          items: [
            DropdownMenuItem(
              value: allValue,
              child: const Text('Tous les services'),
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

class _SeniorErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _SeniorErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: AppColors.danger,
            ),
            const SizedBox(height: AppSpace.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.md),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeniorOnCallRow {
  final String dateStr;
  final String seniorName;
  final String seniorPhone;
  final String service;
  final String hospital;

  const _SeniorOnCallRow({
    required this.dateStr,
    required this.seniorName,
    required this.seniorPhone,
    required this.service,
    required this.hospital,
  });

  factory _SeniorOnCallRow.fromRpc(Map<String, dynamic> json) {
    return _SeniorOnCallRow(
      dateStr: json['duty_date'].toString(),
      seniorName: (json['senior_name'] as String?) ?? '',
      seniorPhone: (json['senior_phone'] as String?) ?? '',
      service: (json['service'] as String?) ?? '',
      hospital: (json['hospital'] as String?) ?? '',
    );
  }
}
