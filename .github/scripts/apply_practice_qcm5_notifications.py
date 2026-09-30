from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label}: source block not found')
    return text.replace(old, new, 1)

# ---------------------------------------------------------------------------
# Clinical cases UI — 5 questions per case + explanation after every answer.
# ---------------------------------------------------------------------------
path = Path('source/lib/screens/clinical_cases_section.dart')
text = path.read_text(encoding='utf-8')
text = text.replace(
    'Cas anonymisés · QCM pédagogique · correction après réponse',
    'Cas anonymisés · 5 QCM de raisonnement · explication IA après chaque réponse',
)
text = text.replace(
    'Les patients validés dans Practice apparaîtront ici automatiquement sous forme anonymisée avec un QCM.',
    'Les patients validés dans Practice apparaîtront ici automatiquement sous forme anonymisée avec 5 QCM pédagogiques.',
)

start = text.find('class _ClinicalCaseCardState extends State<_ClinicalCaseCard> {')
end = text.find('\nclass _CaseSection extends StatelessWidget {', start)
if start < 0 or end < 0:
    raise SystemExit('clinical case card boundaries not found')

new_card_state = r'''class _ClinicalCaseCardState extends State<_ClinicalCaseCard> {
  bool _expanded = false;
  bool _submitting = false;
  int _currentQcm = 0;
  List<ClinicalCaseQcm> _qcms = <ClinicalCaseQcm>[];

  @override
  void initState() {
    super.initState();
    _syncQcms(resetIndex: true);
  }

  @override
  void didUpdateWidget(covariant _ClinicalCaseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = widget.post.id != oldWidget.post.id ||
        widget.post.qcms.length != oldWidget.post.qcms.length ||
        widget.post.qcms
            .map((q) => '${q.id}:${q.mySelectedIndex}:${q.correction.length}')
            .join('|') !=
            oldWidget.post.qcms
                .map((q) => '${q.id}:${q.mySelectedIndex}:${q.correction.length}')
                .join('|');
    if (changed) _syncQcms(resetIndex: widget.post.id != oldWidget.post.id);
  }

  void _syncQcms({required bool resetIndex}) {
    _qcms = List<ClinicalCaseQcm>.from(widget.post.qcms)
      ..sort((a, b) => a.position.compareTo(b.position));
    if (_qcms.isEmpty) {
      _currentQcm = 0;
      return;
    }
    if (resetIndex || _currentQcm >= _qcms.length) {
      final firstUnanswered = _qcms.indexWhere((q) => !q.answered);
      _currentQcm = firstUnanswered >= 0 ? firstUnanswered : 0;
    }
  }

  Future<void> _answer(int index) async {
    if (_qcms.isEmpty || _submitting) return;
    final qcm = _qcms[_currentQcm];
    if (qcm.answered) return;
    setState(() => _submitting = true);
    try {
      final result = await ClinicalCaseService.instance.submitQcmAnswer(
        qcmId: qcm.id,
        selectedIndex: index,
      );
      if (!mounted) return;
      setState(() {
        _qcms[_currentQcm] = qcm.copyWith(
          correctIndex: result.correctIndex,
          correction: result.correction,
          mySelectedIndex: result.selectedIndex,
          myIsCorrect: result.isCorrect,
          answeredAt: result.answeredAt,
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d’enregistrer cette réponse QCM.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _moveQcm(int delta) {
    if (_qcms.isEmpty) return;
    final next = (_currentQcm + delta).clamp(0, _qcms.length - 1);
    if (next != _currentQcm) setState(() => _currentQcm = next);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final answeredCount = _qcms.where((q) => q.answered).length;
    final correctCount = _qcms.where((q) => q.myIsCorrect == true).length;
    final current = _qcms.isEmpty ? null : _qcms[_currentQcm];
    final answered = current?.answered == true;
    final correct = current?.myIsCorrect == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'CAS #${widget.number.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: AppColors.brandBright,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  post.demographicLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.paperAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _qcms.any((q) => q.generationSource == 'openai')
                          ? Icons.auto_awesome_rounded
                          : Icons.quiz_outlined,
                      size: 12,
                      color: AppColors.brandBright,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _qcms.length >= 5 ? '5 QCM' : 'QCM',
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CaseSection(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Présentation',
            value: post.presentation,
            alwaysShow: true,
          ),
          if (_expanded) ...[
            _CaseSection(
              icon: Icons.history_edu_rounded,
              label: 'Histoire / antécédents',
              value: post.history,
            ),
            _CaseSection(
              icon: Icons.health_and_safety_outlined,
              label: 'Examen clinique',
              value: post.clinicalExam,
            ),
            _CaseSection(
              icon: Icons.biotech_outlined,
              label: 'Examens complémentaires',
              value: post.complementaryExams,
            ),
            _CaseSection(
              icon: Icons.image_search_outlined,
              label: 'Imagerie',
              value: post.imagingConclusion,
            ),
            _CaseSection(
              icon: Icons.psychology_alt_outlined,
              label: 'Synthèse',
              value: post.assessment,
            ),
            _CaseSection(
              icon: Icons.medical_services_outlined,
              label: 'Prise en charge documentée',
              value: post.plan,
            ),
            if (post.disposition.trim().isNotEmpty)
              _CaseSection(
                icon: Icons.alt_route_rounded,
                label: 'Orientation',
                value: post.disposition,
              ),
            if ((post.specialistService ?? '').trim().isNotEmpty)
              _CaseSection(
                icon: Icons.groups_2_outlined,
                label: 'Avis spécialisé',
                value: post.specialistService!,
              ),
          ],
          if (_hasExtraDetails(post))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  _expanded ? 'Réduire le cas' : 'Voir le cas complet',
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (current == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.paperAlt,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brandBright,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Les 5 QCM de ce cas sont en préparation…',
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.paperAlt,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.quiz_rounded,
                        color: AppColors.brandBright,
                        size: 19,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'QCM ${_currentQcm + 1} / ${_qcms.length}',
                        style: TextStyle(
                          color: AppColors.brandBright,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const Spacer(),
                      if (current.generationSource == 'openai') ...[
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.brandBright,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        current.topicLabel,
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    current.question,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 11),
                  for (var index = 0;
                      index < current.options.length;
                      index++) ...[
                    _QcmOption(
                      index: index,
                      label: current.options[index],
                      selected: current.mySelectedIndex == index,
                      showCorrection: answered,
                      isCorrect: current.correctIndex == index,
                      onTap: answered || _submitting
                          ? null
                          : () => _answer(index),
                    ),
                    if (index != current.options.length - 1)
                      const SizedBox(height: 7),
                  ],
                  if (_submitting) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.brandBright,
                      backgroundColor: AppColors.line,
                    ),
                  ],
                ],
              ),
            ),
            if (answered) ...[
              const SizedBox(height: 11),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: (correct ? AppColors.success : AppColors.danger)
                      .withOpacity(0.11),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: (correct ? AppColors.success : AppColors.danger)
                        .withOpacity(0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          correct
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color:
                              correct ? AppColors.success : AppColors.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          correct ? 'Bonne réponse' : 'À revoir',
                          style: TextStyle(
                            color:
                                correct ? AppColors.success : AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.brandBright,
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'EXPLICATION IA',
                          style: TextStyle(
                            color: AppColors.brandBright,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      current.correction.trim().isEmpty
                          ? 'Explication pédagogique en préparation.'
                          : current.correction,
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 11.5,
                        height: 1.46,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  tooltip: 'QCM précédent',
                  onPressed: _currentQcm > 0 ? () => _moveQcm(-1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_qcms.length, (index) {
                      final q = _qcms[index];
                      final active = index == _currentQcm;
                      return GestureDetector(
                        onTap: () => setState(() => _currentQcm = index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: q.myIsCorrect == true
                                ? AppColors.success
                                : q.answered
                                    ? AppColors.danger
                                    : active
                                        ? AppColors.brandBright
                                        : AppColors.line,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                IconButton(
                  tooltip: 'QCM suivant',
                  onPressed: _currentQcm < _qcms.length - 1
                      ? () => _moveQcm(1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Center(
              child: Text(
                '$answeredCount / ${_qcms.length} répondus · $correctCount justes',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static bool _hasExtraDetails(ClinicalCasePost post) => <String>[
        post.history,
        post.clinicalExam,
        post.complementaryExams,
        post.imagingConclusion,
        post.assessment,
        post.plan,
        post.disposition,
        post.specialistService ?? '',
      ].any((value) => value.trim().isNotEmpty);
}
'''
text = text[:start] + new_card_state + text[end:]
path.write_text(text, encoding='utf-8')

