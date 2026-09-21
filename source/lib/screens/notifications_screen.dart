import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/exchange_request.dart';
import '../models/leave_request.dart';
import '../models/password_reset_request.dart';
import '../models/reminder_notification.dart';
import '../models/shift_type.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'admin_password_reset_screen.dart';
import '../theme/widgets.dart';
import '../ui/components.dart';

class NotificationsScreen extends StatelessWidget {
  final int initialIndex;
  final bool embedded;
  const NotificationsScreen({super.key, this.initialIndex = 0, this.embedded = false});

  Future<void> _clean(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Nettoyer les notifications ?'),
        content: const Text(
          'Les rappels passés et les demandes déjà terminées seront masqués. '
          'Les transferts, échanges et congés encore à traiter restent visibles.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.cleaning_services_rounded, size: 18),
            label: const Text('Nettoyer'),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      context.read<AppState>().clearReadAndPastNotifications();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifications lues et passées nettoyées.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isAdmin = appState.currentUser?.role == UserRole.admin;
    final accountCount = isAdmin ? appState.accountActionableCount : 0;
    final tabCount = isAdmin ? 4 : 3;
    var resolvedIndex =
        initialIndex < 0 ? 0 : (initialIndex >= tabCount ? tabCount - 1 : initialIndex);

    // If the bell badge is only an account approval, open that section directly.
    if (isAdmin &&
        initialIndex == 0 &&
        accountCount > 0 &&
        appState.exchangeActionableCount() == 0 &&
        appState.leaveActionableCount() == 0) {
      resolvedIndex = 3;
    }

    final tabs = TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        const Tab(text: 'Rappels'),
        Tab(text: 'Échanges / transferts (${appState.exchangeActionableCount()})'),
        Tab(text: 'Congés (${appState.leaveActionableCount()})'),
        if (isAdmin) Tab(text: 'Comptes ($accountCount)'),
      ],
    );
    final body = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        child: Row(children: [
          Expanded(child: Text(appState.totalBadgeCount == 0
              ? 'Vous êtes à jour'
              : '${appState.totalBadgeCount} demande${appState.totalBadgeCount > 1 ? 's' : ''} à traiter',
            style: Theme.of(context).textTheme.titleMedium)),
          IconButton(tooltip: 'Nettoyer les notifications terminées', onPressed: () => _clean(context),
            icon: const Icon(Icons.cleaning_services_outlined)),
        ]),
      ),
      tabs,
      Expanded(child: TabBarView(children: [
        _RemindersTab(), _ExchangesTab(), _LeavesTab(), if (isAdmin) _AccountsTab(),
      ])),
    ]);
    return DefaultTabController(
      length: tabCount, initialIndex: resolvedIndex,
      child: embedded ? body : Scaffold(appBar: AppBar(title: const Text('Notifications')), body: SafeArea(top: false, child: body)),
    );
  }
}


class _AccountsTab extends StatelessWidget {
  const _AccountsTab();

