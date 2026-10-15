import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/radiology_report_archive_service.dart';
import 'practice_daily_visual_theme.dart';

/// Private library of radiology reports, searchable on the server by metadata.
class RadiologyReportLibraryScreen extends StatefulWidget {
  const RadiologyReportLibraryScreen({super.key});
  @override
  State<RadiologyReportLibraryScreen> createState() =>
      _RadiologyReportLibraryScreenState();
}

class _RadiologyReportLibraryScreenState
    extends State<RadiologyReportLibraryScreen> {
  static const _pageSize = 40;
  final _repository = RadiologyReportArchiveService.instance;
  final _term = TextEditingController();
  final List<Map<String, dynamic>> _reports = [];
  String _exam = '', _error = '';
  DateTime? _from, _to;
  bool _byExamDate = false, _loading = false, _hasMore = false;
  int _generation = 0;

  static const _types = [
    'TDM', 'IRM', 'Échographie', 'Radiographie', 'Doppler',
    'Angio-TDM', 'Angio-IRM', 'Autre',
  ];
  String _format(DateTime? date) =>
      date == null ? 'Toutes' : DateFormat('dd/MM/yyyy').format(date);
  String _str(dynamic x) => x?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _generation++;
    _term.dispose();
    super.dispose();
  }

  Future<void> _search({bool append = false}) async {
    if (_loading && append) return;
    final serial = ++_generation;
    setState(() { _loading = true; _error = ''; });
    try {
      final result = await _repository.search(
        examType: _exam,
        indicationContains: _term.text,
        startDate: _from, endDate: _to,
        byExamDate: _byExamDate,
        offset: append ? _reports.length : 0,
        pageSize: _pageSize,
      );
      if (!mounted || serial != _generation) return;
      setState(() {
        if (!append) _reports.clear();
        _reports.addAll(result);
        _hasMore = result.length == _pageSize;
      });
    } catch (e) {
      if (mounted && serial == _generation) {
        setState(() => _error = 'Recherche impossible : $e');
      }
    } finally {
      if (mounted && serial == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final today = DateTime.now();
    final initial = (start ? _from : _to) ?? today;
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(today.year + 2, 12, 31),
      helpText: start ? 'Depuis le' : 'Jusqu’au',
    );
    if (value == null || !mounted) return;
    setState(() {
      if (start) {
        _from = value;
        if (_to != null && _to!.isBefore(value)) _to = null;
      } else {
        _to = value;
        if (_from != null && _from!.isAfter(value)) _from = null;
      }
    });
    await _search();
  }

  Future<void> _open(Map<String, dynamic> entry) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RadiologyArchivedReportDetail(report: entry),
      ),
    );
    if (mounted) _search();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PracticeDailyVisualTheme.from(context),
      child: Scaffold(
        backgroundColor: PracticeDailyVisualTheme.background,
        appBar: AppBar(
          title: const Text('Bibliothèque des CR'),
          actions: [
            IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _search,
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(gradient: PracticeDailyVisualTheme.pageGradient),
          child: SafeArea(child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: PracticeDailyVisualTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PracticeDailyVisualTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(children: [
                      Icon(Icons.folder_copy_rounded,
                        color: PracticeDailyVisualTheme.gold, size: 24),
                      SizedBox(width: 9),
                      Expanded(child: Text('Mes comptes rendus enregistrés',
                        style: TextStyle(color: PracticeDailyVisualTheme.text, fontSize: 17,
                          fontWeight: FontWeight.w900))),
                    ]),
                    const SizedBox(height: 6),
                    const Text(
                      'Archives privées de votre compte GardeFlow. '
                      'Recherchez, ouvrez, modifiez ou copiez un CR.',
                      style: TextStyle(color: PracticeDailyVisualTheme.muted, fontSize: 12)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _term,
                      style: const TextStyle(color: PracticeDailyVisualTheme.text),
                      decoration: const InputDecoration(
                        labelText: 'Rechercher par indication',
                        hintText: 'Ex. céphalées, douleur abdominale…',
                        prefixIcon: Icon(Icons.search_rounded),
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                    ),
                    const SizedBox(height: 11),
                    DropdownButtonFormField<String>(
                      value: _exam,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Type d’examen',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '', child: Text('Tous les examens')),
                        for (final type in _types)
                          DropdownMenuItem(value: type, child: Text(type)),
                      ],
                      onChanged: (value) {
                        setState(() => _exam = value ?? '');
                        _search();
                      },
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false,
                          label: Text('Date du CR')),
                        ButtonSegment(value: true,
                          label: Text('Date d’examen')),
                      ],
                      selected: {_byExamDate},
                      onSelectionChanged: (selection) {
                        setState(() => _byExamDate = selection.first);
                        _search();
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(start: true),
                        icon: const Icon(Icons.calendar_today_rounded, size: 16),
                        label: Text('Depuis : ${_format(_from)}'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(start: false),
                        icon: const Icon(Icons.event_rounded, size: 16),
                        label: Text('Jusqu’au : ${_format(_to)}'),
                      ),
                      if (_from != null || _to != null)
                        TextButton.icon(
                          onPressed: () {
                            setState(() { _from = null; _to = null; });
                            _search();
                          },
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text('Effacer les dates'),
                        ),
                    ]),
                    const SizedBox(height: 9),
                    FilledButton.icon(
                      onPressed: _loading ? null : _search,
                      icon: const Icon(Icons.filter_alt_rounded),
                      label: const Text('Rechercher les comptes rendus'),
                    ),
                  ],
                ),
              ),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(color: PracticeDailyVisualTheme.mint),
              ],
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_error,
                  style: const TextStyle(color: Color(0xFFFFD166))),
              ],
              const SizedBox(height: 18),
              Text('${_reports.length} résultat(s) affiché(s)',
                style: const TextStyle(color: PracticeDailyVisualTheme.muted,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (!_loading && _error.isEmpty && _reports.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(22),
                  child: Text(
                    'Aucun compte rendu pour ces filtres. '
                    'Les nouveaux CR apparaîtront ici après leur génération.',
                    style: TextStyle(color: PracticeDailyVisualTheme.muted),
                    textAlign: TextAlign.center),
                ),
              for (final record in _reports) ...[
                Material(
                  color: PracticeDailyVisualTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: ValueKey('report-' + _str(record['id'])),
                    onTap: () => _open(record),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: PracticeDailyVisualTheme.border),
                      ),
                      child: Row(children: [
                        const Icon(Icons.description_outlined,
                          color: PracticeDailyVisualTheme.gold, size: 23),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_str(record['exam_type'])} • '
                              '${_str(record['region'])}',
                              style: const TextStyle(color: PracticeDailyVisualTheme.text,
                                fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(height: 5),
                            Text(_str(record['indication']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: PracticeDailyVisualTheme.muted,
                                fontSize: 12)),
                            const SizedBox(height: 6),
                            Text(_dateCaption(record),
                              style: const TextStyle(color: PracticeDailyVisualTheme.mint,
                                fontSize: 11)),
                          ],
                        )),
                        const Icon(Icons.chevron_right_rounded,
                          color: PracticeDailyVisualTheme.gold),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_hasMore)
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _search(append: true),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: const Text('Afficher d’autres comptes rendus'),
                ),
            ],
          )),
        ),
      ),
    );
  }

  String _dateCaption(Map<String, dynamic> entry) {
    final created = DateTime.tryParse(_str(entry['created_at']))?.toLocal();
    final examDate = DateTime.tryParse(_str(entry['exam_date']));
    return 'Enregistré : ${_format(created)}' +
        (examDate == null ? '' : ' · Examen : ${_format(examDate)}');
  }
}

