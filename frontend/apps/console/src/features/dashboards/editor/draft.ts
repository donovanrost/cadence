import { decode, decoders as d } from "@/api";
import { commandReader, type Command, type LayoutEdit } from "./contracts.ts";

/**
 * The unsaved edits, owned by the browser (plan: stateless edit session). The server replays
 * `commands` onto `baseVersion` for every preview, save and rebase.
 */
export type Draft = Readonly<{ baseVersion: number; commands: readonly Command[] }>;

/** Domain `StatelessAuthoring` refuses more (422 too_many_commands): the editor asks for a save. */
export const MAX_COMMANDS = 256;

export type Appended = { ok: true; draft: Draft } | { ok: false; reason: "too_many_commands" };

function mergeLayouts(a: readonly LayoutEdit[], b: readonly LayoutEdit[]): LayoutEdit[] {
  const byId = new Map(a.map((l) => [l.placement_id, l]));
  for (const l of b) byId.set(l.placement_id, l);
  return [...byId.values()];
}

/**
 * Appends one edit. Consecutive layout edits collapse into one (a gesture or a burst of drags,
 * lead), and so do consecutive updates of the same widget or section (each carries the whole form).
 */
export function append(draft: Draft, next: Command): Appended {
  const commands = [...draft.commands];
  const last = commands.at(-1);
  if (last?.event === "layout" && next.event === "layout")
    commands[commands.length - 1] = {
      event: "layout",
      input: { layouts: mergeLayouts(last.input.layouts, next.input.layouts) },
    };
  else if (
    (last?.event === "update_widget" &&
      next.event === "update_widget" &&
      last.input.placement_id === next.input.placement_id) ||
    (last?.event === "update_section" &&
      next.event === "update_section" &&
      last.input.section_id === next.input.section_id) ||
    (last?.event === "rename" && next.event === "rename")
  )
    commands[commands.length - 1] = next;
  else {
    if (commands.length >= MAX_COMMANDS) return { ok: false, reason: "too_many_commands" };
    commands.push(next);
  }
  return { ok: true, draft: { ...draft, commands } };
}

/** Client-chosen ids for new widgets and sections, so every replay names them the same way. */
export function newId(kind: "dash_widget" | "dash_section"): string {
  return `${kind}_${crypto.randomUUID().replaceAll("-", "")}`;
}

// ---- autosave (same browser only, DECISIONS #76 Q2) -------------------------------------------

const stored = d.object({
  version: d.literal(1),
  base_version: d.integer,
  commands: d.array(commandReader, MAX_COMMANDS),
  saved_at: d.timestamp,
});

const key = (missionId: string, dashboardId: string) =>
  `cadence.console.dashboard-draft.${missionId}.${dashboardId}`;

/** A stored draft, or null when there's none, it's unreadable, or storage is unavailable. */
export function loadDraft(
  missionId: string,
  dashboardId: string,
): (Draft & { savedAt: string }) | null {
  try {
    const raw = localStorage.getItem(key(missionId, dashboardId));
    if (raw === null) return null;
    const parsed = decode(stored, JSON.parse(raw) as unknown);
    if (!parsed.ok || parsed.value.commands.length === 0) return null;
    return {
      baseVersion: parsed.value.base_version,
      commands: parsed.value.commands,
      savedAt: parsed.value.saved_at,
    };
  } catch {
    return null;
  }
}

export function storeDraft(missionId: string, dashboardId: string, draft: Draft): void {
  try {
    if (draft.commands.length === 0) {
      localStorage.removeItem(key(missionId, dashboardId));
      return;
    }
    const value = {
      version: 1,
      base_version: draft.baseVersion,
      commands: draft.commands,
      saved_at: new Date().toISOString(),
    };
    localStorage.setItem(key(missionId, dashboardId), JSON.stringify(value));
  } catch {
    // Storage full or blocked: the draft still lives in memory; nothing to recover from here.
  }
}

export function clearDraft(missionId: string, dashboardId: string): void {
  storeDraft(missionId, dashboardId, { baseVersion: 0, commands: [] });
}
