import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/supabase_backend_service.dart';
import 'practice_qcm_medical_illustration.dart';

/// A single Gemini generation per distinct learning document, with a
/// cross-user Supabase cache. Hover/tap NEVER triggers another Gemini call.
class PracticeGlossaryService {
  PracticeGlossaryService._();
  static final instance = PracticeGlossaryService._();
  final Map<String, Future<PracticeGlossaryResult>> _pending = {};

  Future<PracticeGlossaryResult> load({
    required String scopeId,
    required String objective,
    required String content,
    required String kind,
    String mode = 'overview',
    bool forceRefresh = false,
  }) {
    final payload = content.trim();
    if (payload.length < 12) {
      return Future.value(const PracticeGlossaryResult([], 'no_content'));
    }
    // v3 forces a refresh of the old short-definition-only in-memory results.
    final key = 'site-v4:' + mode + ':' + scopeId + ':' + objective.hashCode.toString() +
        ':' + payload.hashCode.toString() + ':' + kind;
    if (forceRefresh) _pending.remove(key);
    if (_pending.length > 80) _pending.clear();
    return _pending.putIfAbsent(key, () async {
      try {
        final backend = SupabaseBackendService.instance;
        if (!backend.enabled || backend.client.auth.currentSession == null) {
          return const PracticeGlossaryResult([], 'authentication_required');
        }
        final response = await backend.client.functions.invoke(
          'practice-context-glossary',
          body: {
            'objective': objective.substring(0, objective.length.clamp(0, 280)),
            'content': payload.substring(0, payload.length.clamp(0, 10000)),
            'kind': kind,
            'mode': mode,
          },
        );
        final data = response.data;
        if (data is! Map) {
          return const PracticeGlossaryResult([], 'unavailable');
        }
        final terms = (data['terms'] is List ? data['terms'] as List : const [])
            .whereType<Map>()
            .map((item) => PracticeGlossaryTerm.fromMap(item))
            .where((item) => item.term.length >= 2 && item.definition.isNotEmpty)
            .take(mode == 'chapter' ? 12 : 10)
            .toList(growable: false);
        return PracticeGlossaryResult(
          terms, (data['status'] ?? 'unavailable').toString());
      } catch (_) {
        // Quota, missing provider, expired session: original text is unaffected.
        _pending.remove(key);
        return const PracticeGlossaryResult([], 'unavailable');
      }
    });
  }
}

class PracticeGlossaryResult {
  const PracticeGlossaryResult(this.terms, this.status);
  final List<PracticeGlossaryTerm> terms;
  final String status;
}

class PracticeGlossarySection {
  const PracticeGlossarySection({required this.title, required this.items});
  final String title;
  final List<String> items;
  factory PracticeGlossarySection.fromMap(Map input) => PracticeGlossarySection(
        title: (input['title'] ?? '').toString(),
        items: (input['items'] is List ? input['items'] as List : const [])
            .whereType<String>().take(10).toList(growable: false),
      );
}

class PracticeGlossaryTerm {
  const PracticeGlossaryTerm({
    required this.term,
    required this.title,
    required this.definition,
    required this.category,
    this.sections = const [],
    this.clinicalRelevance = '',
    this.imageQuery = '',
    this.versionNote = '',
  });
  final String term, title, definition, category;
  final List<PracticeGlossarySection> sections;
  final String clinicalRelevance, imageQuery, versionNote;

  factory PracticeGlossaryTerm.fromMap(Map input) => PracticeGlossaryTerm(
        term: (input['term'] ?? '').toString().trim(),
        title: (input['title'] ?? input['term'] ?? '').toString().trim(),
        definition: (input['definition'] ?? '').toString().trim(),
        category: (input['category'] ?? 'notion').toString().trim(),
        sections: (input['sections'] is List ? input['sections'] as List : const [])
            .whereType<Map>()
            .map(PracticeGlossarySection.fromMap)
            .where((item) => item.items.isNotEmpty)
            .take(5).toList(growable: false),
        clinicalRelevance: (input['clinical_relevance'] ?? '').toString().trim(),
        imageQuery: (input['image_query'] ?? '').toString().trim(),
        versionNote: (input['version_note'] ?? '').toString().trim(),
      );
}

class PracticeGlossaryScope extends StatefulWidget {
  const PracticeGlossaryScope({
    super.key,
    required this.scopeId,
    required this.objective,
    required this.content,
    required this.kind,
    this.mode = 'overview',
    this.chapterText = '',
    required this.child,
  });
  final String scopeId, objective, content, kind, mode, chapterText;
  final Widget child;

  @override
  State<PracticeGlossaryScope> createState() => _PracticeGlossaryScopeState();
}

