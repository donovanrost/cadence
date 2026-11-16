import type { MissionId } from "@/api/index.ts";
import { ref, watch, type Ref } from "vue";
import { fetchPassOrContact } from "@/features/contacts/index.ts";

/**
 * Timeline's contact ids (U78, lead's ruling): a scheduled or realized contact id links to Contacts
 * History `?contact=<id>` only when `GET /passes/:id` resolves it, so no link ever 404s; one that
 * doesn't stays text. Probed when Technical details opens, once per id.
 */
export function useContactLinks(missionId: Ref<MissionId>, ids: Ref<readonly string[]>) {
  const resolved = ref<ReadonlySet<string>>(new Set());
  let probed = new Set<string>();
  let generation = 0;
  watch([missionId, ids], () => {
    generation += 1;
    probed = new Set();
    resolved.value = new Set();
  });
  async function probe() {
    const mine = generation;
    const todo = ids.value.filter((id) => !probed.has(id));
    for (const id of todo) probed.add(id);
    const found = await Promise.all(
      todo.map(async (id) => ((await fetchPassOrContact(missionId.value, id)).ok ? id : null)),
    );
    if (mine !== generation) return;
    const next = new Set(resolved.value);
    for (const id of found) if (id !== null) next.add(id);
    resolved.value = next;
  }
  return { resolved, probe };
}
