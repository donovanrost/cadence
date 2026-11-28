import type { DashboardId } from "@/api/index.ts";
import type { MissionId } from "@/api/index.ts";
import { computed, onScopeDispose, ref, shallowRef, watch, type Ref } from "vue";
import type { ApiError } from "@/api";
import type { Runtime } from "../api.ts";
import * as api from "./api.ts";
import type { Command, CommandCode, Preview, SkippedEvent } from "./contracts.ts";
import { append, clearDraft, loadDraft, storeDraft, type Draft } from "./draft.ts";

export type Conflict = Readonly<{
  currentVersion: number;
  savedBy: string | null;
  savedAt: string | null;
}>;
/**
 * The conflict as the editor shows it. `refused`: the person's own Save or edit was refused with
 * it (an alert); otherwise it arrived on the live channel while they edited, read politely, since
 * an alert would interrupt them mid-edit and their next Save meets the alert anyway (ux #276).
 */
export type ShownConflict = Conflict & Readonly<{ refused: boolean }>;
export type Notice =
  | { kind: "rejected"; message: string }
  | { kind: "skipped"; events: readonly SkippedEvent[] }
  | { kind: "too_many_commands" }
  | { kind: "not_ready"; placements: readonly { placement_id: string | null; message: string }[] }
  | { kind: "failed"; message: string };

/**
 * Edit in place (plan: save model). Owns the browser-held draft, its autosave, the staged
 * preview (live values paused), save, discard, and the "saved by someone else" rebase. The
 * server is stateless: every preview replays the draft onto its base version.
 */
export function useEditSession(
  missionId: Readonly<Ref<MissionId>>,
  dashboardId: Readonly<Ref<DashboardId>>,
  runtime: Readonly<Ref<Runtime>>,
  /** The dashboard's current version, from the viewer read (refreshed on `dashboards`). */
  currentVersion: Readonly<Ref<number | null>>,
) {
  const draft = shallowRef<Draft | null>(null);
  const staged = shallowRef<Preview | null>(null);
  /** The draft `staged` was previewed for: the change list is only true for that draft. */
  const stagedFor = shallowRef<Draft | null>(null);
  const previewing = ref(false);
  const busy = ref(false);
  const notice = shallowRef<Notice | null>(null);
  const resumed = ref(false);
  let controller: AbortController | null = null;
  let generation = 0;

  /** Who saved over this draft and when, once a save or a rebase learned it (409 details). */
  const conflictBy = shallowRef<Conflict | null>(null);
  /** The newest channel `version` push, kept even before a draft exists (noteSaved). */
  const lastSaved = shallowRef<Conflict | null>(null);
  const editing = computed(() => draft.value !== null);
  const dirty = computed(() => (draft.value?.commands.length ?? 0) > 0);
  /** What this save changes; null while the preview for the current draft is pending or failed. */
  const changes = computed(() =>
    staged.value && stagedFor.value === draft.value ? staged.value.changes : null,
  );
  /** Someone saved over the version this draft is based on (ux's callout). */
  const conflict = computed<ShownConflict | null>(() => {
    const d = draft.value;
    if (!d || !dirty.value) return null;
    // Who saved: a refused save's 409, else the push, when it is newer than this draft's base.
    const pushed = lastSaved.value;
    const by =
      conflictBy.value ?? (pushed && pushed.currentVersion > d.baseVersion ? pushed : null);
    // The 409 or the push knows the newest version even when the re-read is slow (qa rerun).
    const current = Math.max(
      currentVersion.value ?? 0,
      staged.value?.current_version ?? 0,
      by?.currentVersion ?? 0,
    );
    if (current <= d.baseVersion) return null;
    return {
      currentVersion: current,
      savedBy: by?.savedBy ?? null,
      savedAt: by?.savedAt ?? null,
      refused: conflictBy.value !== null,
    };
  });

  function persist(next: Draft) {
    draft.value = next;
    storeDraft(missionId.value, dashboardId.value, next);
  }

  async function refresh(next: Draft) {
    controller?.abort();
    const mine = new AbortController();
    controller = mine;
    const id = ++generation;
    previewing.value = true;
    let result: Awaited<ReturnType<typeof api.preview>>;
    try {
      result = await api.preview(
        missionId.value,
        dashboardId.value,
        next,
        runtime.value,
        mine.signal,
      );
    } catch (error) {
      // qa: a newer edit aborts the older preview; that rejection is expected, not an error.
      if (mine.signal.aborted) return;
      throw error;
    } finally {
      if (id === generation) previewing.value = false;
    }
    if (id !== generation || mine.signal.aborted) return;
    if (result.ok) {
      staged.value = result.value;
      stagedFor.value = next;
      return;
    }
    const failure = api.editFailure(result.error, next);
    if (failure.kind === "command" && failure.index === null) {
      notice.value = { kind: "rejected", message: rejectionText(failure.code, failure.field) };
    } else if (failure.kind === "command") {
      // The command the server refused is dropped; the rest of the draft stays.
      const kept = { ...next, commands: next.commands.filter((_, i) => i !== failure.index) };
      persist(kept);
      notice.value = { kind: "rejected", message: rejectionText(failure.code, failure.field) };
      void refresh(kept);
    } else if (failure.kind === "conflict") conflictBy.value = failure;
    else if (failure.kind === "too_many_commands") notice.value = { kind: "too_many_commands" };
    else if (failure.kind === "other")
      notice.value = { kind: "failed", message: failureText(failure.error) };
  }

  /** Enter edit mode: resume a stored draft for this dashboard, else start on the current version. */
  function enter() {
    const storedDraft = loadDraft(missionId.value, dashboardId.value);
    const base = currentVersion.value;
    if (!storedDraft && base === null) return;
    resumed.value = storedDraft !== null;
    const next = storedDraft ?? { baseVersion: base ?? 0, commands: [] };
    draft.value = next;
    notice.value = null;
    void refresh(next);
  }

  function stage(command: Command) {
    const d = draft.value;
    if (!d) return;
    const result = append(d, command);
    if (!result.ok) {
      notice.value = { kind: "too_many_commands" };
      return;
    }
    persist(result.draft);
    void refresh(result.draft);
  }

  function leave() {
    controller?.abort();
    generation++;
    draft.value = null;
    staged.value = null;
    stagedFor.value = null;
    previewing.value = false;
    notice.value = null;
    conflictBy.value = null;
  }

  function discard() {
    clearDraft(missionId.value, dashboardId.value);
    leave();
  }

  async function save(input: { message: string; defaults: { time: boolean; scope: boolean } }) {
    const d = draft.value;
    if (!d || busy.value) return { ok: false as const };
    busy.value = true;
    try {
      const result = await api.save(missionId.value, dashboardId.value, d, {
        ...input,
        runtime: runtime.value,
      });
      if (result.ok) {
        discard();
        return { ok: true as const, ...result.value };
      }
      const failure = api.editFailure(result.error, d);
      if (failure.kind === "conflict") conflictBy.value = failure;
      else if (failure.kind === "not_ready")
        notice.value = { kind: "not_ready", placements: failure.placements };
      else if (failure.kind === "too_many_commands") notice.value = { kind: "too_many_commands" };
      else if (failure.kind === "command")
        notice.value = { kind: "rejected", message: rejectionText(failure.code, failure.field) };
      else notice.value = { kind: "failed", message: failureText(failure.error) };
      return { ok: false as const };
    } finally {
      busy.value = false;
    }
  }

  /** Continue editing: replay my edits onto the newest version; report the ones that no longer apply. */
  async function continueEditing() {
    const d = draft.value;
    if (!d || busy.value) return;
    busy.value = true;
    try {
      const result = await api.rebase(missionId.value, dashboardId.value, d, runtime.value);
      if (!result.ok) {
        notice.value = { kind: "failed", message: failureText(result.error) };
        return;
      }
      const r = result.value;
      persist({ baseVersion: r.base_version, commands: r.applied });
      staged.value = r;
      stagedFor.value = draft.value;
      conflictBy.value = null;
      notice.value = r.skipped.length
        ? { kind: "skipped", events: r.skipped.map((s) => s.event) }
        : null;
    } finally {
      busy.value = false;
    }
  }

  /**
   * Someone saved (the channel's `version` event): remember who and when, so the callout names
   * them before any save of mine is refused (qa: the pushed callout said "Someone").
   */
  function noteSaved(saved: Conflict) {
    lastSaved.value = saved;
  }

  /** Discard mine: drop the draft and keep editing on the newest version. */
  function discardMine() {
    clearDraft(missionId.value, dashboardId.value);
    leave();
    enter();
  }

  // Another dashboard (Save as copy pushes the same route): this draft and preview aren't its.
  // The screen re-enters once the new dashboard's view loads.
  watch([missionId, dashboardId], () => {
    lastSaved.value = null;
    if (draft.value !== null) leave();
  });
  onScopeDispose(() => controller?.abort());
  return {
    draft,
    staged,
    changes,
    previewing,
    busy,
    notice,
    resumed,
    editing,
    dirty,
    conflict,
    enter,
    stage,
    save,
    discard,
    leave,
    continueEditing,
    discardMine,
    noteSaved,
  };
}