# ---------------------------------------------------------------------------
# Practice service — push on new case, milestones, goals, levels, streaks,
# and newly unlocked achievements. Never block the clinical save on push.
# ---------------------------------------------------------------------------
path = Path('source/lib/services/practice_service.dart')
text = path.read_text(encoding='utf-8')
old = '''  Future<PracticeCase> _saveRemote(PracticeCase value) async {
    final payload = value.toMap(includeId: false)
      ..['is_draft'] = false
      ..['synced_at'] = DateTime.now().toUtc().toIso8601String();
    dynamic response;
    if (value.id == null || value.id!.isEmpty) {
      response = await _backend.client.from('practice_cases').insert(payload).select().single();
    } else {
      response = await _backend.client
          .from('practice_cases')
          .update(payload)
          .eq('id', value.id!)
          .select()
          .single();
    }
    final saved = PracticeCase.fromMap(Map<String, dynamic>.from(response as Map));
    final savedId = saved.id?.trim() ?? '';
    if (savedId.isNotEmpty) {
      ClinicalCaseService.instance.notifyChanged();
      unawaited(ClinicalCaseService.instance.enrichQcmForPracticeCase(savedId));
    }
    return saved;
  }
'''
new = '''  Future<PracticeCase> _saveRemote(PracticeCase value) async {
    final isNew = value.id == null || value.id!.isEmpty;
    final activityStartedAt = DateTime.now();
    PracticeStats? beforeAll;
    if (isNew) {
      try {
        beforeAll = await summary(scope: 'all');
      } catch (_) {}
    }

    final payload = value.toMap(includeId: false)
      ..['is_draft'] = false
      ..['synced_at'] = DateTime.now().toUtc().toIso8601String();
    dynamic response;
    if (isNew) {
      response = await _backend.client
          .from('practice_cases')
          .insert(payload)
          .select()
          .single();
    } else {
      response = await _backend.client
          .from('practice_cases')
          .update(payload)
          .eq('id', value.id!)
          .select()
          .single();
    }
    final saved = PracticeCase.fromMap(Map<String, dynamic>.from(response as Map));
    final savedId = saved.id?.trim() ?? '';
    if (savedId.isNotEmpty) {
      ClinicalCaseService.instance.notifyChanged();
      unawaited(ClinicalCaseService.instance.enrichQcmForPracticeCase(savedId));
      if (isNew) {
        unawaited(_notifyAfterNewCase(saved, beforeAll, activityStartedAt));
      }
    }
    return saved;
  }

  Future<void> _notifyAfterNewCase(
    PracticeCase saved,
    PracticeStats? beforeAll,
    DateTime activityStartedAt,
  ) async {
    final savedId = saved.id?.trim() ?? '';
    if (savedId.isEmpty || !_backend.enabled || _authUserId == null) return;

    await _triggerPracticePush('practice_case_created', savedId);
    await _triggerPracticePush('practice_goal_reached', saved.guardId);
    await _triggerPracticePush('practice_case_milestone', savedId);

    try {
      final afterAll = await summary(scope: 'all');
      if (beforeAll != null) {
        if (practiceLevelForXp(afterAll.xp).number >
            practiceLevelForXp(beforeAll.xp).number) {
          await _triggerPracticePush('practice_level_up', savedId);
        }
        if (afterAll.streak > beforeAll.streak && afterAll.streak >= 3) {
          await _triggerPracticePush('practice_streak', savedId);
        }
      }
    } catch (_) {}

    try {
      final rows = await achievements();
      for (final achievement in rows) {
        final unlockedAt = achievement.unlockedAt;
        if (unlockedAt == null) continue;
        if (unlockedAt.isAfter(
          activityStartedAt.subtract(const Duration(seconds: 5)),
        )) {
          await _triggerPracticePush(
            'practice_achievement_unlocked',
            achievement.key,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _triggerPracticePush(String kind, String resourceId) async {
    try {
      await _backend.triggerPush(kind, resourceId);
    } catch (_) {
      // La notification est best-effort et ne doit jamais transformer un
      // enregistrement clinique réussi en erreur visible pour l'utilisateur.
    }
  }
'''
text = replace_once(text, old, new, 'practice _saveRemote')

