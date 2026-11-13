import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, onBeforeUnmount, shallowRef, watch, type Ref } from "vue";
import { codeOf, describeApiError, isError, type ApiError } from "@/api/index.ts";
import { formatClock, formatShort } from "@/ui";
import {
  changedBy,
  discardComposeDraft,
  fetchComposeDraft,
  isBlank,
  restoreDraft,
  saveComposeDraft,
  toDocument,
  type ComposeFields,
  type DraftSaved,
  type Restored,
  type StoredDraft,
} from "./saved.ts";

/** Autosave settles this long after the last edit. */
export const AUTOSAVE_MS = 1_500;

export type DraftStatus =
  | { kind: "loading" }
  /** Nothing of this session saved yet. */
  | { kind: "new" }
  | { kind: "saving" }
  | { kind: "saved"; at: string }
  /**
   * 409 command_draft_changed: another tab or device saved (theirs), or the draft is gone (null:
   * submitted or discarded elsewhere). Autosave stops until a choice.
   */
  | { kind: "conflict"; theirs: DraftSaved | null }
  /** `reason`: the server's words when it gave any; `lastSaved`: null if nothing ever saved. */
  | { kind: "failed"; reason: string | null; lastSaved: string | null };

export type DraftNotice = Readonly<{ tone: "info" | "caution"; text: string }>;

/** The server's reason for a refused save, or null when it gave none (network, 5xx page). */
function serverReason(e: ApiError): string | null {
  if (codeOf(e) !== null && "message" in e) return e.message;
  return e.kind === "unavailable" && e.serverCode ? e.message : null;
}

/**
 * Compose's autosave (commanding.md §Compose draft; ux Command.md States, 601a32f9): one current
 * draft per user per mission. `resume` restores it on open; otherwise an existing draft is offered
 * and replaced only from the operator's first edit (values prefilled from the origin don't count:
 * `rebase` after a prefill). Submitting freezes autosave and hands the last saved revision to
 * POST /command-groups, so the server deletes exactly that draft.
 */
