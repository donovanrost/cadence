import { computed, nextTick, onBeforeUnmount, shallowRef, watch, type Ref } from "vue";
import { describeApiError } from "@/api/index.ts";
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
  /** 409 command_draft_changed: another tab or device saved; autosave stops until a choice. */
  | { kind: "conflict"; theirs: DraftSaved | null }
  | { kind: "failed"; message: string };

export type DraftNotice = Readonly<{ tone: "info" | "caution"; text: string }>;

/**
 * Compose's autosave (commanding.md §Compose draft, ux 36cca988): one current draft per user per
 * mission. `resume` restores it on open; otherwise an existing draft is offered (Resume) and
 * replaced only once this request has something in it. Submitting freezes autosave and hands the
 * last saved revision to POST /command-groups, so the server deletes exactly that draft.
 */
export function useComposeDraft(
  missionId: Ref<string>,
  fields: Ref<ComposeFields>,
  apply: (restored: Restored) => void,
  resume: boolean,
) {
  const status = shallowRef<DraftStatus>({ kind: "loading" });
  /** A saved draft found on open and not resumed: offered until this request replaces it. */
  const offered = shallowRef<StoredDraft | null>(null);
  const notice = shallowRef<DraftNotice | null>(null);
  /** The revision PUT expects: the one we last saved or adopted. */
  let revision: number | null = null;
  /** True once this session resumed or saved the draft: a blank form then still saves. */
  let owned = false;
  let lastJson: string | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let inFlight: Promise<void> | null = null;
  let frozen = false;

  const json = computed(() => JSON.stringify(toDocument(fields.value)));

  async function adopt(stored: StoredDraft) {
    const r = await restoreDraft(missionId.value, stored);
    if (!r.ok) {
      notice.value = { tone: "caution", text: r.message };
      return false;
    }
    apply(r.value);
    await nextTick();
    revision = stored.revision;
    owned = true;
    offered.value = null;
    lastJson = json.value;
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
      status.value = {
        kind: "failed",
        message: `Couldn't read your saved draft: ${describeApiError(r.error)}`,
      };
    } else if (r.value === null) {
      status.value = { kind: "new" };
    } else if (resume) {
      if (!(await adopt(r.value))) status.value = { kind: "new" };
    } else {
      offered.value = r.value;
      revision = r.value.revision;
      status.value = { kind: "new" };
    }
    lastJson ??= json.value;
  }

  async function save() {
    timer = null;
    if (frozen || status.value.kind === "conflict" || status.value.kind === "loading") return;
    const body = toDocument(fields.value);
    const text = JSON.stringify(body);
    if (text === lastJson || (!owned && isBlank(fields.value))) return;
    status.value = { kind: "saving" };
    const r = await saveComposeDraft(missionId.value, body, revision);
    if (r.ok) {
      revision = r.value.revision;
      owned = true;
      offered.value = null;
      lastJson = text;
      status.value = { kind: "saved", at: r.value.saved_at };
      if (json.value !== lastJson) schedule();
    } else if (r.error.kind === "conflict" && r.error.code === "command_draft_changed") {
      status.value = { kind: "conflict", theirs: changedBy(r.error.details) };
    } else {
      status.value = { kind: "failed", message: `Draft not saved: ${describeApiError(r.error)}` };
    }
  }

  function run() {
    inFlight = save()
      .catch((e: unknown) => console.error("Draft save failed", e))
      .finally(() => (inFlight = null));
  }
  function schedule() {
    if (timer !== null) clearTimeout(timer);
    timer = setTimeout(() => (inFlight ? inFlight.then(run) : run()), AUTOSAVE_MS);
  }
  watch(json, () => {
    if (lastJson !== null) schedule();
  });
  // Closing within the debounce still keeps the last edit.
  onBeforeUnmount(() => {
    if (timer === null) return;
    clearTimeout(timer);
    if (!frozen) run();
  });

  /** Conflict: overwrite the other save with this tab's state. */
  function keepMine() {
    const s = status.value;
    if (s.kind !== "conflict") return;
    revision = s.theirs?.revision ?? null;
    status.value = { kind: "saving" };
    lastJson = null;
    run();
  }
  /** Conflict, or the offered draft: load the stored version into Compose. */
  async function load() {
    const r = await fetchComposeDraft(missionId.value);
    if (!r.ok) {
      status.value = {
        kind: "failed",
        message: `Couldn't read your saved draft: ${describeApiError(r.error)}`,
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
    const r = await discardComposeDraft(missionId.value);
    if (!r.ok) {
      notice.value = {
        tone: "caution",
        text: `Couldn't discard the draft: ${describeApiError(r.error)}`,
      };
      return false;
    }
    revision = null;
    owned = false;
    offered.value = null;
    lastJson = json.value;
    status.value = { kind: "new" };
    return true;
  }

  /** Before submit: stop autosave, let a save in flight land, and return the revision to delete. */
  async function freeze(): Promise<number | null> {
    frozen = true;
    if (timer !== null) clearTimeout(timer);
    timer = null;
    await inFlight;
    return owned ? revision : null;
  }
  /** After a rejected submit: autosave resumes with any edits since. */
  function thaw() {
    frozen = false;
    if (json.value !== lastJson) schedule();
  }

  open().catch((e: unknown) => console.error("Draft read failed", e));

  return {
    status,
    offered,
    notice,
    owned: computed(() => status.value.kind === "saved" && owned),
    keepMine,
    load: () => load().catch((e: unknown) => console.error("Draft load failed", e)),
    discard,
    freeze,
    thaw,
    retry: () => {
      lastJson = null;
      run();
    },
  };
}

/** `02:44Z` today (UTC), else `11-10 02:44Z`. */
export function savedWhen(at: string, now: Date = new Date()): string {
  const d = new Date(at);
  return d.toISOString().slice(0, 10) === now.toISOString().slice(0, 10)
    ? `${formatClock(d).slice(0, 5)}Z`
    : formatShort(d);
}

/** The takeover request line (ux 36cca988): `Draft · saved 02:44:31Z`, no number (U25). */
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
      return "Draft · saved elsewhere";
    case "failed":
      return "Draft · not saved";
  }
}