old_sync = '''        final insertedId = '${inserted['id'] ?? ''}'.trim();
        await _removePending(item.clientId);
        ClinicalCaseService.instance.notifyChanged();
        if (insertedId.isNotEmpty) {
          unawaited(ClinicalCaseService.instance.enrichQcmForPracticeCase(insertedId));
        }
        synced++;
'''
new_sync = '''        final insertedId = '${inserted['id'] ?? ''}'.trim();
        await _removePending(item.clientId);
        ClinicalCaseService.instance.notifyChanged();
        if (insertedId.isNotEmpty) {
          final syncedCase = item.copyWith(id: insertedId, pendingSync: false);
          unawaited(ClinicalCaseService.instance.enrichQcmForPracticeCase(insertedId));
          unawaited(
            _notifyAfterNewCase(
              syncedCase,
              null,
              DateTime.now(),
            ),
          );
        }
        synced++;
'''
text = replace_once(text, old_sync, new_sync, 'practice pending sync')
path.write_text(text, encoding='utf-8')

# ---------------------------------------------------------------------------
# Push navigation — Practice notifications open Practice directly.
# ---------------------------------------------------------------------------
path = Path('source/lib/services/push_notification_service.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import '../screens/notifications_screen.dart';\n",
    "import '../screens/notifications_screen.dart';\nimport '../screens/practice_screen.dart';\nimport '../state/app_state.dart';\n",
    'push imports',
)
text = replace_once(
    text,
    '  bool _isAdmin = false;\n  String? _pendingKind;\n',
    '  bool _isAdmin = false;\n  AppState? _appState;\n  String? _pendingKind;\n',
    'push app state field',
)
text = replace_once(
    text,
    '''  void navigationReady({required bool isAdmin}) {
    _navigationReady = true;
    _isAdmin = isAdmin;
    final kind = _pendingKind;
''',
    '''  void navigationReady({required bool isAdmin, AppState? appState}) {
    _navigationReady = true;
    _isAdmin = isAdmin;
    _appState = appState ?? _appState;
    final kind = _pendingKind;
''',
    'push navigationReady',
)
text = replace_once(
    text,
    '''    if (kind == 'announcement_created') {
''',
    '''    if (kind.startsWith('practice_') && _appState != null) {
      huimNavigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => PracticeScreen(appState: _appState!),
        ),
      );
      return;
    }
    if (kind == 'announcement_created') {
''',
    'push Practice route',
)
path.write_text(text, encoding='utf-8')

