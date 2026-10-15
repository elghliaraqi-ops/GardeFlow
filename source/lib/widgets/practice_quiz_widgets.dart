import 'package:flutter/material.dart';

import '../screens/practice_daily_visual_theme.dart';
import '../theme/app_theme.dart';
import 'practice_keyword_text.dart';

/// Presentation shared with the original clinical-case QCM screen.
/// Callers own answers, validation, persistence, chronology and generation.
class PracticeQuizCard extends StatelessWidget {
  const PracticeQuizCard({
    super.key,
    required this.index,
    required this.total,
    required this.topic,
    required this.question,
    required this.options,
    this.beforeQuestion,
    this.afterQuestion,
    this.headerLabel = 'DÉFI',
    this.trailing = const [],
    this.submitting = false,
  });
  final int index, total;
  final String topic, question;
  final List<Widget> options, trailing;
  final Widget? beforeQuestion, afterQuestion;
  final String headerLabel;
  final bool submitting;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          PracticeDailyVisualTheme.purple.withOpacity(.32),
          PracticeDailyVisualTheme.elevated,
          PracticeDailyVisualTheme.blue.withOpacity(.18),
        ],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: PracticeDailyVisualTheme.purple.withOpacity(.50),
      ),
      boxShadow: [
        BoxShadow(
          color: PracticeDailyVisualTheme.purple.withOpacity(.14),
          blurRadius: 22,
          offset: const Offset(0, 9),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.sports_esports_rounded,
              color: PracticeDailyVisualTheme.gold,
              size: 19,
            ),
            const SizedBox(width: 7),
            Text(
              '$headerLabel ${index + 1} / $total',
              style: const TextStyle(
                color: PracticeDailyVisualTheme.gold,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.auto_awesome_rounded,
              color: PracticeDailyVisualTheme.purple,
              size: 13,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                practiceQuizTopic(topic),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: PracticeDailyVisualTheme.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : (index + 1) / total,
            minHeight: 5,
            backgroundColor: PracticeDailyVisualTheme.border,
            color: PracticeDailyVisualTheme.gold,
          ),
        ),
        if (beforeQuestion != null) ...[
          const SizedBox(height: 12),
          beforeQuestion!,
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.13),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(.10)),
          ),
          child: PracticeKeywordText(
            question,
            style: const TextStyle(
              color: PracticeDailyVisualTheme.text,
              fontSize: 15.2,
              height: 1.43,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (afterQuestion != null) ...[
          const SizedBox(height: 12),
          afterQuestion!,
        ],
        const SizedBox(height: 12),
        for (var i = 0; i < options.length; i++) ...[
          options[i],
          if (i < options.length - 1) const SizedBox(height: 7),
        ],
        if (submitting) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(
            minHeight: 2,
            color: PracticeDailyVisualTheme.gold,
            backgroundColor: PracticeDailyVisualTheme.border,
          ),
        ],
        ...trailing,
      ],
    ),
  );
}

class PracticeQuizOption extends StatelessWidget {
  final int index;
  final String label;
  final bool selected;
  final bool showCorrection;
  final bool isCorrect;
  final VoidCallback? onTap;

