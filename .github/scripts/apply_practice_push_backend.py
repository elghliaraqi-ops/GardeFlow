from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label}: source block not found')
    return text.replace(old, new, 1)

# Avoid two simultaneous notifications when a user finishes a case 5/5.
path = Path('source/lib/services/clinical_case_service.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    """    if (postId.isNotEmpty && result.caseAnswered >= 5) {
      await _triggerPush('practice_qcm_complete', postId);
      if (result.caseCorrect >= 5) {
        await _triggerPush('practice_qcm_perfect', postId);
      }
    }
""",
    """    if (postId.isNotEmpty && result.caseAnswered >= 5) {
      await _triggerPush(
        result.caseCorrect >= 5
            ? 'practice_qcm_perfect'
            : 'practice_qcm_complete',
        postId,
      );
    }
""",
    'qcm completion notification',
)
path.write_text(text, encoding='utf-8')

# Secure self-push notifications for Practice.
path = Path('source/supabase/functions/send-push/index.ts')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    """    let recipients: string[] = [];
    let title = 'GardeFlow';
    let body = 'Nouvelle notification';
""",
    """    let recipients: string[] = [];
    let title = 'GardeFlow';
    let body = 'Nouvelle notification';
    let allowSelf = false;
    let practicePush = false;
    let receiptResourceId = resourceId;
""",
    'push state vars',
)

marker = """    } else {
      throw new Error('Type de push inconnu');
    }

    recipients = [...new Set(recipients)].filter((id) => id && id !== caller.id);