  Future<void> _reviewAccount(
    BuildContext context,
    AppState appState,
    AppUser user,
    bool approve,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(approve ? 'Valider ce compte ?' : 'Refuser ce compte ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.fullName,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            SizedBox(height: 6),
            Text(
              '${user.gradeLabel} · ${user.service}',
              style: TextStyle(color: AppColors.inkSoft),
            ),
            SizedBox(height: 3),
            Text(
              user.hospital,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
            ),
            SizedBox(height: 3),
            Text(
              user.phone,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
            ),
            SizedBox(height: 14),
            Text(
              approve
                  ? 'Après validation, ce médecin pourra se connecter à GardeFlow.'
                  : 'Le compte sera refusé / suspendu et ne pourra pas se connecter.',
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Annuler'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: approve ? AppColors.brandDark : const Color(0xFFB42318),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: Icon(
              approve ? Icons.verified_user_outlined : Icons.block_outlined,
              size: 18,
            ),
            label: Text(approve ? 'Valider le compte' : 'Refuser'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final error = await appState.reviewAccount(user.id, approve);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (approve
                  ? 'Compte validé.'
                  : 'Compte refusé / suspendu.'),
        ),
      ),
    );
  }


  Future<void> _openPasswordReset(
    BuildContext context,
    AppState appState,
    PasswordResetRequest request,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminPasswordResetScreen(
          initialUserId: request.profileId,
        ),
      ),
    );
    if (context.mounted) {
      await appState.refreshBackend();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final me = appState.currentUser;

    if (me == null || me.role != UserRole.admin) {
      return const _EmptyState(
        icon: Icons.admin_panel_settings_outlined,
        message: 'La validation des comptes est réservée aux administrateurs.',
      );
    }

    final resetRequests = appState.passwordResetRequests.toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    final pending = appState.pendingUsers.toList()
      ..sort(
        (a, b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );

    if (pending.isEmpty && resetRequests.isEmpty) {
      return const _EmptyState(
        icon: Icons.verified_user_outlined,
        message: 'Aucune action de compte en attente.',
      );
    }

    return RefreshIndicator(
      onRefresh: appState.refreshBackend,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpace.lg),
        itemCount: resetRequests.length + pending.length,
        separatorBuilder: (_, __) => const SizedBox(height: 11),
        itemBuilder: (context, index) {
          if (index < resetRequests.length) {
            final request = resetRequests[index];
            return AppCard(
              padding: EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 43,
                        height: 43,
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.lock_reset_rounded,
                          color: AppColors.warning,
                          size: 23,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mot de passe oublié',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              request.fullName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            SizedBox(height: 3),
                            Text(
                              '${request.gradeLabel} · ${request.service}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            SizedBox(height: 2),
                            Text(
                              request.hospital,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            SizedBox(height: 2),
                            Text(
                              request.phone,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Demandé le ${DateFormat('dd/MM/yyyy · HH:mm').format(request.requestedAt.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.inkFaint,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: AppSpace.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () =>
                          _openPasswordReset(context, appState, request),
                      icon: Icon(Icons.lock_reset_rounded, size: 18),
                      label: Text('Réinitialiser le mot de passe'),
                    ),
                  ),
                ],
              ),
            );
          }

          final user = pending[index - resetRequests.length];
          return AppCard(
            padding: EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 43,
                      height: 43,
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.person_add_alt_1_rounded,
                        color: AppColors.brand,
                        size: 22,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          SizedBox(height: 3),
                          Text(
                            '${user.gradeLabel} · ${user.service}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          SizedBox(height: 2),
                          Text(
                            user.hospital,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          SizedBox(height: 2),
                          Text(
                            user.phone,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _reviewAccount(context, appState, user, false),
                        icon: Icon(Icons.block_outlined, size: 18),
                        label: Text('Refuser'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: BorderSide(
                            color: AppColors.danger.withOpacity(0.55),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            _reviewAccount(context, appState, user, true),
                        icon: Icon(
                          Icons.verified_user_outlined,
                          size: 18,
                        ),
                        label: Text('Valider'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RemindersTab extends StatelessWidget {
  const _RemindersTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final reminders = appState.reminders.toList()
      ..sort((a, b) {
        final aSent = a.status == ReminderStatus.sent;
        final bSent = b.status == ReminderStatus.sent;
        if (aSent != bSent) return aSent ? 1 : -1;
        return aSent
            ? b.fireAt.compareTo(a.fireAt)
            : a.fireAt.compareTo(b.fireAt);
      });

    if (reminders.isEmpty) {
      return const _EmptyState(
        icon: Icons.notifications_none_rounded,
        message:
            'Aucun rappel de garde pour l’instant. Les rappels sont créés '
            'à partir des gardes des calendriers validés.',
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            physics: BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
            itemCount: reminders.length,
            separatorBuilder: (_, __) => SizedBox(height: 11),
            itemBuilder: (context, i) => _ReminderCard(reminder: reminders[i]),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.paper,
              border: Border(
                top: BorderSide(color: AppColors.line.withOpacity(0.65)),
              ),
            ),
            child: OutlinedButton.icon(
              onPressed: appState.clearSentReminders,
              icon: Icon(Icons.delete_sweep_outlined, size: 19),
              label: const Text('Effacer les rappels envoyés', textAlign: TextAlign.center),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final ReminderNotification reminder;
  const _ReminderCard({required this.reminder});
  @override
  Widget build(BuildContext context) => NotificationTile(
    title: reminder.label,
    subtitle: DateFormat('EEEE d MMMM · HH:mm', 'fr_FR').format(reminder.fireAt),
    active: reminder.status != ReminderStatus.sent,
    status: reminder.status == ReminderStatus.sent ? 'Envoyé' : 'À venir',
  );
}

/// État vide partagé par les trois onglets.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: AppColors.inkFaint),
            SizedBox(height: AppSpace.md),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}

class _ExchangesTab extends StatelessWidget {
  const _ExchangesTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final me = appState.currentUser;
    if (me == null) return const SizedBox.shrink();

    final relevant = appState.exchanges.where((e) {
      if (appState.isNotificationDismissed('exchange:${e.id}')) return false;
      return me.role == UserRole.admin || e.fromId == me.id || e.toId == me.id || e.fromPhone == me.phone || e.toPhone == me.phone;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (relevant.isEmpty) {
      return const _EmptyState(
        icon: Icons.swap_horiz_rounded,
        message: 'Aucune demande de transfert ou d’échange pour l’instant.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: relevant.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, i) {
        final ex = relevant[i];
        final shift = ShiftCatalog.byId(ex.shiftId);
        final date = DateTime.parse(ex.dateStr);
        final dateLabel = DateFormat('EEE d MMM', 'fr_FR').format(date);
        final targetShift = ex.targetShiftId == null ? null : ShiftCatalog.byId(ex.targetShiftId!);
        final targetDateLabel = ex.targetDateStr == null ? null : DateFormat('EEE d MMM', 'fr_FR').format(DateTime.parse(ex.targetDateStr!));
        final requestLabel = ex.isTransfer ? 'Transfert' : 'Échange';

        final canRespondAsB = ex.status == ExchangeStatus.pendingB && (ex.toId == me.id || ex.toPhone == me.phone);
        final canRespondAsAdmin = ex.status == ExchangeStatus.pendingAdmin && me.role == UserRole.admin && ex.fromId != me.id && ex.toId != me.id && ex.fromPhone != me.phone && ex.toPhone != me.phone;
        final needsOtherAdmin = ex.status == ExchangeStatus.pendingAdmin && me.role == UserRole.admin && (ex.fromId == me.id || ex.toId == me.id || ex.fromPhone == me.phone || ex.toPhone == me.phone);

        return AppCard(
          padding: EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Pill(
                  text: requestLabel,
                  icon: ex.isTransfer ? Icons.arrow_forward_rounded : Icons.swap_horiz_rounded,
                  fontSize: 12,
                ),
                SizedBox(width: AppSpace.sm),
                Expanded(child: Text('${ex.fromName} → ${ex.toName}', style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
              ]),
              SizedBox(height: AppSpace.sm),
              if (ex.isTransfer)
                Text('Garde transférée : $dateLabel · ${shift.label}', style: Theme.of(context).textTheme.bodySmall)
              else ...[
                Text('${ex.fromName} donne : $dateLabel · ${shift.label}', style: Theme.of(context).textTheme.bodySmall),
                SizedBox(height: 2),
                Text('${ex.toName} donne : $targetDateLabel · ${targetShift?.label ?? ""}', style: Theme.of(context).textTheme.bodySmall),
              ],
              if (ex.isServiceExchange && ex.status == ExchangeStatus.pendingB) ...[
                SizedBox(height: AppSpace.sm),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: AppRadius.smR,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.flash_on_rounded, size: 16, color: Theme.of(context).colorScheme.onPrimaryContainer),
                      SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: Text(
                          'Échange de gardes Service : l’acceptation applique immédiatement l’échange, sans validation administrateur.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: AppSpace.md),
              if (canRespondAsB)
                Row(children: [
                  Expanded(child: _ActionButton(label: 'Accepter', color: AppColors.conge, textColor: AppColors.congeText, onTap: () async { final err = await appState.acceptExchange(ex.id); if (err != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err))); })),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: _ActionButton(label: 'Refuser', color: AppColors.urg24h, textColor: AppColors.urg24hText, onTap: () async { final err = await appState.declineExchange(ex.id); if (err != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err))); })),
                ])
              else if (canRespondAsAdmin)
                Row(children: [
                  Expanded(child: _ActionButton(label: 'Approuver', color: AppColors.conge, textColor: AppColors.congeText, onTap: () async { if (!await confirmAction(context, title: 'Approuver cet échange ou transfert ?', message: '${ex.fromName} → ${ex.toName}\nLes affectations seront mises à jour.', actionLabel: 'Approuver') || !context.mounted) return; final err = await appState.approveExchange(ex.id); if (err != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err))); })),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: _ActionButton(label: 'Rejeter', color: AppColors.urg24h, textColor: AppColors.urg24hText, onTap: () async { if (!await confirmAction(context, title: 'Rejeter cette demande ?', message: '${ex.fromName} → ${ex.toName}\nLes gardes resteront affectées à leurs médecins actuels.', actionLabel: 'Rejeter', destructive: true) || !context.mounted) return; final err = await appState.rejectExchange(ex.id); if (err != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err))); })),
                ])
              else if (ex.status == ExchangeStatus.pendingB && (ex.fromId == me.id || ex.fromPhone == me.phone))
                Row(
                  children: [
                    Expanded(child: Align(alignment: Alignment.centerLeft, child: _StatusPill(ex: ex))),
                    const SizedBox(width: AppSpace.sm),
                    TextButton(onPressed: () async { final err = await appState.cancelExchange(ex.id); if (err != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err))); }, child: const Text('Annuler')),
                  ],
                )
              else ...[
                _StatusPill(ex: ex),
                if (needsOtherAdmin) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text('Vous participez à cette demande : sa validation doit être effectuée par un autre administrateur.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}


class _LeavesTab extends StatelessWidget {
  const _LeavesTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final me = appState.currentUser;
    if (me == null) return const SizedBox.shrink();

    final relevant = appState.leaveRequests.where((r) =>
      !appState.isNotificationDismissed('leave:${r.id}') &&
      (me.role == UserRole.admin || r.ownerId == me.id || r.ownerPhone == me.phone)
    ).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (relevant.isEmpty) {
      return const _EmptyState(
        icon: Icons.beach_access_rounded,
        message: 'Aucune demande de congé pour l’instant.',
      );
    }

    if (me.role == UserRole.admin) {
      return _AdminLeavesGroupedList(requests: relevant);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: relevant.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, i) => AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: _LeaveRequestRow(request: relevant[i]),
      ),
    );
  }
}

class _AdminLeavesGroupedList extends StatelessWidget {
  final List<LeaveRequest> requests;
  const _AdminLeavesGroupedList({required this.requests});

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<LeaveRequest>>{};
    for (final request in requests) {
      grouped.putIfAbsent(request.ownerPhone, () => <LeaveRequest>[]).add(request);
    }

    final groups = grouped.values.toList()
      ..sort((a, b) {
        final aPending = a.where((r) => r.status == LeaveRequestStatus.pendingAdmin).length;
        final bPending = b.where((r) => r.status == LeaveRequestStatus.pendingAdmin).length;
        if (aPending != bPending) return bPending.compareTo(aPending);
        return a.first.ownerName.toLowerCase().compareTo(b.first.ownerName.toLowerCase());
      });

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doctorRequests = groups[index]
          ..sort((a, b) {
            final aPending = a.status == LeaveRequestStatus.pendingAdmin ? 0 : 1;
            final bPending = b.status == LeaveRequestStatus.pendingAdmin ? 0 : 1;
            if (aPending != bPending) return aPending.compareTo(bPending);
            return b.createdAt.compareTo(a.createdAt);
          });
        final doctorName = doctorRequests.first.ownerName;
        final pendingCount = doctorRequests.where((r) => r.status == LeaveRequestStatus.pendingAdmin).length;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.line),
            borderRadius: AppRadius.mdR,
            boxShadow: AppShadow.low,
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: pendingCount > 0,
            shape: Border(),
            collapsedShape: Border(),
            tilePadding: EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xs),
            childrenPadding: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
            title: Text(doctorName, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(
              '${doctorRequests.length} demande${doctorRequests.length > 1 ? 's' : ''} de congé',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: pendingCount > 0
                ? Pill(
                    text: '$pendingCount en attente',
                    background: AppColors.serviceJour,
                    foreground: AppColors.serviceJourText,
                    fontSize: 12,
                  )
                : Icon(Icons.expand_more_rounded, color: AppColors.inkFaint),
            children: [
              for (var i = 0; i < doctorRequests.length; i++) ...[
                if (i > 0) Divider(height: AppSpace.lg, color: AppColors.line),
                _LeaveRequestRow(request: doctorRequests[i], showOwnerName: false),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LeaveRequestRow extends StatelessWidget {
  final LeaveRequest request;
  final bool showOwnerName;
  const _LeaveRequestRow({required this.request, this.showOwnerName = true});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final me = appState.currentUser;
    if (me == null) return const SizedBox.shrink();

    final r = request;
    final startLabel = DateFormat('EEE d MMM yyyy', 'fr_FR').format(DateTime.parse(r.startDateStr));
    final endLabel = DateFormat('EEE d MMM yyyy', 'fr_FR').format(DateTime.parse(r.endDateStr));
    final dateLabel = r.isSingleDay ? startLabel : 'Du $startLabel au $endLabel';
    final conflicts = appState.leaveConflictingEntries(r);
    final canReview = me.role == UserRole.admin && r.status == LeaveRequestStatus.pendingAdmin && r.ownerId != me.id && r.ownerPhone != me.phone;
    final needsOtherAdmin = me.role == UserRole.admin && r.status == LeaveRequestStatus.pendingAdmin && (r.ownerId == me.id || r.ownerPhone == me.phone);
    final canCancel = (r.ownerId == me.id || r.ownerPhone == me.phone) && r.status == LeaveRequestStatus.pendingAdmin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Pill(
            text: 'Congé',
            icon: Icons.beach_access_rounded,
            background: AppColors.conge,
            foreground: AppColors.congeText,
            fontSize: 12,
          ),
          if (showOwnerName) ...[
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(r.ownerName, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
          ],
        ]),
        const SizedBox(height: AppSpace.sm),
        Text(dateLabel, style: Theme.of(context).textTheme.bodySmall),
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(color: AppColors.urgJour, borderRadius: AppRadius.smR),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.urgJourText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${conflicts.length} garde${conflicts.length > 1 ? 's' : ''} à couvrir avant approbation : ${conflicts.map((e) => DateFormat('dd/MM', 'fr_FR').format(DateTime.parse(e.dateStr))).join(', ')}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.urgJourText),
                ),
              ),
            ]),
          ),
        ],
        if (needsOtherAdmin) ...[
          const SizedBox(height: AppSpace.sm),
          Text('Votre propre congé doit être validé par un autre administrateur.', style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: AppSpace.md),
        if (canReview)
          Row(children: [
            Expanded(child: _ActionButton(
              label: 'Approuver', color: AppColors.conge, textColor: AppColors.congeText,
              onTap: conflicts.isNotEmpty ? null : () async {
                if (!await confirmAction(context, title: 'Approuver ce congé ?', message: '${r.ownerName}\n$dateLabel', actionLabel: 'Approuver') || !context.mounted) return;
                final err = await appState.reviewLeave(r.id, true);
                if (err != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
            )),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: _ActionButton(
              label: 'Refuser', color: AppColors.urg24h, textColor: AppColors.urg24hText,
              onTap: () async {
                if (!await confirmAction(context, title: 'Refuser ce congé ?', message: '${r.ownerName}\n$dateLabel\nLes tuiles de ce congé seront retirées selon les règles actuelles.', actionLabel: 'Refuser', destructive: true) || !context.mounted) return;
                final err = await appState.reviewLeave(r.id, false);
                if (err != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
            )),
          ])
        else
          Row(children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: _LeaveStatusPill(request: r))),
            if (canCancel) ...[
              const SizedBox(width: AppSpace.sm),
              TextButton(
                onPressed: () async {
                  final err = await appState.cancelLeave(r.id);
                  if (err != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                },
                child: const Text('Annuler'),
              ),
            ],
          ]),
      ],
    );
  }
}

