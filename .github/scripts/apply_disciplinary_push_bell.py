from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(rel, old, new):
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{rel}: expected 1 occurrence, got {count}: {old[:80]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# 1) Persist the administrative reason on the planning entry so the doctor can
#    see the same information inside the in-app notification center.
replace_once(
    "source/lib/models/planning_entry.dart",
    "  bool isDisciplinary;\n  final DateTime createdAt;",
    "  bool isDisciplinary;\n  String? disciplinaryReason;\n  final DateTime createdAt;",
)
replace_once(
    "source/lib/models/planning_entry.dart",
    "    this.isDisciplinary = false,\n    DateTime? createdAt,",
    "    this.isDisciplinary = false,\n    this.disciplinaryReason,\n    DateTime? createdAt,",
)
replace_once(
    "source/lib/models/planning_entry.dart",
    "        'isDisciplinary': isDisciplinary,\n        'createdAt': createdAt.toIso8601String(),",
    "        'isDisciplinary': isDisciplinary,\n        'disciplinaryReason': disciplinaryReason,\n        'createdAt': createdAt.toIso8601String(),",
)
replace_once(
    "source/lib/models/planning_entry.dart",
    "        isDisciplinary: j['isDisciplinary'] as bool? ?? false,\n        createdAt: DateTime.parse(j['createdAt'] as String),",
    "        isDisciplinary: j['isDisciplinary'] as bool? ?? false,\n        disciplinaryReason: j['disciplinaryReason'] as String?,\n        createdAt: DateTime.parse(j['createdAt'] as String),",
)

# 2) Load the reason from Supabase with the planning entry.
replace_once(
    "source/lib/services/supabase_backend_service.dart",
    "'id,date_str,shift_id,owner_id,owner_phone,owner_name,leave_request_id,is_disciplinary,created_at',",
    "'id,date_str,shift_id,owner_id,owner_phone,owner_name,leave_request_id,is_disciplinary,disciplinary_reason,created_at',",
)
replace_once(
    "source/lib/services/supabase_backend_service.dart",
    "        isDisciplinary: j['is_disciplinary'] as bool? ?? false,\n        createdAt: DateTime.parse(j['created_at'] as String),",
    "        isDisciplinary: j['is_disciplinary'] as bool? ?? false,\n        disciplinaryReason: j['disciplinary_reason'] as String?,\n        createdAt: DateTime.parse(j['created_at'] as String),",
)

# 3) Require a reason at assignment time, because it is sent to the doctor.
replace_once(
    "source/lib/screens/admin_disciplinary_assignment_screen.dart",
    "    final dates = <String>{};",
    "    final reason = _reasonController.text.trim();\n"
    "    if (reason.length < 3) {\n"
    "      setState(() => _error =\n"
    "          'Indiquez le motif de la garde disciplinaire. Il sera communiqué au médecin.');\n"
    "      return;\n"
    "    }\n\n"
    "    final dates = <String>{};",
)
replace_once(
    "source/lib/screens/admin_disciplinary_assignment_screen.dart",
    "          'p_reason': _reasonController.text.trim(),",
    "          'p_reason': reason,",
)
replace_once(
    "source/lib/screens/admin_disciplinary_assignment_screen.dart",
    "                          'La garde disciplinaire est immédiatement ajoutée au calendrier du médecin. Elle ne peut pas être supprimée, transférée ou échangée par le médecin.',",
    "                          'La garde disciplinaire est immédiatement ajoutée au calendrier du médecin. Une notification PUSH lui est envoyée avec le motif, qui reste également visible dans la cloche de GardeFlow.',",
)
replace_once(
    "source/lib/screens/admin_disciplinary_assignment_screen.dart",
    "                labelText: 'Motif administratif (facultatif)',\n                hintText: 'Visible dans le journal des actions administrateur',",
    "                labelText: 'Motif de la garde disciplinaire',\n                hintText: 'Obligatoire · envoyé au médecin par notification PUSH',",
)

# 4) Treat manual disciplinary assignments as persistent bell notifications.
replace_once(
    "source/lib/state/app_state.dart",
    "  int get totalBadgeCount =>\n      exchangeActionableCount() +\n      leaveActionableCount() +\n      accountActionableCount;",
    "  List<PlanningEntry> get disciplinaryNotifications {\n"
    "    final me = currentUser;\n"
    "    if (me == null) return const <PlanningEntry>[];\n"
    "    final result = _planning\n"
    "        .where(\n"
    "          (e) =>\n"
    "              e.isDisciplinary &&\n"
    "              (e.ownerId == me.id || e.ownerPhone == me.phone) &&\n"
    "              (e.disciplinaryReason?.trim().isNotEmpty ?? false),\n"
    "        )\n"
    "        .toList()\n"
    "      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));\n"
    "    return result;\n"
    "  }\n\n"
    "  int get disciplinaryUnreadCount => disciplinaryNotifications\n"
    "      .where((e) => !isNotificationDismissed('disciplinary:${e.id}'))\n"
    "      .length;\n\n"
    "  void markDisciplinaryNotificationsRead() {\n"
    "    var changed = false;\n"
    "    for (final entry in disciplinaryNotifications) {\n"
    "      changed = _dismissedNotificationKeys.add(\n"
    "            _scopedNotificationKey('disciplinary:${entry.id}'),\n"
    "          ) ||\n"
    "          changed;\n"
    "    }\n"
    "    if (!changed) return;\n"
    "    _persist();\n"
    "    notifyListeners();\n"
    "  }\n\n"
    "  int get totalBadgeCount =>\n"
    "      exchangeActionableCount() +\n"
    "      leaveActionableCount() +\n"
    "      accountActionableCount +\n"
    "      disciplinaryUnreadCount;",
)

# 5) Bell screen: show disciplinary notices above ordinary reminders and clear
#    only the unread badge after the doctor opens the bell. The card remains.
replace_once(
    "source/lib/screens/notifications_screen.dart",
    "import '../models/password_reset_request.dart';\nimport '../models/reminder_notification.dart';",
    "import '../models/password_reset_request.dart';\nimport '../models/planning_entry.dart';\nimport '../models/reminder_notification.dart';",
)
replace_once(
    "source/lib/screens/notifications_screen.dart",
    "    final isAdmin = appState.currentUser?.role == UserRole.admin;\n    final accountCount = isAdmin ? appState.accountActionableCount : 0;",
    "    final isAdmin = appState.currentUser?.role == UserRole.admin;\n"
    "    final disciplinaryUnread = appState.disciplinaryUnreadCount;\n"
    "    if (disciplinaryUnread > 0) {\n"
    "      WidgetsBinding.instance.addPostFrameCallback((_) {\n"
    "        if (context.mounted) {\n"
    "          context.read<AppState>().markDisciplinaryNotificationsRead();\n"
    "        }\n"
    "      });\n"
    "    }\n"
    "    final accountCount = isAdmin ? appState.accountActionableCount : 0;",
)
replace_once(
    "source/lib/screens/notifications_screen.dart",
    "        appState.exchangeActionableCount() == 0 &&\n        appState.leaveActionableCount() == 0) {",
    "        appState.exchangeActionableCount() == 0 &&\n        appState.leaveActionableCount() == 0 &&\n        disciplinaryUnread == 0) {",
)
replace_once(
    "source/lib/screens/notifications_screen.dart",
    "                  Tab(text: 'Rappels'),",
    "                  Tab(text: 'Alertes'),",
)
replace_once(
    "source/lib/screens/notifications_screen.dart",
    "    final appState = context.watch<AppState>();\n    final reminders = appState.reminders.toList()",
    "    final appState = context.watch<AppState>();\n"
    "    final disciplinary = appState.disciplinaryNotifications;\n"
    "    final reminders = appState.reminders.toList()",
)
replace_once(
    "source/lib/screens/notifications_screen.dart",
    "    if (reminders.isEmpty) {\n      return const _EmptyState(\n        icon: Icons.notifications_none_rounded,\n        message:\n            'Aucun rappel de garde pour l’instant. Les rappels sont créés '\n            'à partir des gardes des calendriers validés.',\n      );\n    }",
    "    if (reminders.isEmpty && disciplinary.isEmpty) {\n"
    "      return const _EmptyState(\n"
    "        icon: Icons.notifications_none_rounded,\n"
    "        message:\n"
    "            'Aucune alerte pour l’instant. Les gardes disciplinaires attribuées et les rappels de garde apparaîtront ici.',\n"
    "      );\n"
    "    }",
)
replace_once(
    "source/lib/screens/notifications_screen.dart",
    "            itemCount: reminders.length,\n            separatorBuilder: (_, __) => SizedBox(height: 11),\n            itemBuilder: (context, i) => _ReminderCard(reminder: reminders[i]),",
    "            itemCount: disciplinary.length + reminders.length,\n"
    "            separatorBuilder: (_, __) => SizedBox(height: 11),\n"
    "            itemBuilder: (context, i) {\n"
    "              if (i < disciplinary.length) {\n"
    "                return _DisciplinaryNotificationCard(\n"
    "                  entry: disciplinary[i],\n"
    "                );\n"
    "              }\n"
    "              return _ReminderCard(\n"
    "                reminder: reminders[i - disciplinary.length],\n"
    "              );\n"
    "            },",
)

card_code = r'''
class _DisciplinaryNotificationCard extends StatelessWidget {
  final PlanningEntry entry;

  const _DisciplinaryNotificationCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(entry.dateStr);
    final dateLabel = date == null
        ? entry.dateStr
        : DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date);
    final shift = ShiftCatalog.byId(entry.shiftId);
    final reason = entry.disciplinaryReason?.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.danger.withOpacity(0.34),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.055),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.gavel_rounded,
              color: AppColors.danger,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Text(
                        'Garde disciplinaire attribuée',
                        style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 15,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'DISCIPLINAIRE',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  '${dateLabel.isEmpty ? entry.dateStr : dateLabel[0].toUpperCase() + dateLabel.substring(1)} · ${shift.label}',
                  style: const TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.055),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Motif : ${reason == null || reason.isEmpty ? 'Non renseigné' : reason}',
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Attribuée le ${DateFormat('dd/MM/yyyy · HH:mm', 'fr_FR').format(entry.createdAt.toLocal())}',
                  style: const TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

'''
replace_once(
    "source/lib/screens/notifications_screen.dart",
    "class _ReminderCard extends StatelessWidget {",
    card_code + "class _ReminderCard extends StatelessWidget {",
)

# 6) Keep the production migration represented in source control.
migration = r'''-- GardeFlow V12
-- Notification d'attribution de garde disciplinaire : motif persistant dans
-- planning_entries pour affichage dans la cloche + PUSH avec le même motif.

alter table public.planning_entries
  add column if not exists disciplinary_reason text;

update public.planning_entries p
set disciplinary_reason = (
  select nullif(trim(a.reason),'')
  from public.audit_log a
  where a.action='planning.disciplinary_assigned'
    and a.entity_type='planning_entry'
    and a.entity_id=p.id
    and nullif(trim(a.reason),'') is not null
  order by a.created_at desc, a.id desc
  limit 1
)
where p.is_disciplinary=true
  and p.disciplinary_reason is null
  and exists (
    select 1
    from public.audit_log a
    where a.action='planning.disciplinary_assigned'
      and a.entity_type='planning_entry'
      and a.entity_id=p.id
      and nullif(trim(a.reason),'') is not null
  );

create or replace function public.admin_assign_disciplinary_guards(
  p_owner_id uuid,
  p_assignments jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_profile public.profiles%rowtype;
  v_item jsonb;
  v_date date;
  v_shift text;
  v_existing public.planning_entries%rowtype;
  v_entry_id text;
  v_ids text[] := array[]::text[];
  v_seen_dates date[] := array[]::date[];
  v_applied int := 0;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  if not public.is_admin() then
    raise exception 'Action réservée à l’administrateur';
  end if;

  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Le motif de la garde disciplinaire est obligatoire';
  end if;

  select * into v_profile
  from public.profiles
  where id=p_owner_id
    and account_status='active';
  if not found then
    raise exception 'Médecin actif introuvable';
  end if;

  if jsonb_typeof(coalesce(p_assignments,'null'::jsonb)) <> 'array'
     or jsonb_array_length(p_assignments) < 1 then
    raise exception 'Ajoutez au moins une garde disciplinaire';
  end if;
  if jsonb_array_length(p_assignments) > 31 then
    raise exception 'Maximum 31 gardes par attribution';
  end if;

  perform set_config('gardeflow.official_import','1',true);

  for v_item in select value from jsonb_array_elements(p_assignments)
  loop
    begin
      v_date := nullif(v_item->>'date','')::date;
      v_shift := nullif(v_item->>'shift_id','');
    exception when others then
      raise exception 'Date ou type de garde invalide';
    end;

    if v_date is null then
      raise exception 'Date de garde manquante';
    end if;
    if v_shift not in (
      'service-jour','service-24h','service-nuit',
      'urg-jour','urg-24h','urg-nuit'
    ) then
      raise exception 'Type de garde invalide pour le %', v_date;
    end if;
    if v_date = any(v_seen_dates) then
      raise exception 'La date % est présente plusieurs fois dans la même attribution', v_date;
    end if;
    v_seen_dates := array_append(v_seen_dates,v_date);

    if public.guard_has_started(v_date,v_shift) then
      raise exception 'La garde du % est déjà commencée ou passée', v_date;
    end if;

    select * into v_existing
    from public.planning_entries
    where owner_id=p_owner_id
      and date_str=v_date
      and deleted_at is null
    for update;

    if found then
      if not coalesce(v_existing.is_disciplinary,false) then
        raise exception '% a déjà une affectation le %. Supprimez ou déplacez d’abord cette affectation.',
          trim(v_profile.prenom || ' ' || v_profile.nom), v_date;
      end if;

      update public.exchange_requests
      set status='cancelled'
      where status in ('pendingB','pendingAdmin')
        and (planning_entry_id=v_existing.id or target_planning_entry_id=v_existing.id);

      update public.planning_entries
      set shift_id=v_shift,
          owner_phone=v_profile.phone,
          owner_name=trim(v_profile.prenom || ' ' || v_profile.nom),
          leave_request_id=null,
          is_disciplinary=true,
          disciplinary_reason=v_reason
      where id=v_existing.id;
      v_entry_id := v_existing.id;
    else
      v_entry_id := 'disc-' || replace(gen_random_uuid()::text,'-','');
      insert into public.planning_entries(
        id,date_str,shift_id,owner_id,owner_phone,owner_name,
        leave_request_id,is_disciplinary,disciplinary_reason,created_at
      ) values (
        v_entry_id,v_date,v_shift,v_profile.id,v_profile.phone,
        trim(v_profile.prenom || ' ' || v_profile.nom),
        null,true,v_reason,now()
      );
    end if;

    perform public.write_audit(
      'planning.disciplinary_assigned',
      'planning_entry',
      v_entry_id,
      v_profile.id,
      trim(v_profile.prenom || ' ' || v_profile.nom),
      v_reason,
      jsonb_build_object(
        'date',v_date,
        'shift_id',v_shift,
        'manual_admin_assignment',true
      )
    );

    v_ids := array_append(v_ids,v_entry_id);
    v_applied := v_applied + 1;
  end loop;

  return jsonb_build_object(
    'applied',v_applied,
    'entry_ids',to_jsonb(v_ids),
    'owner_id',p_owner_id
  );
end;
$$;

revoke all on function public.admin_assign_disciplinary_guards(uuid,jsonb,text) from public,anon;
grant execute on function public.admin_assign_disciplinary_guards(uuid,jsonb,text) to authenticated;
'''
(ROOT / "source/supabase/patch_v12_0_1_disciplinary_push_bell.sql").write_text(
    migration, encoding="utf-8"
)

print("Disciplinary push + bell patch applied.")