class _PracticeGlossaryScopeState extends State<PracticeGlossaryScope> {
  PracticeGlossaryResult _result =
      const PracticeGlossaryResult([], 'loading');
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PracticeGlossaryScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeId != widget.scopeId ||
        oldWidget.content != widget.content ||
        oldWidget.objective != widget.objective ||
        oldWidget.kind != widget.kind ||
        oldWidget.mode != widget.mode ||
        oldWidget.chapterText != widget.chapterText) {
      _result = const PracticeGlossaryResult([], 'loading');
      _load();
    }
  }

  Future<void> _load({bool retry = false}) async {
    final request = ++_request;
    final result = await PracticeGlossaryService.instance.load(
      scopeId: widget.scopeId,
      objective: widget.objective,
      content: widget.content,
      kind: widget.kind,
      mode: widget.mode,
      forceRefresh: retry,
    );
    if (mounted && request == _request) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final parentTerms = _GlossaryInherited.of(context);
    final visibleLocal = widget.chapterText.isEmpty ? _result.terms :
      _result.terms.where((term) =>
        widget.chapterText.toLowerCase().contains(term.term.toLowerCase()))
          .toList(growable:false);
    final allTerms = <PracticeGlossaryTerm>[..._result.terms];
    final known = allTerms.map((t) => t.term.toLowerCase()).toSet();
    for (final term in parentTerms) {
      if (known.add(term.term.toLowerCase())) allTerms.add(term);
    }
    return _GlossaryInherited(
        terms: allTerms,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (visibleLocal.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_outlined,
                        color: Color(0xFF5BE7B0), size: 15),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${visibleLocal.length} notions dans ce passage · toucher pour explorer',
                        style: const TextStyle(color: Color(0xFFB9CBE0),
                            fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            // Direct access to saved fiche vocabulary even if the term lies in
            // a collapsed chapter or an old lesson with unusual formatting.
            if (widget.kind == 'fiche' && visibleLocal.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final term in visibleLocal)
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(term.term,
                            style: const TextStyle(fontSize: 11,
                              fontWeight: FontWeight.w700)),
                          onPressed: () =>
                            PracticeGlossaryText.openDetail(context, term),
                          backgroundColor: const Color(0xFF17314E),
                          side: const BorderSide(color: Color(0xFF5BE7B0)),
                          labelStyle: const TextStyle(color: Color(0xFFF5F8FF)),
                        ),
                      ),
                  ],
                ),
              ),
            if (_result.terms.isEmpty &&
                !['loading', 'no_content', 'generated', 'cached'].contains(_result.status))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 14,
                      color: Color(0xFFB9CBE0)),
                  const SizedBox(width: 6),
                  const Expanded(child: Text(
                    'Explications contextuelles temporairement indisponibles',
                    style: TextStyle(fontSize: 10.5,
                        color: Color(0xFFB9CBE0)),
                  )),
                  TextButton(
                    onPressed: () {
                      setState(() => _result =
                          const PracticeGlossaryResult([], 'loading'));
                      _load(retry: true);
                    },
                    child: const Text('Réessayer', style: TextStyle(fontSize: 11)),
                  ),
                ]),
              ),
            widget.child,
          ],
        ),
      );
  }
}

class _GlossaryInherited extends InheritedWidget {
  const _GlossaryInherited({required this.terms, required super.child});
  final List<PracticeGlossaryTerm> terms;
  static List<PracticeGlossaryTerm> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlossaryInherited>()?.terms ??
          const [];

  @override
  bool updateShouldNotify(_GlossaryInherited oldWidget) =>
      !identical(terms, oldWidget.terms);
}

class PracticeGlossaryText extends StatelessWidget {
  const PracticeGlossaryText(this.value, {
    super.key,
    this.style,
    this.richEnabled = true,
  });
  final String value;
  final TextStyle? style;

  /// Never reveal staged classification details during unanswered QCMs.
  final bool richEnabled;

  @override
  Widget build(BuildContext context) {
    final terms = _GlossaryInherited.of(context);
    if (terms.isEmpty || value.trim().isEmpty) return Text(value, style: style);
    final all = <_GlossaryMatch>[];
    for (final term in terms) {
      final pattern = RegExp(RegExp.escape(term.term),
          caseSensitive: false, unicode: true);
      for (final match in pattern.allMatches(value)) {
        final left = match.start == 0 ||
            !RegExp(r'[\wÀ-ÿ]').hasMatch(value[match.start - 1]);
        final right = match.end == value.length ||
            !RegExp(r'[\wÀ-ÿ]').hasMatch(value[match.end]);
        if (left && right) {
          all.add(_GlossaryMatch(match.start, match.end, term));
        }
      }
    }
    all.sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : (b.end - b.start).compareTo(a.end - a.start));
    final matches = <_GlossaryMatch>[];
    var cursor = 0;
    for (final match in all) {
      if (match.start < cursor) continue;
      matches.add(match);
      cursor = match.end;
      if (matches.length >= 36) break;
    }
    if (matches.isEmpty) return Text(value, style: style);