"""
practice_branch = r'''    } else if (kind.startsWith('practice_')) {
      allowSelf = true;
      practicePush = true;
      recipients = [caller.id];

      const requireOwnedCase = async (caseId: string) => {
        const { data: practiceCase, error } = await admin.from('practice_cases')
          .select('id,user_id,guard_id,patient_number,is_draft,consultation_reason')
          .eq('id', caseId)
          .maybeSingle();
        if (error || !practiceCase || practiceCase.user_id !== caller.id || practiceCase.is_draft) {
          throw new Error('Cas Practice introuvable ou non autorisé');
        }
        return practiceCase;
      };

      const requireOwnedPost = async (postId: string) => {
        const { data: post, error } = await admin.from('clinical_case_posts')
          .select('id,practice_case_id,author_id')
          .eq('id', postId)
          .maybeSingle();
        if (error || !post || post.author_id !== caller.id) {
          throw new Error('Cas clinique introuvable ou non autorisé');
        }
        return post;
      };

      if (kind === 'practice_case_created') {
        const practiceCase = await requireOwnedCase(resourceId);
        const number = Number(practiceCase.patient_number || 0);
        title = 'Cas clinique ajouté';
        body = `${number > 0 ? `Patient #${String(number).padStart(3, '0')} ` : 'Nouveau cas '}enregistré dans Practice. Les 5 QCM sont en préparation.`;
      } else if (kind === 'practice_qcm_ready') {
        const { data: post, error } = await admin.from('clinical_case_posts')
          .select('id,practice_case_id,author_id')
          .eq('practice_case_id', resourceId)
          .maybeSingle();
        if (error || !post || post.author_id !== caller.id) {
          throw new Error('Cas clinique introuvable ou non autorisé');
        }
        const { count } = await admin.from('clinical_case_qcms')
          .select('id', { count: 'exact', head: true })
          .eq('post_id', post.id)
          .eq('generation_source', 'openai');
        if ((count ?? 0) < 5) throw new Error('QCM IA pas encore prêts');
        title = '5 QCM Practice prêts';
        body = 'Les 5 QCM de raisonnement avec explication IA après chaque réponse sont disponibles.';
      } else if (kind === 'practice_achievement_unlocked') {
        const { data: achievement, error } = await admin.from('practice_achievements')
          .select('id,key,name,description')
          .eq('key', resourceId)
          .maybeSingle();
        if (error || !achievement) throw new Error('Succès Practice introuvable');
        const { data: userAchievement } = await admin.from('user_practice_achievements')
          .select('unlocked_at')
          .eq('user_id', caller.id)
          .eq('achievement_id', achievement.id)
          .maybeSingle();
        if (!userAchievement?.unlocked_at) throw new Error('Succès non débloqué');
        title = `🏆 Succès débloqué · ${achievement.name}`;
        body = achievement.description || 'Nouveau succès débloqué dans Practice.';
      } else if (kind === 'practice_goal_reached') {
        const { data: pref } = await admin.from('practice_preferences')
          .select('guard_goal')
          .eq('user_id', caller.id)
          .maybeSingle();
        const goal = Number(pref?.guard_goal || 0);
        if (goal <= 0) throw new Error('Aucun objectif de garde configuré');
        const { count } = await admin.from('practice_cases')
          .select('id', { count: 'exact', head: true })
          .eq('user_id', caller.id)
          .eq('guard_id', resourceId)
          .eq('is_draft', false);
        if ((count ?? 0) < goal) throw new Error('Objectif de garde non atteint');
        title = '🎯 Objectif de garde atteint';
        body = `${count ?? goal} cas documentés : votre objectif de ${goal} est atteint.`;
      } else if (kind === 'practice_case_milestone') {
        const practiceCase = await requireOwnedCase(resourceId);
        const { count } = await admin.from('practice_cases')
          .select('id', { count: 'exact', head: true })
          .eq('user_id', caller.id)
          .eq('guard_id', practiceCase.guard_id)
          .eq('is_draft', false);
        const n = count ?? 0;
        if (![5, 10, 15, 20, 30].includes(n)) {
          throw new Error('Pas de palier Practice à notifier');
        }
        receiptResourceId = `${practiceCase.guard_id}:${n}`;
        title = `🔥 ${n} cas documentés`;
        body = 'Belle progression pendant cette garde. Continuez à documenter les cas utiles sans ralentir les soins.';
      } else if (kind === 'practice_qcm_complete' || kind === 'practice_qcm_perfect') {
        const post = await requireOwnedPost(resourceId);
        const { data: qcms } = await admin.from('clinical_case_qcms')
          .select('id')
          .eq('post_id', post.id);
        const ids = (qcms ?? []).map((q: any) => q.id as string);
        if (ids.length < 5) throw new Error('QCM incomplets');
        const { data: answers } = await admin.from('clinical_case_qcm_answers')
          .select('is_correct')
          .eq('user_id', caller.id)
          .in('qcm_id', ids);
        const answered = answers?.length ?? 0;
        const correct = (answers ?? []).filter((a: any) => a.is_correct).length;
        if (answered < 5) throw new Error('Les 5 QCM ne sont pas terminés');
        if (kind === 'practice_qcm_perfect') {
          if (correct < 5) throw new Error('Score parfait non atteint');
          title = '⭐ 5/5 sur ce cas clinique';
          body = 'Les 5 QCM sont justes. Les explications IA restent disponibles pour consolider le raisonnement.';
        } else {
          title = 'Cas révisé · 5 QCM terminés';
          body = `${correct}/5 réponses justes. Relisez les explications IA pour les points à consolider.`;
        }
      } else if (kind === 'practice_level_up' || kind === 'practice_streak') {
        // Ces événements sont détectés par le client après comparaison des
        // statistiques avant/après. On vérifie seulement que la ressource
        // déclenchante appartient bien à l'utilisateur.
        const { data: ownedCase } = await admin.from('practice_cases')
          .select('id')
          .eq('id', resourceId)
          .eq('user_id', caller.id)
          .maybeSingle();
        if (!ownedCase) {
          const { data: ownedPost } = await admin.from('clinical_case_posts')
            .select('id')
            .eq('id', resourceId)
            .eq('author_id', caller.id)
            .maybeSingle();
          if (!ownedPost) throw new Error('Ressource Practice non autorisée');
        }
        if (kind === 'practice_level_up') {
          title = '⬆️ Nouveau niveau Practice';
          body = 'Votre activité documentée et vos QCM vous font passer au niveau suivant.';
        } else {
          title = '🔥 Série Practice prolongée';
          body = 'Votre régularité continue : une nouvelle garde documentée s’ajoute à votre série.';
        }
      } else {
        throw new Error('Type de push Practice inconnu');
      }

      const { data: previousReceipt } = await admin.from('practice_push_receipts')
        .select('id')
        .eq('user_id', caller.id)
        .eq('kind', kind)
        .eq('resource_id', receiptResourceId)
        .maybeSingle();
      if (previousReceipt) {
        return Response.json({ sent: 0, deduplicated: true }, { headers: corsHeaders });
      }
    } else {
      throw new Error('Type de push inconnu');
    }

    recipients = [...new Set(recipients)].filter((id) => id && (allowSelf || id !== caller.id));
'''
text = replace_once(text, marker, practice_branch, 'Practice push branch')

text = replace_once(
    text,
    """    if (!tokenRows?.length) return Response.json({ sent: 0, devices: 0 }, { headers: corsHeaders });
""",
    """    if (!tokenRows?.length) {
      return Response.json({ sent: 0, devices: 0 }, { headers: corsHeaders });
    }
""",
    'push no devices',
)

text = replace_once(
    text,
    """    return Response.json({ sent, failed, devices: tokenRows.length, recipients: recipients.length }, { headers: corsHeaders });
""",
    """    if (practicePush && sent > 0) {
      await admin.from('practice_push_receipts').upsert({
        user_id: caller.id,
        kind,
        resource_id: receiptResourceId,
        sent_at: new Date().toISOString(),
      }, { onConflict: 'user_id,kind,resource_id' });
    }

    return Response.json({ sent, failed, devices: tokenRows.length, recipients: recipients.length }, { headers: corsHeaders });
""",
    'push receipt',
)
path.write_text(text, encoding='utf-8')

print('Practice push backend integration applied.')
