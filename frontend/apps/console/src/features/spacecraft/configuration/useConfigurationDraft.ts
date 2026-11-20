import { computed, ref, shallowRef, watch, type Ref } from "vue";
import { isError, type ApiError } from "@/api/index.ts";
import {
  saveDraft,
  type ConfigurationDocument,
  type ConfigurationSnapshot,
  type WorkspaceKey,
} from "./api.ts";
import { saveRefusal, savedLine, type SaveRefusal } from "./draft-words.ts";

const same = (a: ConfigurationDocument, b: ConfigurationDocument) =>
  JSON.stringify(a) === JSON.stringify(b);

/**
 * #595a (U94): one draft across the configuration's tabs. Edits live here until `Save draft`
 * (PUT …/workspace/draft with the snapshot's token); the answer is the fresh snapshot, shown
 * until the next read arrives. A stale token (`spacecraft_configuration_changed`) keeps the
 * edits and opens "Someone saved…" over the newer snapshot.
 */
export function useConfigurationDraft(
  key: Readonly<Ref<WorkspaceKey | null>>,
  /** The latest read's snapshot (null while loading or failed). */
  read: () => ConfigurationSnapshot | null,
  refetch: () => void,
) {
  /** The PUT's answer, until a read newer than it arrives (useRemoteQuery has no setter). */
  const fresh = shallowRef<ConfigurationSnapshot | null>(null);
  const edits = shallowRef<ConfigurationDocument | null>(null);
  const saving = ref(false);
  const failure = shallowRef<SaveRefusal | null>(null);
  /** U94: the outcome of the person's own save, one object per save (OutcomeCallout). */
  const saved = shallowRef<Readonly<{ tone: "nominal"; text: string }> | null>(null);
  /** Someone saved after these edits started: the newer saved document, until a choice. */
  const conflict = shallowRef<ConfigurationDocument | null>(null);

  const snapshot = computed(() => {
    const r = read();
    const f = fresh.value;
    return f !== null && r !== null && f.spacecraft_id === r.spacecraft_id ? f : r;
  });
  watch(read, () => (fresh.value = null));
  // Another craft or section's read: start clean.
  watch(
    () => key.value?.spacecraftId,
    () => reset(),
  );

  const doc = computed(() => edits.value ?? snapshot.value?.document ?? null);
  const dirty = computed(() => {
    const s = snapshot.value;
    return s !== null && edits.value !== null && !same(edits.value, s.document);
  });

  function reset() {
    edits.value = null;
    failure.value = null;
    saved.value = null;
    conflict.value = null;
  }
  function edit(patch: Partial<ConfigurationDocument>) {
    const base = doc.value;
    if (!base) return;
    edits.value = { ...base, ...patch };
    saved.value = null;
  }

  async function save() {
    const k = key.value;
    const s = snapshot.value;
    const mine = doc.value;
    if (saving.value || !k || !s || !mine) return;
    saving.value = true;
    failure.value = null;
    saved.value = null;
    try {
      const r = await saveDraft(k, s.token, mine);
      if (r.ok) {
        fresh.value = r.value;
        edits.value = null;
        conflict.value = null;
        saved.value = { tone: "nominal", text: savedLine(r.value) };
        refetch();
      } else onRefused(r.error, s, mine);
    } finally {
      saving.value = false;
    }
  }
  function onRefused(e: ApiError, s: ConfigurationSnapshot, mine: ConfigurationDocument) {
    if (isError(e, "spacecraft_configuration_changed")) {
      // U94: the edits are kept; the next read brings the newer saved draft and its token.
      edits.value = mine;
      conflictPending = true;
      refetch();
      return;
    }
    failure.value = saveRefusal(e, s, mine);
  }
  /** The newer read after a stale-token refusal opens the panel over it. */
  let conflictPending = false;
  watch(read, (r) => {
    if (!conflictPending || r === null) return;
    conflictPending = false;
    conflict.value = r.document;
  });

  /** `Use the saved version`: drop the edits. `Keep my edits`: save them over the newer token. */
  const useSaved = () => reset();
  const keepMine = () => (conflict.value = null);
  const discard = () => reset();

  return {
    snapshot,
    doc,
    dirty,
    saving,
    failure,
    saved,
    conflict,
    edit,
    save,
    discard,
    useSaved,
    keepMine,
  };
}
