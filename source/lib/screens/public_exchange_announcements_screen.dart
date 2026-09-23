import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/directory_contact.dart';
import '../models/planning_entry.dart';
import '../models/shift_type.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class PublicExchangeAnnouncementsScreen extends StatelessWidget {
  const PublicExchangeAnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text(
          'Annonces de garde',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: PublicExchangeAnnouncementsSection(compact: false),
        ),
      ),
    );
  }
}

class PublicExchangeAnnouncementsSection extends StatefulWidget {
  final bool compact;

  const PublicExchangeAnnouncementsSection({
    super.key,
    this.compact = true,
  });

  @override
  State<PublicExchangeAnnouncementsSection> createState() =>
      _PublicExchangeAnnouncementsSectionState();
}

class _PublicExchangeAnnouncementsSectionState
    extends State<PublicExchangeAnnouncementsSection> {
  SupabaseClient get _client => Supabase.instance.client;

  Stream<List<Map<String, dynamic>>> _stream() => _client
      .from('public_exchange_announcements')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);

  Future<void> _openPublishSheet() async {
    final state = context.read<AppState>();
    final me = state.currentUser;
    if (me == null) return;

    final available = state.exchangeableEntriesFor(me.id);
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aucune garde validée et échangeable n’est disponible à publier.',
          ),
        ),
      );
      return;
    }

    final published = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PublishAnnouncementSheet(entries: available),
    );

    if (!mounted || published != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Annonce publiée dans le fil public.')),
    );
  }

  Future<void> _closeAnnouncement(_PublicAnnouncement item) async {
    try {
      final me = context.read<AppState>().currentUser;
      if (me == null || item.authorId != me.id) return;
      await _client
          .from('public_exchange_announcements')
          .update({'status': 'closed'})
          .eq('id', item.id)
          .eq('author_id', me.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Annonce retirée du fil public.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de fermer l’annonce : $e')),
      );
    }
  }

  Future<void> _offerExchange(_PublicAnnouncement item) async {
    final state = context.read<AppState>();
    final me = state.currentUser;
    if (me == null) return;
    if (item.authorId == me.id) return;

    if (item.hospital != me.hospital) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Un échange de garde reste limité aux médecins du même établissement.',
          ),
        ),
      );
      return;
    }

    final targetUser = state.users
        .where((user) => user.id == item.authorId)
        .firstOrNull;
    if (targetUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le médecin auteur n’est plus disponible.')),
      );
      return;
    }

    final ownEntries = state.exchangeableEntriesFor(me.id);
    if (ownEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vous n’avez aucune garde validée disponible à proposer en échange.',
          ),
        ),
      );
      return;
    }

    final contact = DirectoryContact(
      id: targetUser.id,
      name: targetUser.fullName,
      phone: targetUser.phone,
      hospital: targetUser.hospital,
      service: targetUser.service,
      gradeLabel: targetUser.gradeLabel,
      isAdmin: targetUser.role.name == 'admin',
    );

    final targetEntry = state.planning
            .where((entry) => entry.id == item.planningEntryId)
            .firstOrNull ??
        PlanningEntry(
          id: item.planningEntryId,
          dateStr: item.dateStr,
          shiftId: item.shiftId,
          ownerId: targetUser.id,
          ownerPhone: targetUser.phone,
          ownerName: targetUser.fullName,
        );

    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OfferExchangeSheet(
        announcement: item,
        ownEntries: ownEntries,
        target: contact,
        targetEntry: targetEntry,
      ),
    );

    if (!mounted || sent != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Proposition d’échange envoyée à ${item.authorName}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().currentUser;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream(),
      builder: (context, snapshot) {
        final announcements = (snapshot.data ?? const <Map<String, dynamic>>[])
            .map(_PublicAnnouncement.fromMap)
            .where((item) => item.status == 'active')
            .toList();
        final shown = widget.compact
            ? announcements.take(3).toList()
            : announcements;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.campaign_rounded,
                    color: AppColors.brand,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Annonces de garde',
                        style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          color: AppColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.35,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Fil public pour proposer une garde à échanger',
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: me == null ? null : _openPublishSheet,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Publier'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (snapshot.connectionState == ConnectionState.waiting &&
                announcements.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            else if (snapshot.hasError && announcements.isEmpty)
              _AnnouncementInfoCard(
                icon: Icons.cloud_off_rounded,
                text: 'Le fil d’annonces est momentanément indisponible.',
              )
            else if (announcements.isEmpty)
              _AnnouncementInfoCard(
                icon: Icons.forum_outlined,
                text:
                    'Aucune annonce active. Publiez une garde pour trouver un échange.',
              )
            else ...[
              for (var i = 0; i < shown.length; i++) ...[
                _AnnouncementCard(
                  item: shown[i],
                  isMine: me?.id == shown[i].authorId,
                  canOffer: me != null &&
                      me.id != shown[i].authorId &&
                      me.hospital == shown[i].hospital,
                  onOffer: () => _offerExchange(shown[i]),
                  onClose: () => _closeAnnouncement(shown[i]),
                ),
                if (i != shown.length - 1) const SizedBox(height: 11),
              ],
              if (widget.compact && announcements.length > shown.length) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const PublicExchangeAnnouncementsScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.forum_rounded, size: 18),
                    label: Text(
                      'Voir toutes les annonces (${announcements.length})',
                    ),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _PublishAnnouncementSheet extends StatefulWidget {
  final List<PlanningEntry> entries;

  const _PublishAnnouncementSheet({required this.entries});

  @override
  State<_PublishAnnouncementSheet> createState() =>
      _PublishAnnouncementSheetState();
}

class _PublishAnnouncementSheetState
    extends State<_PublishAnnouncementSheet> {
  final _messageController = TextEditingController();
  String? _entryId;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.entries.isNotEmpty) _entryId = widget.entries.first.id;
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_sending) return;
    final state = context.read<AppState>();
    final me = state.currentUser;
    final selected = widget.entries
        .where((entry) => entry.id == _entryId)
        .firstOrNull;
    if (me == null || selected == null) {
      setState(() => _error = 'Sélectionnez une garde à publier.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final row = await Supabase.instance.client
          .from('public_exchange_announcements')
          .insert({
            'author_id': me.id,
            'planning_entry_id': selected.id,
            'message': _messageController.text.trim(),
          })
          .select('id')
          .single();

      final id = row['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        try {
          await Supabase.instance.client.functions.invoke(
            'send-push',
            body: {
              'kind': 'public_announcement_created',
              'resourceId': id,
            },
          );
        } catch (_) {
          // L’annonce reste publiée même si un appareil ou FCM est
          // momentanément indisponible.
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _sending = false;
        _error = raw.contains('public_exchange_announcements_one_active')
            ? 'Une annonce active existe déjà pour cette garde.'
            : 'Publication impossible : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          4,
          18,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Publier une annonce publique',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choisissez une garde validée. Tous les médecins pourront voir l’annonce et les appareils ayant activé les notifications recevront une alerte.',
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: _entryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Garde proposée à l’échange',
              ),
              items: widget.entries.map((entry) {
                final shift = ShiftCatalog.byId(entry.shiftId);
                final category =
                    entry.shiftId.startsWith('urg-') ? 'Urgences' : 'Service';
                final date = DateFormat('EEE d MMM yyyy', 'fr_FR')
                    .format(DateTime.parse(entry.dateStr));
                return DropdownMenuItem(
                  value: entry.id,
                  child: Text(
                    '$date · $category ${shift.label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _sending
                  ? null
                  : (value) => setState(() {
                        _entryId = value;
                        _error = null;
                      }),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _messageController,
              enabled: !_sending,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Message (facultatif)',
                hintText:
                    'Ex. Je cherche de préférence une garde la semaine suivante.',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _publish,
                icon: _sending
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.campaign_rounded),
                label: Text(_sending ? 'Publication…' : 'Publier l’annonce'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferExchangeSheet extends StatefulWidget {
  final _PublicAnnouncement announcement;
  final List<PlanningEntry> ownEntries;
  final DirectoryContact target;
  final PlanningEntry targetEntry;

  const _OfferExchangeSheet({
    required this.announcement,
    required this.ownEntries,
    required this.target,
    required this.targetEntry,
  });

  @override
  State<_OfferExchangeSheet> createState() => _OfferExchangeSheetState();
}

class _OfferExchangeSheetState extends State<_OfferExchangeSheet> {
  String? _entryId;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.ownEntries.isNotEmpty) _entryId = widget.ownEntries.first.id;
  }

  Future<void> _send() async {
    final own = widget.ownEntries
        .where((entry) => entry.id == _entryId)
        .firstOrNull;
    if (own == null) {
      setState(() => _error = 'Sélectionnez la garde que vous proposez.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    final state = context.read<AppState>();
    final error = await state.createSwapRequest(
      own.dateStr,
      own,
      widget.target,
      widget.targetEntry,
    );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _sending = false;
        _error = error;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final offeredShift = ShiftCatalog.byId(widget.announcement.shiftId);
    final offeredCategory = widget.announcement.shiftId.startsWith('urg-')
        ? 'Urgences'
        : 'Service';
    final offeredDate = DateFormat('EEE d MMM yyyy', 'fr_FR')
        .format(DateTime.parse(widget.announcement.dateStr));

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          4,
          18,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Proposer un échange',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(
                '${widget.announcement.authorName} propose : $offeredDate · $offeredCategory ${offeredShift.label}',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _entryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Votre garde proposée',
              ),
              items: widget.ownEntries.map((entry) {
                final shift = ShiftCatalog.byId(entry.shiftId);
                final category =
                    entry.shiftId.startsWith('urg-') ? 'Urgences' : 'Service';
                final date = DateFormat('EEE d MMM yyyy', 'fr_FR')
                    .format(DateTime.parse(entry.dateStr));
                return DropdownMenuItem(
                  value: entry.id,
                  child: Text(
                    '$date · $category ${shift.label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _sending
                  ? null
                  : (value) => setState(() {
                        _entryId = value;
                        _error = null;
                      }),
            ),
            const SizedBox(height: 10),
            Text(
              'La proposition utilisera les règles d’échange GardeFlow déjà en place (établissement, service et validations nécessaires).',
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.swap_horiz_rounded),
                label: Text(
                  _sending ? 'Envoi…' : 'Envoyer la proposition d’échange',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final _PublicAnnouncement item;
  final bool isMine;
  final bool canOffer;
  final VoidCallback onOffer;
  final VoidCallback onClose;

  const _AnnouncementCard({
    required this.item,
    required this.isMine,
    required this.canOffer,
    required this.onOffer,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final shift = ShiftCatalog.byId(item.shiftId);
    final category = item.shiftId.startsWith('urg-') ? 'Urgences' : 'Service';
    final date = DateFormat('EEEE d MMMM yyyy', 'fr_FR')
        .format(DateTime.parse(item.dateStr));
    final created = _relativeDate(item.createdAt.toLocal());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.045),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.brandSoft,
                child: Icon(
                  Icons.person_rounded,
                  color: AppColors.brand,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.hospital} · ${item.service}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                created,
                style: TextStyle(
                  color: AppColors.inkFaint,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: shift.color,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(shift.icon, size: 18, color: shift.textColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$date · $category ${shift.label}',
                    style: TextStyle(
                      color: shift.textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Text(
            item.message,
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 13),
          if (isMine)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Fermer mon annonce'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canOffer ? onOffer : null,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(
                  canOffer
                      ? 'Proposer un échange'
                      : 'Échange non disponible pour cet établissement',
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _relativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'À l’instant';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    return DateFormat('d MMM', 'fr_FR').format(date);
  }
}

class _AnnouncementInfoCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AnnouncementInfoCard({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.brand, size: 23),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicAnnouncement {
  final String id;
  final String authorId;
  final String authorName;
  final String authorPhone;
  final String hospital;
  final String service;
  final String planningEntryId;
  final String dateStr;
  final String shiftId;
  final String message;
  final String status;
  final DateTime createdAt;

  const _PublicAnnouncement({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhone,
    required this.hospital,
    required this.service,
    required this.planningEntryId,
    required this.dateStr,
    required this.shiftId,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  factory _PublicAnnouncement.fromMap(Map<String, dynamic> map) {
    return _PublicAnnouncement(
      id: map['id']?.toString() ?? '',
      authorId: map['author_id']?.toString() ?? '',
      authorName: map['author_name']?.toString() ?? 'Médecin',
      authorPhone: map['author_phone']?.toString() ?? '',
      hospital: map['hospital']?.toString() ?? '',
      service: map['service']?.toString() ?? '',
      planningEntryId: map['planning_entry_id']?.toString() ?? '',
      dateStr: map['date_str']?.toString() ?? '',
      shiftId: map['shift_id']?.toString() ?? '',
      message: map['message']?.toString() ?? 'Je souhaite échanger cette garde.',
      status: map['status']?.toString() ?? 'active',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