    final resolved = DefaultTextStyle.of(context).style.merge(style);
    final spans = <InlineSpan>[];
    cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      final raw = value.substring(match.start, match.end);
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Tooltip(
          message: richEnabled ? match.term.definition :
              'Explication détaillée après validation du QCM',
          waitDuration: const Duration(milliseconds: 300),
          preferBelow: false,
          child: InkWell(
            onTap: () => openDetail(context, match.term, allow: richEnabled),
            child: Text(raw, style: resolved.copyWith(
              color: const Color(0xFF5BE7B0),
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: const Color(0xFF5BE7B0),
            )),
          ),
        ),
      ));
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return Text.rich(TextSpan(style: resolved, children: spans));
  }

  static void openDetail(BuildContext parent, PracticeGlossaryTerm term,
      {bool allow = true}) {
    if (!allow) {
      ScaffoldMessenger.maybeOf(parent)?.showSnackBar(const SnackBar(
        content: Text('L’explication complète sera accessible après validation.'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    var showImages = false;
    showDialog<void>(
      context: parent,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => Dialog(
          backgroundColor: const Color(0xFF10243A),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF244B68)),
            borderRadius: BorderRadius.circular(21),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * .84,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 16, 8, 10),
                child: Row(children: [
                  const Icon(Icons.school_outlined,
                    color: Color(0xFF5BE7B0), size: 22),
                  const SizedBox(width: 9),
                  Expanded(child: Text(term.title,
                    style: const TextStyle(color: Color(0xFFF5F8FF),
                      fontSize: 17, fontWeight: FontWeight.w900))),
                  IconButton(
                    tooltip: 'Fermer',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ]),
              ),
              Flexible(child: ListView(
                padding: const EdgeInsets.fromLTRB(17, 3, 17, 18),
                shrinkWrap: true,
                children: [
                  Text(term.definition,
                    style: const TextStyle(color: Color(0xFFB9CBE0),
                      fontSize: 13.5, height: 1.5)),
                  for (final section in term.sections) ...[
                    const SizedBox(height: 15),
                    Text(section.title, style: const TextStyle(
                      color: Color(0xFFFFD166), fontSize: 13,
                      fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    for (final item in section.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Icon(Icons.circle,
                                color: Color(0xFF5BE7B0), size: 6),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(item, style: const TextStyle(
                              color: Color(0xFFF5F8FF),
                              fontSize: 12.5, height: 1.45))),
                          ]),
                      ),
                  ],
                  if (term.clinicalRelevance.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('INTÉRÊT CLINIQUE',
                        style: TextStyle(color: Color(0xFFFFD166),
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(term.clinicalRelevance,
                        style: const TextStyle(color: Color(0xFFF5F8FF),
                            fontSize: 12.5, height: 1.45)),
                  ],
                  if (term.versionNote.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(term.versionNote,
                      style: const TextStyle(color: Color(0xFFB9CBE0),
                        fontSize: 11.5, fontStyle: FontStyle.italic)),
                  ],
                  if (term.imageQuery.isNotEmpty &&
                      ['anatomie', 'classification'].contains(term.category)) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () =>
                        setModalState(() => showImages = !showImages),
                      icon: Icon(showImages ? Icons.visibility_off_outlined :
                          Icons.image_search_outlined),
                      label: Text(showImages
                          ? 'Masquer les illustrations'
                          : 'Voir des illustrations médicales'),
                    ),
                    if (showImages)
                      PracticeQcmMedicalIllustration(
                        correction: PracticeQcmImageMetadata.marker +
                            jsonEncode({
                              'query': term.imageQuery,
                              'purpose': term.title,
                              'modality': 'anatomical illustration',
                              'image_type': 'anatomical_diagram',
                              'anatomy': term.title,
                              'plane': 'not_applicable',
                              'required_features': <String>[],
                              'excluded_features': <String>[
                                'wrong organ', 'book cover', 'non-medical photo'
                              ],
                            }),
                        question: term.title,
                        caseContext: '',
                      ),
                  ],
                  const SizedBox(height: 15),
                  const Text('Support pédagogique généré par IA : vérifier les '
                    'critères et l’édition des classifications dans les '
                    'recommandations de référence.',
                    style: TextStyle(fontSize: 10.5,
                        color: Color(0xFFB9CBE0))),
                ],
              )),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GlossaryMatch {
  const _GlossaryMatch(this.start, this.end, this.term);
  final int start, end;
  final PracticeGlossaryTerm term;
}
