import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/intern_promotions.dart';
import '../models/directory_contact.dart';
import '../models/planning_entry.dart';
import '../models/shift_type.dart';
import '../services/supabase_backend_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class AnnouncementsScreen extends StatefulWidget {
  final String? initialEntryId;
  final bool autoOpenComposer;

  const AnnouncementsScreen({
    super.key,
    this.initialEntryId,
    this.autoOpenComposer = false,
  });

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late Future<List<_Announcement>> _future;
  StreamSubscription? _realtime;
  bool _composerOpened = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    final client = SupabaseBackendService.instance.client;
    _realtime = client
        .from('public_announcements')
        .stream(primaryKey: ['id'])
        .listen((_) => _reload(silent: true), onError: (_) {});
    if (widget.autoOpenComposer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openComposer());
    }
  }

  @override
  void dispose() {
    _realtime?.cancel();
    super.dispose();
  }

  Future<List<_Announcement>> _load() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final rows = await SupabaseBackendService.instance.client
        .from('public_announcements')
        .select()
        .isFilter('closed_at', null)
        .gte('date_str', today)
        .order('created_at', ascending: false)
        .limit(150);
    return (rows as List)
        .map((e) => _Announcement.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false);
  }

  Future<void> _reload({bool silent = false}) async {
    if (!mounted) return;
    final next = _load();
    setState(() => _future = next);
    if (!silent) await next;
  }

  List<PlanningEntry> _myPublishableEntries(AppState state) {
    final me = state.currentUser;
    if (me == null) return const [];
    final result = state.planning.where((entry) {
      if (entry.ownerId != me.id && entry.ownerPhone != me.phone) return false;
      if (entry.isDisciplinary || entry.shiftId == 'conge') return false;
      if (!ShiftCatalog.byId(entry.shiftId).hasSchedule) return false;
      if (!state.isPlanningEntryApproved(entry)) return false;
      return !state.guardHasStarted(entry);
    }).toList()
      ..sort((a, b) => a.dateStr.compareTo(b.dateStr));
    return result;
  }

  Future<void> _openComposer() async {
    if (_composerOpened || !mounted) return;
    _composerOpened = true;
    final state = context.read<AppState>();
    final me = state.currentUser;
    final entries = _myPublishableEntries(state);
    if (me == null || entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune garde future validée disponible à publier.'),
        ),
      );
      _composerOpened = false;
      return;
    }

    var selectedId = widget.initialEntryId != null &&
            entries.any((e) => e.id == widget.initialEntryId)
        ? widget.initialEntryId!
        : entries.first.id;
    final controller = TextEditingController();
    var sending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final selected = entries.firstWhere((e) => e.id == selectedId);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              2,
              18,
              18 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Publier une annonce d’échange',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  'L’annonce est visible dans le fil. Pour une garde d’Urgences, la notification reste limitée à votre promotion ; pour une garde de Service, Promo 6 et Promo 7 peuvent répondre.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Garde à échanger'),
                  items: entries.map((entry) {
                    final shift = ShiftCatalog.byId(entry.shiftId);
                    final date = DateFormat('EEE d MMM yyyy', 'fr_FR')
                        .format(DateTime.parse(entry.dateStr));
                    return DropdownMenuItem(
                      value: entry.id,
                      child: Text('$date · ${shift.label}', overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: sending
                      ? null
                      : (value) {
                          if (value != null) setSheetState(() => selectedId = value);
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  enabled: !sending,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 280,
                  decoration: const InputDecoration(
                    labelText: 'Message (facultatif)',
                    hintText: 'Ex. Je cherche une garde de nuit en échange…',
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: sending
                        ? null
                        : () async {
                            setSheetState(() => sending = true);
                            final id = 'an${DateTime.now().microsecondsSinceEpoch}';
                            try {
                              await SupabaseBackendService.instance.client
                                  .from('public_announcements')
                                  .insert({
                                'id': id,
                                'author_id': me.id,
                                'author_name': me.fullName,
                                'hospital': me.hospital,
                                'promotion_number': InternPromotions.numberFor(me),
                                'planning_entry_id': selected.id,
                                'date_str': selected.dateStr,
                                'shift_id': selected.shiftId,
                                'message': controller.text.trim(),
                              });
                              try {
                                await SupabaseBackendService.instance
                                    .triggerPush('announcement_created', id);
                              } catch (_) {
                                // L'annonce reste publiée même si un appareil push
                                // est momentanément indisponible.
                              }
                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext);
                            } catch (e) {
                              if (!sheetContext.mounted) return;
                              setSheetState(() => sending = false);
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(content: Text('Publication impossible : $e')),
                              );
                            }
                          },
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.campaign_rounded),
                    label: Text(sending ? 'Publication…' : 'Publier dans le fil'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    controller.dispose();
    _composerOpened = false;
    if (mounted) await _reload(silent: true);
  }

  Future<void> _close(_Announcement announcement) async {
    await SupabaseBackendService.instance.client
        .from('public_announcements')
        .update({'closed_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', announcement.id);
    if (mounted) await _reload(silent: true);
  }

  Future<void> _proposeExchange(_Announcement announcement) async {
    final state = context.read<AppState>();
    final me = state.currentUser;
    if (me == null) return;
    final author = state.users
        .where((u) => u.id == announcement.authorId)
        .firstOrNull;
    final targetEntry = state.planning
        .where((e) => e.id == announcement.planningEntryId)
        .firstOrNull;
    if (author == null || targetEntry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette garde n’est plus disponible.')),
      );
      return;
    }
    if (state.promotionExchangeBlocked(me, author)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La promotion de première année (Promo ${state.currentFirstYearPromotion}) ne peut échanger des gardes qu’avec la même promotion.',
          ),
        ),
      );
      return;
    }
    if (me.hospital != author.hospital) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les échanges restent limités au même hôpital.')),
      );
      return;
    }

    final mine = _myPublishableEntries(state)
        .where((e) => e.id != targetEntry.id)
        .toList();
    if (mine.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous n’avez aucune garde validée disponible à proposer.')),
      );
      return;
    }

    var selectedId = mine.first.id;
    String? error;
    var sending = false;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Proposer un échange à ${announcement.authorName}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choisissez la garde que vous proposez en contrepartie.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Votre garde proposée'),
                  items: mine.map((entry) {
                    final shift = ShiftCatalog.byId(entry.shiftId);
                    final date = DateFormat('EEE d MMM yyyy', 'fr_FR')
                        .format(DateTime.parse(entry.dateStr));
                    return DropdownMenuItem(
                      value: entry.id,
                      child: Text('$date · ${shift.label}', overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: sending
                      ? null
                      : (value) {
                          if (value != null) {
                            setSheetState(() {
                              selectedId = value;
                              error = null;
                            });
                          }
                        },
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: sending
                        ? null
                        : () async {
                            setSheetState(() => sending = true);
                            final source = mine.firstWhere((e) => e.id == selectedId);
                            final contact = DirectoryContact(
                              id: author.id,
                              name: author.fullName,
                              phone: author.phone,
                              hospital: author.hospital,
                              service: author.service,
                              gradeLabel: author.gradeLabel,
                              isAdmin: author.role.name == 'admin',
                            );
                            final result = await state.createSwapRequest(
                              source.dateStr,
                              source,
                              contact,
                              targetEntry,
                            );
                            if (!sheetContext.mounted) return;
                            if (result != null) {
                              setSheetState(() {
                                sending = false;
                                error = result;
                              });
                              return;
                            }
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Demande d’échange envoyée.')),
                            );
                          },
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: Text(sending ? 'Envoi…' : 'Envoyer la proposition'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.currentUser;
    final myPromotion = InternPromotions.labelFor(
      me,
      firstYearPromotion: state.currentFirstYearPromotion,
    );

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        title: const Text('Annonces & échanges'),
        actions: [
          IconButton(
            tooltip: 'Publier une annonce',
            onPressed: _openComposer,
            icon: const Icon(Icons.add_comment_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openComposer,
        icon: const Icon(Icons.campaign_rounded),
        label: const Text('Publier'),
      ),
      body: FutureBuilder<List<_Announcement>>(
        future: _future,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <_Announcement>[];
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(15),
                  shadow: const [],
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.brandSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.forum_rounded, color: AppColors.brand),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Fil public des gardes',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              myPromotion == null
                                  ? 'Publiez une garde et trouvez un collègue pour l’échanger.'
                                  : '$myPromotion · Urgences : même promo · Service : interpromo autorisé.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (snapshot.connectionState == ConnectionState.waiting && items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError && items.isEmpty)
                  _InfoState(
                    icon: Icons.cloud_off_rounded,
                    text: 'Le fil est momentanément indisponible. Tirez pour actualiser.',
                  )
                else if (items.isEmpty)
                  _InfoState(
                    icon: Icons.mark_chat_unread_outlined,
                    text: 'Aucune annonce active pour le moment.',
                  )
                else
                  for (final item in items) ...[
                    _AnnouncementCard(
                      announcement: item,
                      meId: me?.id,
                      blocked: _blockedForViewer(state, item),
                      onClose: () => _close(item),
                      onExchange: () => _proposeExchange(item),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }

  bool _blockedForViewer(AppState state, _Announcement item) {
    final me = state.currentUser;
    if (me == null || me.id == item.authorId) return false;
    final author = state.users.where((u) => u.id == item.authorId).firstOrNull;
    if (author != null && state.promotionExchangeBlocked(me, author)) {
      return true;
    }
    return me.hospital != item.hospital;
  }
}

class _AnnouncementCard extends StatelessWidget {
  final _Announcement announcement;
  final String? meId;
  final bool blocked;
  final VoidCallback onClose;
  final VoidCallback onExchange;

  const _AnnouncementCard({
    required this.announcement,
    required this.meId,
    required this.blocked,
    required this.onClose,
    required this.onExchange,
  });

  @override
  Widget build(BuildContext context) {
    final own = announcement.authorId == meId;
    final shift = ShiftCatalog.byId(announcement.shiftId);
    final date = DateFormat('EEEE d MMMM yyyy', 'fr_FR')
        .format(DateTime.parse(announcement.dateStr));
    final promo = announcement.promotionNumber == 7
        ? '1re année · Promo 7'
        : announcement.promotionNumber == 6
            ? '2e année · Promo 6'
            : null;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: AppColors.brandSoft,
                child: Text(
                  announcement.authorName.trim().isEmpty
                      ? '?'
                      : announcement.authorName.trim()[0].toUpperCase(),
                  style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      announcement.authorName,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    Text(
                      [
                        if (promo != null) promo,
                        announcement.hospital,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                _relative(announcement.createdAt),
                style: TextStyle(color: AppColors.inkFaint, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: shift.color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(shift.icon, color: shift.textColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shift.label,
                        style: TextStyle(color: shift.textColor, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date,
                        style: TextStyle(color: shift.textColor.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (announcement.message.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              announcement.message.trim(),
              style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 14),
          if (own)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Retirer mon annonce'),
              ),
            )
          else if (blocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.paperAlt,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.line),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 17),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Échange non disponible : hôpital ou promotion différente.',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onExchange,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Proposer un échange'),
              ),
            ),
        ],
      ),
    );
  }

  static String _relative(DateTime date) {
    final d = DateTime.now().difference(date.toLocal());
    if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} min';
    if (d.inHours < 24) return '${d.inHours} h';
    if (d.inDays == 1) return 'Hier';
    return '${d.inDays} j';
  }
}

class _InfoState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 44, color: AppColors.inkFaint),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}

class _Announcement {
  final String id;
  final String authorId;
  final String authorName;
  final String hospital;
  final int? promotionNumber;
  final String planningEntryId;
  final String dateStr;
  final String shiftId;
  final String message;
  final DateTime createdAt;

  const _Announcement({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.hospital,
    required this.promotionNumber,
    required this.planningEntryId,
    required this.dateStr,
    required this.shiftId,
    required this.message,
    required this.createdAt,
  });

  factory _Announcement.fromMap(Map<String, dynamic> row) => _Announcement(
        id: row['id'].toString(),
        authorId: row['author_id'].toString(),
        authorName: (row['author_name'] ?? '').toString(),
        hospital: (row['hospital'] ?? '').toString(),
        promotionNumber: (row['promotion_number'] as num?)?.toInt(),
        planningEntryId: row['planning_entry_id'].toString(),
        dateStr: row['date_str'].toString(),
        shiftId: row['shift_id'].toString(),
        message: (row['message'] ?? '').toString(),
        createdAt: DateTime.parse(row['created_at'].toString()),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