# ---------------------------------------------------------------------------
# Home shell — pass AppState to notification deep-link routing and clean the
# accidental duplicate Practice imports.
# ---------------------------------------------------------------------------
path = Path('source/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')
text = re.sub(r"(?:import 'practice_screen\.dart';\n){2,}", "import 'practice_screen.dart';\n", text)
text = replace_once(
    text,
    '''          PushNotificationService.instance.navigationReady(
            isAdmin: appState.currentUser!.role == UserRole.admin,
          );
''',
    '''          PushNotificationService.instance.navigationReady(
            isAdmin: appState.currentUser!.role == UserRole.admin,
            appState: appState,
          );
''',
    'home push routing',
)
path.write_text(text, encoding='utf-8')

# ---------------------------------------------------------------------------
# Local notifications — dedicated Practice channel + scheduled start/mid/end.
# ---------------------------------------------------------------------------
path = Path('source/lib/services/notification_service.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "  static const pushChannelId = 'huim6_push';\n",
    "  static const pushChannelId = 'huim6_push';\n  static const practiceChannelId = 'gardeflow_practice_v1';\n",
    'practice channel const',
)
text = replace_once(
    text,
    '''        await android.createNotificationChannel(const AndroidNotificationChannel(
          pushChannelId,
          'Échanges et congés',
          description: 'Demandes, validations et événements du planning',
          importance: Importance.high,
        ));
''',
    '''        await android.createNotificationChannel(const AndroidNotificationChannel(
          pushChannelId,
          'Échanges et congés',
          description: 'Demandes, validations et événements du planning',
          importance: Importance.high,
        ));
        await android.createNotificationChannel(const AndroidNotificationChannel(
          practiceChannelId,
          'Practice',
          description: 'Cas cliniques, progression, succès et encouragements de garde',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ));
''',
    'practice channel create',
)

show_start = text.find('  Future<void> showPush({required String title, required String body, required String kind}) async {')
show_end = text.find('\n  /// Demande uniquement', show_start)
if show_start < 0 or show_end < 0:
    raise SystemExit('showPush boundaries not found')