class _LeaveStatusPill extends StatelessWidget {
  final LeaveRequest request;
  const _LeaveStatusPill({required this.request});

  @override
  Widget build(BuildContext context) {
    late String text;
    late Color bg;
    late Color fg;
    switch (request.status) {
      case LeaveRequestStatus.pendingAdmin:
        text = 'En attente de l’admin'; bg = AppColors.serviceJour; fg = AppColors.serviceJourText; break;
      case LeaveRequestStatus.approved:
        text = 'Congé approuvé'; bg = AppColors.conge; fg = AppColors.congeText; break;
      case LeaveRequestStatus.rejectedAdmin:
        text = 'Congé refusé'; bg = AppColors.urg24h; fg = AppColors.urg24hText; break;
      case LeaveRequestStatus.cancelled:
        text = 'Annulé'; bg = AppColors.paperAlt; fg = AppColors.inkSoft; break;
    }
    return Pill(text: text, background: bg, foreground: fg, fontSize: 12);
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;
  const _ActionButton({required this.label, required this.color, required this.textColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
      ),
      child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final ExchangeRequest ex;
  const _StatusPill({required this.ex});

  @override
  Widget build(BuildContext context) {
    late String text;
    late Color bg;
    late Color fg;
    switch (ex.status) {
      case ExchangeStatus.pendingB:
        text = 'En attente de ${ex.toName}';
        bg = AppColors.serviceJour; fg = AppColors.serviceJourText;
        break;
      case ExchangeStatus.pendingAdmin:
        text = 'En attente de l\u2019admin';
        bg = AppColors.serviceJour; fg = AppColors.serviceJourText;
        break;
      case ExchangeStatus.approved:
        text = ex.isServiceExchange ? 'Accepté · appliqué' : 'Approuvé';
        bg = AppColors.conge; fg = AppColors.congeText;
        break;
      case ExchangeStatus.declinedB:
        text = 'Refusé par ${ex.toName}';
        bg = AppColors.urg24h; fg = AppColors.urg24hText;
        break;
      case ExchangeStatus.rejectedAdmin:
        text = 'Rejeté par l\u2019admin';
        bg = AppColors.urg24h; fg = AppColors.urg24hText;
        break;
      case ExchangeStatus.cancelled:
        text = 'Annulé';
        bg = AppColors.paperAlt; fg = AppColors.inkSoft;
        break;
    }
    return Pill(text: text, background: bg, foreground: fg, fontSize: 12);
  }
}
