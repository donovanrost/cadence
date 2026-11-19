import type { MissionId } from "@/api/index.ts";
import { ref, watch, type Ref } from "vue";
import { fetchPassOrContact } from "@/features/contacts/index.ts";

/** How long an id that didn't resolve stays unresolved before an open event asks again. */
export const UNRESOLVED_TTL_MS = 5 * 60_000;

/**
 * Answers shared by every event detail for the page's life (lead): a resolved id stays resolved;
 * one that didn't is asked again only after UNRESOLVED_TTL_MS (api's any-id lookup may ship).
 */
const answers = new Map<string, { ok: boolean; at: number }>();
const inFlight = new Map<string, Promise<boolean>>();

function resolves(missionId: MissionId, id: string): Promise<boolean> {
  const key = `${missionId} ${id}`;
  const known = answers.get(key);
  if (known && (known.ok || Date.now() - known.at < UNRESOLVED_TTL_MS)) {
    return Promise.resolve(known.ok);
  }
  const pending = inFlight.get(key);
  if (pending) return pending;
  const ask = fetchPassOrContact(missionId, id)
    .then((r) => {
      answers.set(key, { ok: r.ok, at: Date.now() });
      return r.ok;
    })
    .finally(() => inFlight.delete(key));
  inFlight.set(key, ask);
  return ask;
}

/** Test seam: forget every answer. */
export function forgetContactLinks() {
  answers.clear();
  inFlight.clear();
}

/**
 * Timeline's contact ids (U78, lead's ruling): a scheduled or realized contact id links to Contacts
 * History `?contact=<id>` only when `GET /passes/:id` resolves it, so no link ever 404s; one that
 * doesn't stays text. Only the OPEN event's detail uses this, and only once its Technical details
 * opens: at most one read per id (two ids per event), shared across events and cached (lead).
 */
export function useContactLinks(missionId: Ref<MissionId>, ids: Ref<readonly string[]>) {
  const resolved = ref<ReadonlySet<string>>(new Set());
  let generation = 0;
  watch([missionId, ids], () => {
    generation += 1;
    resolved.value = new Set();
  });
  async function probe() {
    const mine = generation;
    const found = await Promise.all(
      ids.value.map(async (id) => ((await resolves(missionId.value, id)) ? id : null)),
    );
    if (mine !== generation) return;
    resolved.value = new Set(found.filter((id): id is string => id !== null));
  }
  return { resolved, probe };
}