  const PracticeQuizOption({
    super.key,
    required this.index,
    required this.label,
    required this.selected,
    required this.showCorrection,
    required this.isCorrect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border = PracticeDailyVisualTheme.border;
    Color background = PracticeDailyVisualTheme.surface;
    Color foreground = PracticeDailyVisualTheme.text;
    if (showCorrection && isCorrect) {
      border = AppColors.success;
      background = AppColors.success.withOpacity(.10);
      foreground = AppColors.success;
    } else if (showCorrection && selected && !isCorrect) {
      border = AppColors.danger;
      background = AppColors.danger.withOpacity(.10);
      foreground = AppColors.danger;
    } else if (selected) {
      border = PracticeDailyVisualTheme.purple;
      background = PracticeDailyVisualTheme.purple.withOpacity(.20);
      foreground = PracticeDailyVisualTheme.gold;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: border,
              width: selected || (showCorrection && isCorrect) ? 1.35 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: foreground.withOpacity(.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: foreground.withOpacity(.18)),
                ),
                child: Text(
                  String.fromCharCode(65 + index),
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: PracticeKeywordText(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.3,
                      height: 1.43,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (showCorrection && isCorrect)
                const Padding(
                  padding: EdgeInsets.only(left: 7, top: 4),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 19,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PracticeQuizFeedback extends StatefulWidget {
  const PracticeQuizFeedback({
    super.key,
    required this.correct,
    required this.child,
    this.expanded,
    this.onToggle,
  });
  final bool correct;
  final Widget child;
  final bool? expanded;
  final VoidCallback? onToggle;
  @override
  State<PracticeQuizFeedback> createState() => _PracticeQuizFeedbackState();
}

class _PracticeQuizFeedbackState extends State<PracticeQuizFeedback> {
  bool _expanded = true;
  @override
  Widget build(BuildContext context) {
    final open = widget.expanded ?? _expanded;
    final semantic = widget.correct ? AppColors.success : AppColors.danger;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            semantic.withOpacity(.14),
            PracticeDailyVisualTheme.surface,
            PracticeDailyVisualTheme.purple.withOpacity(.12),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: semantic.withOpacity(.48)),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:
                  widget.onToggle ??
                  () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      widget.correct
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: semantic,
                      size: 20,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        widget.correct ? 'Bonne réponse' : 'À revoir',
                        style: TextStyle(
                          color: semantic,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: PracticeDailyVisualTheme.gold,
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'EXPLICATION IA',
                      style: TextStyle(
                        color: PracticeDailyVisualTheme.gold,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: PracticeDailyVisualTheme.gold,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

class PracticeQuizNavigation extends StatelessWidget {
  const PracticeQuizNavigation({
    super.key,
    required this.index,
    required this.results,
    this.onPrevious,
    this.onNext,
    this.onSelect,
    this.nextLabel = 'QCM suivant',
    this.nextIcon = Icons.chevron_right_rounded,
  });
  final int index;
  final List<bool?> results;
  final VoidCallback? onPrevious, onNext;
  final ValueChanged<int>? onSelect;
  final String nextLabel;
  final IconData nextIcon;
  Widget _arrow(String label, IconData icon, VoidCallback? action) => Tooltip(
    message: label,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: action == null
                ? PracticeDailyVisualTheme.surface.withOpacity(.55)
                : PracticeDailyVisualTheme.elevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: action == null
                  ? PracticeDailyVisualTheme.border.withOpacity(.55)
                  : PracticeDailyVisualTheme.purple.withOpacity(.55),
            ),
          ),
          child: Icon(
            icon,
            color: action == null
                ? PracticeDailyVisualTheme.muted
                : PracticeDailyVisualTheme.gold,
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Row(
    children: [
      _arrow('QCM précédent', Icons.chevron_left_rounded, onPrevious),
      const SizedBox(width: 10),
      Expanded(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 8,
          children: List.generate(results.length, (i) {
            final active = i == index;
            final color = results[i] == true
                ? AppColors.success
                : results[i] == false
                ? AppColors.danger
                : active
                ? PracticeDailyVisualTheme.gold
                : PracticeDailyVisualTheme.purple;
            return Semantics(
              label: 'Question ${i + 1}',
              selected: active,
              button: onSelect != null,
              child: GestureDetector(
                onTap: onSelect == null ? null : () => onSelect!(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: active ? 22 : 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
      const SizedBox(width: 10),
      _arrow(nextLabel, nextIcon, onNext),
    ],
  );
}

String practiceQuizTopic(String topic) =>
    const <String, String>{
      'motif': 'Motif de consultation',
      'symptome': 'Symptômes',
      'examen': 'Examen clinique',
      'imagerie': 'Imagerie',
      'synthese': 'Synthèse diagnostique',
      'prise_en_charge': 'Prise en charge',
      'orientation': 'Orientation',
      'avis_specialise': 'Avis spécialisé',
    }[topic.toLowerCase()] ??
    topic;
