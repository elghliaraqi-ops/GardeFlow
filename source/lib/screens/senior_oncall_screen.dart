import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/hospitals.dart';
import '../models/app_user.dart';
import '../services/senior_contact_service.dart';
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
  final Set<String> _savingContacts = <String>{};

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
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
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
    return a.ownerName.toLowerCase().compareTo(b.ownerName.toLowerCase());
  }

  List<String> get _availableServices {
    final values = _rows
        .where((r) => r.hospital == _activeHospital)
        .map((r) => r.service.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  void _normalizeServiceFilter() {
    if (_selectedService == _allServices) return;
    final services = _rows
        .where((r) => r.hospital == _activeHospital)
        .map((r) => r.service)
        .toSet();
    if (!services.contains(_selectedService)) {
      _selectedService = _allServices;
    }
  }

  List<_SeniorOnCallRow> get _visibleRows {
    return _rows.where((r) {
      if (r.hospital != _activeHospital) return false;
      if (r.dateStr != _selectedDateStr) return false;
      if (_selectedService != _allServices && r.service != _selectedService) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  void _changeWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: delta * 7));
      _selectedDayIndex = 0;
    });
    _load();
  }

  void _selectHospital(String hospital) {
    if (hospital == _selectedHospital) return;
    setState(() {
      _selectedHospital = hospital;
      _selectedService = _allServices;
    });
  }

  Future<void> _openMonthCalendar() async {
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('fr', 'FR'),
      initialDate: _selectedDay,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime(2028, 12, 31),
      helpText: 'Calendrier des astreintes séniors',
      cancelText: 'Fermer',
      confirmText: 'Afficher',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _weekStart = _startOfWeek(picked);
      _selectedDayIndex = picked.weekday - DateTime.monday;
    });
    await _load();
  }

  void _openPhotos() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AstreinteScreen()),
    );
  }

  Future<void> _addContact(_SeniorOnCallRow row) async {
    final key = row.contactKey;
    if (_savingContacts.contains(key)) return;

    final controller = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter le contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.ownerName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              row.service,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numéro de téléphone',
                hintText: '06 12 34 56 78',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) Navigator.pop(ctx, value.trim());
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(ctx, value);
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Ajouter'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (phone == null || phone.trim().isEmpty || !mounted) return;

    setState(() => _savingContacts.add(key));
    try {
      final result = await SupabaseBackendService.instance.addSeniorOnCallContact(
        name: row.ownerName,
        phone: phone,
        hospital: row.hospital,
        service: row.service,
      );
      final normalized = result['phone']?.toString() ?? phone;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$normalized ajouté pour ${row.ownerName}.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ajout du contact impossible : $e')),
      );
    } finally {
      if (mounted) setState(() => _savingContacts.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        if (widget.embedded)
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

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
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
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final rows = _visibleRows;
    if (rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpace.xl),
          children: [
            const SizedBox(height: 70),
            Icon(
              Icons.event_available_outlined,
              size: 50,
              color: AppColors.inkFaint,
            ),
            const SizedBox(height: AppSpace.md),
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
    final isAdmin = context.watch<AppState>().currentUser?.role == UserRole.admin;

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
            canAddContact: isAdmin,
            savingContacts: _savingContacts,
            onAddContact: _addContact,
          );
        },
      ),
    );
  }
}

class _SeniorServiceCard extends StatelessWidget {
  final String service;
  final List<_SeniorOnCallRow> rows;
  final bool canAddContact;
  final Set<String> savingContacts;
  final ValueChanged<_SeniorOnCallRow> onAddContact;