new_show = r'''  Future<void> showPush({
    required String title,
    required String body,
    required String kind,
  }) async {
    if (kIsWeb) return;
    if (!await _ensureInitialized()) return;
    try {
      final practice = kind.startsWith('practice_');
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          practice ? practiceChannelId : pushChannelId,
          practice ? 'Practice' : 'Échanges et congés',
          channelDescription: practice
              ? 'Cas cliniques, progression, succès et encouragements de garde'
              : 'Demandes, validations et événements du planning',
          icon: 'ic_stat_huim6',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      await _plugin.show(
        (DateTime.now().microsecondsSinceEpoch & 0x3fffffff) | 0x40000000,
        title,
        body,
        details,
        payload: 'push:$kind',
      );
    } catch (e) {
      debugPrint('Notification push locale ignorée: $e');
    }
  }

  Future<void> schedulePracticeMoment({
    required String ownerPhone,
    required String guardId,
    required String kind,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async {
    if (kIsWeb || !fireAt.isAfter(DateTime.now())) return;
    if (!await _ensureInitialized()) return;
    final id = _idFor(ownerPhone, 'practice:$guardId:$kind');
    final scheduled = _moroccoTime(fireAt);
    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        practiceChannelId,
        'Practice',
        channelDescription:
            'Cas cliniques, progression, succès et encouragements de garde',
        icon: 'ic_stat_huim6',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        payload: 'push:$kind',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Programmation Practice ignorée: $e');
    }
  }
'''
text = text[:show_start] + new_show + text[show_end:]
text = replace_once(
    text,
    '''        if (!payload.startsWith('guard:')) continue;
''',
    '''        if (!payload.startsWith('guard:') &&
            !payload.startsWith('push:practice_guard_')) {
          continue;
        }
''',
    'cancel Practice scheduled notifications',
)
path.write_text(text, encoding='utf-8')

# ---------------------------------------------------------------------------
# AppState — schedule start, midpoint and end encouragements for upcoming
# emergency guards. Use PracticeGuard semantics for night guards.
# ---------------------------------------------------------------------------
path = Path('source/lib/state/app_state.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import '../models/planning_month.dart';\n",
    "import '../models/planning_month.dart';\nimport '../models/practice_models.dart';\n",
    'app state Practice import',
)
needle = '''  Future<void> rescheduleAllReminders() async {
'''
insert = r'''  Future<void> _schedulePracticeGuardMomentsForCurrentUser() async {
    final me = currentUser;
    if (me == null || !_notificationsOn || kIsWeb) return;

    final now = DateTime.now();
    final guards = <PracticeGuard>[];
    for (final entry in _planning) {
      if (entry.ownerId != me.id && entry.ownerPhone != me.phone) continue;
      if (!isPlanningEntryApproved(entry)) continue;
      final guard = PracticeGuard.fromEntry(entry);
      if (guard == null || !guard.end.isAfter(now)) continue;
      guards.add(guard);
    }
    guards.sort((a, b) => a.start.compareTo(b.start));

    final maxGuards = defaultTargetPlatform == TargetPlatform.iOS ? 2 : 8;
    for (final guard in guards.take(maxGuards)) {
      final duration = guard.end.difference(guard.start);
      final midpoint = guard.start.add(
        Duration(minutes: duration.inMinutes ~/ 2),
      );

      await NotificationService.instance.schedulePracticeMoment(
        ownerPhone: me.phone,
        guardId: guard.id,
        kind: 'practice_guard_start',
        title: 'Practice · Bonne garde',
        body:
            'Votre garde aux Urgences commence. Documentez vos cas au fil de la garde et progressez dans Practice.',
        fireAt: guard.start,
      );
      await NotificationService.instance.schedulePracticeMoment(
        ownerPhone: me.phone,
        guardId: guard.id,
        kind: 'practice_guard_midpoint',
        title: 'Practice · Point de garde',
        body:
            'Vous êtes à mi-garde. Pensez à documenter les cas vus : quelques secondes maintenant évitent les oublis en fin de garde.',
        fireAt: midpoint,
      );
      await NotificationService.instance.schedulePracticeMoment(
        ownerPhone: me.phone,
        guardId: guard.id,
        kind: 'practice_guard_end',
        title: 'Practice · Fin de garde',
        body:
            'Garde terminée. Consultez votre bilan, vos XP, vos succès et les 5 QCM générés pour chaque cas clinique.',
        fireAt: guard.end,
      );
    }
  }

'''
if needle not in text:
    raise SystemExit('rescheduleAllReminders marker not found')
text = text.replace(needle, insert + needle, 1)
text = replace_once(
    text,
    '''    for (final r in upcoming.take(limit)) {
      await _scheduleNativeReminder(r);
    }
  }
''',
    '''    for (final r in upcoming.take(limit)) {
      await _scheduleNativeReminder(r);
    }
    await _schedulePracticeGuardMomentsForCurrentUser();
  }
''',
    'activate Practice moments',
)
path.write_text(text, encoding='utf-8')

print('Practice QCM5 + notifications client integration applied.')