export function useComposeDraft(
  missionId: Ref<MissionId>,
  fields: Ref<ComposeFields>,
  apply: (restored: Restored) => void,
  resume: boolean,
) {
  const status = shallowRef<DraftStatus>({ kind: "loading" });
  /** A saved draft found on open and not resumed: offered until this request replaces it. */
  const offered = shallowRef<StoredDraft | null>(null);
  const notice = shallowRef<DraftNotice | null>(null);
  /** When this session last saved or adopted the draft (null: it owns none). */
  const savedAt = shallowRef<string | null>(null);
  /** The document as last saved, adopted or prefilled: edits are differences from it. */
  const baseline = shallowRef<string | null>(null);
  /** The revision PUT expects: the one we last saved or adopted. */
  let revision: number | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let inFlight: Promise<void> | null = null;
  let frozen = false;

  const json = computed(() => JSON.stringify(toDocument(fields.value)));
  /** Edits not yet on the server (a blank form that owns no draft has nothing to keep). */
  const dirty = computed(
    () =>
      baseline.value !== null &&
      json.value !== baseline.value &&
      (savedAt.value !== null || !isBlank(fields.value)),
  );

  async function adopt(stored: StoredDraft) {
    const r = await restoreDraft(missionId.value, stored);
    if (!r.ok) {
      notice.value = { tone: "caution", text: r.message };
      return false;
    }
    apply(r.value);
    await nextTick();
    revision = stored.revision;
    savedAt.value = stored.saved_at;
    offered.value = null;
    baseline.value = json.value;
    status.value = { kind: "saved", at: stored.saved_at };
    const { revision_saved: was, revision_now: now } = stored.catalog;
    const gone = r.value.gone;
    notice.value = gone
      ? {
          tone: "caution",
          text: `${gone === 1 ? "A command" : `${gone} commands`} in this draft ${gone === 1 ? "is" : "are"} no longer in the active catalog and ${gone === 1 ? "was" : "were"} left out.`,
        }
      : was !== null && now !== null && was !== now
        ? {
            tone: "info",
            text: "The catalog changed since this draft was saved. The checks below re-run against it.",
          }
        : null;
    return true;
  }

  async function open() {
    const r = await fetchComposeDraft(missionId.value);
    if (!r.ok) {
      notice.value = {
        tone: "caution",
        text: `Couldn't read your saved draft: ${describeApiError(r.error)}`,
      };
    } else if (r.value !== null && resume) {
      await adopt(r.value);
    } else if (r.value !== null) {
      offered.value = r.value;
      revision = r.value.revision;
    }
    if (status.value.kind === "loading") status.value = { kind: "new" };
    baseline.value ??= json.value;
  }

  async function save() {
    timer = null;
    if (frozen || !dirty.value) return;
    const s = status.value.kind;
    if (s === "conflict" || s === "loading") return;
    const body = toDocument(fields.value);
    const text = JSON.stringify(body);
    status.value = { kind: "saving" };
    const r = await saveComposeDraft(missionId.value, body, revision);
    if (r.ok) {
      revision = r.value.revision;
      savedAt.value = r.value.saved_at;
      offered.value = null;
      baseline.value = text;
      status.value = { kind: "saved", at: r.value.saved_at };
      if (dirty.value) schedule();
    } else if (isError(r.error, "command_draft_changed")) {
      status.value = {
        kind: "conflict",
        theirs: changedBy("details" in r.error ? r.error.details : null),
      };
    } else {
      status.value = { kind: "failed", reason: serverReason(r.error), lastSaved: savedAt.value };
    }
  }

  function run(): Promise<void> {
    const p: Promise<void> = (inFlight ?? Promise.resolve())
      .then(save)
      .catch((e: unknown) => console.error("Draft save failed", e))
      .finally(() => {
        if (inFlight === p) inFlight = null;
      });
    inFlight = p;
    return p;
  }
  function schedule() {
    if (timer !== null) clearTimeout(timer);
    timer = setTimeout(() => void run(), AUTOSAVE_MS);
  }
  watch(json, () => {
    if (dirty.value) schedule();
  });
  // Leaving by any other route still keeps the last edit (close itself flushes first).
  onBeforeUnmount(() => {
    if (timer === null) return;
    clearTimeout(timer);
    if (!frozen) void run();
  });

  /** After a prefill from the origin (alarm, ?targets=, a resend): not the operator's edit. */
  function rebase() {
    if (savedAt.value === null) baseline.value = json.value;
  }
  /** Before closing: save pending edits now. False when they couldn't be saved. */
  async function flush(): Promise<boolean> {
    if (timer !== null) clearTimeout(timer);
    timer = null;
    if (!frozen && dirty.value) await run();
    else await inFlight;
    return frozen || !dirty.value;
  }
  /** Conflict: overwrite the other save (or recreate a gone draft) with this tab's state. */
  function keepMine() {
    const s = status.value;
    if (s.kind !== "conflict") return;
    revision = s.theirs?.revision ?? null;
    status.value = { kind: "saving" };
    baseline.value = "";
    void run();
  }
  /** Conflict, or the offered draft: load the stored version into Compose. */
  async function load() {
    const r = await fetchComposeDraft(missionId.value);
    if (!r.ok) {
      notice.value = {
        tone: "caution",
        text: `Couldn't read your saved draft: ${describeApiError(r.error)}`,
      };
      return;
    }
    if (r.value === null) {
      revision = null;
      offered.value = null;
      status.value = { kind: "new" };
      notice.value = {
        tone: "caution",
        text: "That draft is gone: it was submitted or discarded elsewhere.",
      };
      return;
    }
    await adopt(r.value);
  }
  async function discard() {
    if (timer !== null) clearTimeout(timer);
    timer = null;
    await inFlight;
    const r = await discardComposeDraft(missionId.value);
    if (!r.ok) {
      notice.value = {
        tone: "caution",
        text: `Couldn't discard the draft: ${describeApiError(r.error)}`,
      };
      return false;
    }
    revision = null;
    savedAt.value = null;
    offered.value = null;
    baseline.value = json.value;
    status.value = { kind: "new" };
    return true;
  }

  /** Before submit: stop autosave, let a save in flight land, and return the revision to delete. */
  async function freeze(): Promise<number | null> {
    frozen = true;
    if (timer !== null) clearTimeout(timer);
    timer = null;
    await inFlight;
    return savedAt.value === null ? null : revision;
  }
  /** After a rejected submit: autosave resumes with any edits since. */
  function thaw() {
    frozen = false;
    if (dirty.value) schedule();
  }

  open().catch((e: unknown) => console.error("Draft read failed", e));

  return {
    status,
    offered,
    notice,
    savedAt,
    dirty,
    rebase,
    flush,
    keepMine,
    load: () => load().catch((e: unknown) => console.error("Draft load failed", e)),
    discard,
    freeze,
    thaw,
    retry: () => void run(),
  };
}

/** `02:44Z` today (UTC), else `11-10 02:44Z`. */
export function savedWhen(at: string, now: Date = new Date()): string {
  const d = new Date(at);
  return d.toISOString().slice(0, 10) === now.toISOString().slice(0, 10)
    ? `${formatClock(d).slice(0, 5)}Z`
    : formatShort(d);
}

/** The takeover request line (ux 36cca988, 601a32f9): `Draft · saved 02:44:31Z`, no number. */
export function draftLine(s: DraftStatus): string {
  switch (s.kind) {
    case "loading":
    case "new":
      return "new";
    case "saving":
      return "Draft · saving…";
    case "saved":
      return `Draft · saved ${formatClock(new Date(s.at))}Z`;
    case "conflict":
      return "Draft · autosave paused";
    case "failed":
      return s.lastSaved
        ? `Draft · not saved · last saved ${savedWhen(s.lastSaved)}`
        : "Draft · not saved";
  }
}

/** ux (3): the close button names where it returns to and, once saved, the draft. */
export function closeLabel(to: string, savedAt: string | null): string {
  return `Close and return to ${to}${savedAt ? ` · draft saved ${savedWhen(savedAt)}` : ""}`;
}