  const _SeniorServiceCard({
    required this.service,
    required this.rows,
    required this.canAddContact,
    required this.savingContacts,
    required this.onAddContact,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _seniorServiceAccent(service);
    final headerBackground = _seniorServiceBackground(accent);
    final headerForeground = _seniorServiceForeground(accent);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.48), width: 1.2),
        boxShadow: AppShadow.low,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(15, 12, 13, 11),
            decoration: BoxDecoration(
              color: headerBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(17),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.medical_services_rounded,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    service,
                    style: TextStyle(
                      color: headerForeground,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${rows.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            _SeniorDutyLine(
              row: rows[i],
              canAddContact: canAddContact,
              savingContact: savingContacts.contains(rows[i].contactKey),
              onAddContact: () => onAddContact(rows[i]),
            ),
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
  final bool canAddContact;
  final bool savingContact;
  final VoidCallback onAddContact;

  const _SeniorDutyLine({
    required this.row,
    required this.canAddContact,
    required this.savingContact,
    required this.onAddContact,
  });

  Future<void> _call(BuildContext context) async {
    final phone = row.ownerPhone.trim();
    if (phone.isEmpty) return;
    final launched = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ouvrir l’appel vers $phone.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = row.ownerPhone.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: 11,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              color: AppColors.brand,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.ownerName,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPhone ? row.ownerPhone : 'Numéro non renseigné',
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (hasPhone)
            IconButton.filledTonal(
              tooltip: 'Appeler',
              onPressed: () => _call(context),
              icon: const Icon(Icons.phone_rounded, size: 20),
            )
          else if (canAddContact)
            FilledButton.tonalIcon(
              onPressed: savingContact ? null : onAddContact,
              icon: savingContact
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text(
                'Ajouter contact',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            )
          else
            IconButton.filledTonal(
              tooltip: 'Numéro indisponible',
              onPressed: null,
              icon: const Icon(Icons.phone_disabled_rounded, size: 20),
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
        : '${DateFormat('d MMM', 'fr_FR').format(start)} – ${DateFormat('d MMM', 'fr_FR').format(end)}';
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
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ),
            IconButton(
              onPressed: onNext,
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
          final label = raw.isEmpty
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
  final ValueChanged<String?> onChanged;

  const _SeniorServiceFilter({
    required this.services,
    required this.value,
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
            filled: true,
            fillColor: AppColors.card,
          ),
          items: [
            const DropdownMenuItem(
              value: _SeniorOnCallScreenState._allServices,
              child: Text('Tous les services'),
            ),
            for (final service in services)
              DropdownMenuItem(
                value: service,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _seniorServiceAccent(service),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        service,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

Color _seniorServiceAccent(String service) {
  final value = service.toLowerCase();

  if (value.contains('urgences')) return const Color(0xFFE05252);
  if (value.contains('cardiologie') || value.contains('usic')) {
    return const Color(0xFFD94A67);
  }
  if (value.contains('cathlab')) return const Color(0xFFE07A3F);
  if (value.contains('usip')) return const Color(0xFFF0A43A);
  if (value.contains('réanimation') || value.contains('reanimation')) {
    return const Color(0xFFE16A3D);
  }
  if (value.contains('neurochirurgie')) return const Color(0xFF6D5BD0);
  if (value.contains('neurologie')) return const Color(0xFF7668D8);
  if (value.contains('radiologie')) return const Color(0xFF3E7CC8);
  if (value.contains('pneumologie')) return const Color(0xFF2A9DB0);
  if (value.contains('néphrologie') || value.contains('nephrologie')) {
    return const Color(0xFF2A9A83);
  }
  if (value.contains('endocrinologie')) return const Color(0xFF8A63C7);
  if (value.contains('gastro')) return const Color(0xFFC98724);
  if (value.contains('dermatologie')) return const Color(0xFF9A5BA8);
  if (value.contains('gynécologie') || value.contains('gynecologie')) {
    return const Color(0xFFD35E91);
  }
  if (value.contains('ophtalmologie')) return const Color(0xFF388FB7);
  if (value.contains('hématologie') ||
      value.contains('hematologie') ||
      value.contains('oncologie')) {
    return const Color(0xFFB5548C);
  }
  if (value.contains('urologie')) return const Color(0xFF338E78);
  if (value.contains('traumatologie') || value.contains('orthopédie')) {
    return const Color(0xFF4F6FB8);
  }
  if (value.contains('orl') || value.contains('maxillo')) {
    return const Color(0xFF607DB2);
  }
  if (value.contains('thoracique')) return const Color(0xFF347F91);
  if (value.contains('plastique')) return const Color(0xFF9A66B4);
  if (value.contains('viscérale') || value.contains('viscerale')) {
    return const Color(0xFF4B7F56);
  }
  if (value.contains('blood')) return const Color(0xFFB84444);
  if (value.contains('médecine physique') ||
      value.contains('medecine physique')) {
    return const Color(0xFF588A5C);
  }

  const palette = <Color>[
    Color(0xFF4D7DB7),
    Color(0xFF6D67B5),
    Color(0xFF3F8A76),
    Color(0xFFB2733A),
    Color(0xFFA45775),
    Color(0xFF547F9E),
    Color(0xFF7C6AAB),
    Color(0xFF5E8E53),
  ];
  var hash = 0;
  for (final unit in service.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

Color _seniorServiceBackground(Color accent) {
  final opacity = AppColors.isDarkMode ? 0.30 : 0.14;
  return Color.alphaBlend(accent.withOpacity(opacity), AppColors.card);
}

Color _seniorServiceForeground(Color accent) {
  if (AppColors.isDarkMode) return Colors.white;
  return Color.lerp(accent, Colors.black, 0.35) ?? accent;
}

class _SeniorOnCallRow {
  final String dateStr;
  final String ownerName;
  final String ownerPhone;
  final String service;
  final String hospital;

  const _SeniorOnCallRow({
    required this.dateStr,
    required this.ownerName,
    required this.ownerPhone,
    required this.service,
    required this.hospital,
  });

  String get contactKey => '$hospital|$ownerName';

  factory _SeniorOnCallRow.fromRpc(Map<String, dynamic> json) {
    return _SeniorOnCallRow(
      dateStr: json['date_str'].toString(),
      ownerName: (json['owner_name'] as String?) ?? '',
      ownerPhone: (json['owner_phone'] as String?) ?? '',
      service: (json['service'] as String?) ?? '',
      hospital: (json['hospital'] as String?) ?? '',
    );
  }
}
