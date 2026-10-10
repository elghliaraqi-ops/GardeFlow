import 'package:flutter/material.dart';
import '../services/supabase_backend_service.dart';

/// One Gemini request per distinct educational document, not per word or tap.
/// The Edge Function maintains a shared cross-user cache and strict daily cap.
class PracticeGlossaryService {
  PracticeGlossaryService._();
  static final instance = PracticeGlossaryService._();
  final Map<String, Future<List<PracticeGlossaryTerm>>> _pending = {};

  Future<List<PracticeGlossaryTerm>> load({
    required String scopeId,
    required String objective,
    required String content,
    required String kind,
  }) {
    final payload = content.trim();
    if (payload.isEmpty) return Future.value(const []);
    final key = scopeId + ':' + objective.hashCode.toString() +
        ':' + payload.hashCode.toString() + ':' + kind;
    if (_pending.length > 80) _pending.clear();
    return _pending.putIfAbsent(key, () async {
      try {
        final backend = SupabaseBackendService.instance;
        if (!backend.enabled || backend.client.auth.currentSession == null) {
          return const <PracticeGlossaryTerm>[];
        }
        final response = await backend.client.functions.invoke(
          'practice-context-glossary',
          body: {
            'objective': objective.substring(0, objective.length.clamp(0, 280)),
            'content': payload.substring(0, payload.length.clamp(0, 10000)),
            'kind': kind,
          },
        );
        final data = response.data;
        if (data is! Map || data['terms'] is! List) {
          return const <PracticeGlossaryTerm>[];
        }
        return (data['terms'] as List)
            .whereType<Map>()
            .map((item) => PracticeGlossaryTerm(
                  term: (item['term'] ?? '').toString().trim(),
                  definition: (item['definition'] ?? '').toString().trim(),
                  category: (item['category'] ?? '').toString(),
                ))
            .where((item) => item.term.length >= 2 &&
                item.definition.isNotEmpty)
            .take(16)
            .toList(growable: false);
      } catch (_) {
        // Missing key, free quota or unavailable server: keep original text.
        _pending.remove(key);
        return const <PracticeGlossaryTerm>[];
      }
    });
  }
}

class PracticeGlossaryTerm {
  const PracticeGlossaryTerm({
    required this.term,
    required this.definition,
    required this.category,
  });
  final String term;
  final String definition;
  final String category;
}

class PracticeGlossaryScope extends StatefulWidget {
  const PracticeGlossaryScope({
    super.key,
    required this.scopeId,
    required this.objective,
    required this.content,
    required this.kind,
    required this.child,
  });
  final String scopeId;
  final String objective;
  final String content;
  final String kind;
  final Widget child;

  @override
  State<PracticeGlossaryScope> createState() => _PracticeGlossaryScopeState();
}

class _PracticeGlossaryScopeState extends State<PracticeGlossaryScope> {
  List<PracticeGlossaryTerm> _terms = const [];
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
        oldWidget.kind != widget.kind) {
      _terms = const [];
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    final terms = await PracticeGlossaryService.instance.load(
      scopeId: widget.scopeId,
      objective: widget.objective,
      content: widget.content,
      kind: widget.kind,
    );
    if (mounted && request == _request) setState(() => _terms = terms);
  }

  @override
  Widget build(BuildContext context) => _GlossaryInherited(
        terms: _terms,
        child: widget.child,
      );
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

/// Underlines only Gemini-selected terms that actually occur in the displayed
/// text. No lookup is performed when hovering or tapping.
class PracticeGlossaryText extends StatelessWidget {
  const PracticeGlossaryText(this.value, {super.key, this.style});
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final terms = _GlossaryInherited.of(context);
    if (terms.isEmpty || value.trim().isEmpty) return Text(value, style: style);

    final all = <_Match>[];
    for (final term in terms) {
      final pattern = RegExp(RegExp.escape(term.term), caseSensitive: false,
          unicode: true);
      for (final match in pattern.allMatches(value)) {
        final left = match.start == 0 ||
            !RegExp(r'[\wÀ-ÿ]').hasMatch(value[match.start - 1]);
        final right = match.end == value.length ||
            !RegExp(r'[\wÀ-ÿ]').hasMatch(value[match.end]);
        if (left && right) all.add(_Match(match.start, match.end, term));
      }
    }
    all.sort((a, b) => a.start != b.start
        ? a.start.compareTo(b.start)
        : (b.end - b.start).compareTo(a.end - a.start));
    final matches = <_Match>[];
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
          triggerMode: TooltipTriggerMode.tap,
          enableTapToDismiss: true,
          preferBelow: false,
          showDuration: const Duration(seconds: 7),
          waitDuration: const Duration(milliseconds: 250),
          constraints: const BoxConstraints(maxWidth: 310),
          decoration: BoxDecoration(
            color: const Color(0xFF17314E),
            border: Border.all(color: const Color(0xFF5BE7B0)),
            borderRadius: BorderRadius.circular(14),
          ),
          richMessage: TextSpan(
            children: [
              TextSpan(text: match.term.term + '\n',
                style: const TextStyle(fontWeight: FontWeight.w900,
                    color: Color(0xFFFFD166))),
              TextSpan(text: match.term.definition),
            ],
            style: const TextStyle(color: Color(0xFFF5F8FF),
                fontSize: 13, height: 1.4),
          ),
          child: Text(raw,
            style: resolved.copyWith(
              color: const Color(0xFF5BE7B0),
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: const Color(0xFF5BE7B0),
            ),
          ),
        ),
      ));
      cursor = match.end;
    }
    if (cursor < value.length) spans.add(TextSpan(text: value.substring(cursor)));
    return Text.rich(TextSpan(style: resolved, children: spans));
  }
}

class _Match {
  const _Match(this.start, this.end, this.term);
  final int start;
  final int end;
  final PracticeGlossaryTerm term;
}