/// Opens a saved draft without a new Groq call. Editing updates the SAME row.
class RadiologyArchivedReportDetail extends StatefulWidget {
  const RadiologyArchivedReportDetail({super.key, required this.report});
  final Map<String, dynamic> report;
  @override
  State<RadiologyArchivedReportDetail> createState() =>
      _RadiologyArchivedReportDetailState();
}

class _RadiologyArchivedReportDetailState
    extends State<RadiologyArchivedReportDetail> {
  late final TextEditingController _text, _indication;
  bool _saving = false, _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: widget.report['report_text']?.toString() ?? '',
    );
    _indication = TextEditingController(
      text: widget.report['indication']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _indication.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_text.text.trim().isEmpty || _indication.text.trim().isEmpty) {
      setState(() => _error = 'Indication et compte rendu obligatoires.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await RadiologyReportArchiveService.instance.save(
        id: widget.report['id'] as String,
        examType: widget.report['exam_type'].toString(),
        region: widget.report['region'].toString(),
        indication: _indication.text,
        examDate: DateTime.tryParse(
          widget.report['exam_date']?.toString() ?? '',
        ),
        reportText: _text.text,
      );
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modifications enregistrées.')),
      );
    } catch (e) {
      if (mounted) setState(() =>
          _error = 'Enregistrement impossible : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmExit() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text(
          'Quitter sans enregistrer les changements apportés au CR ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Rester')),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitter sans enregistrer')),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PracticeDailyVisualTheme.from(context),
      child: PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmExit() && context.mounted) {
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          backgroundColor: PracticeDailyVisualTheme.background,
          appBar: AppBar(title: const Text('Compte rendu enregistré')),
          body: SafeArea(child: ListView(
            padding: const EdgeInsets.all(15),
            children: [
              Text('${widget.report['exam_type']} · '
                '${widget.report['region']}',
                style: const TextStyle(color: PracticeDailyVisualTheme.text,
                  fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              const Text('Projet radiologique — validation médicale requise.',
                style: TextStyle(color: PracticeDailyVisualTheme.muted, fontSize: 12)),
              const SizedBox(height: 14),
              TextField(
                controller: _indication,
                maxLength: 3500,
                onChanged: (_) => setState(() => _dirty = true),
                style: const TextStyle(color: PracticeDailyVisualTheme.text),
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Indication',
                  border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _text,
                onChanged: (_) => setState(() => _dirty = true),
                style: const TextStyle(color: PracticeDailyVisualTheme.text, height: 1.48),
                minLines: 18, maxLines: null,
                decoration: const InputDecoration(
                  labelText: 'Compte rendu modifiable',
                  border: OutlineInputBorder()),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                  style: const TextStyle(color: Color(0xFFFFD166))),
              ],
              const SizedBox(height: 14),
              Wrap(spacing: 9, runSpacing: 9, children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Enregistrement…'
                    : 'Enregistrer les modifications'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _text.text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('CR copié.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copier'),
                ),
              ]),
            ],
          )),
        ),
      ),
    );
  }
}