function failureText(error: ApiError): string {
  return error.kind === "unauthenticated" ? "Signed out." : error.message;
}

const REJECTION: Readonly<Record<CommandCode, string>> = {
  invalid_type: "That widget type isn't valid.",
  invalid_title: "The title isn't valid.",
  invalid_options: "One of the display options isn't valid.",
  invalid_binding: "The widget's binding isn't valid.",
  forbidden: "You can't edit this dashboard.",
  invalid_input: "That change isn't valid.",
  invalid_defaults: "Those defaults aren't valid.",
  conflict: "The dashboard changed meanwhile.",
  missing_section: "That section no longer exists.",
  missing_placement: "That widget no longer exists.",
  unsupported_widget: "That widget type isn't supported.",
  invalid_widget: "That widget isn't valid.",
  capacity: "This dashboard is at its widget or section limit.",
  duplicate_id: "That widget already exists.",
  unavailable: "The dashboard isn't available.",
  library_item_unavailable:
    "That library widget was retired or removed. Remove it from this dashboard to save.",
  library_version_unavailable: "That library widget doesn't have this version any more.",
  unknown: "The server didn't accept that change.",
  unrecognized: "The server didn't accept that change.",
};
/** Codes whose sentence already says what's wrong: no "(field name)" after it (qa). */
const FIELD_IMPLIED: ReadonlySet<CommandCode> = new Set([
  "library_item_unavailable",
  "library_version_unavailable",
]);
function rejectionText(code: CommandCode, field: string | null): string {
  const base = REJECTION[code];
  return field && !FIELD_IMPLIED.has(code) ? `${base} (${field.replaceAll("_", " ")})` : base;
}
