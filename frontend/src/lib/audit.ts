import { supabase } from './supabase';

export async function logAudit(
  action: string,
  entity: string,
  entityId: string | null,
  details?: Record<string, unknown>,
  summary?: string | null
) {
  await supabase.from('audit_logs').insert({
    actor_id: (await supabase.auth.getUser()).data.user?.id ?? null,
    action,
    entity,
    entity_id: entityId,
    details_json: details ?? null,
    summary_text: summary ?? null,
  });
}
