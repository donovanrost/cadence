import { formatCount, formatHourMinute, formatShort, plural } from "@/ui";
import type { DataSource } from "./api.ts";
import type { BindingEvent, BlastRadius, MissionBinding } from "./bindings.ts";

/** ux U53 (DECISIONS #90): the words for switching a platform-wide binding. */
export const ADMIN_ONLY = "Only platform admins in admin mode can switch platform bindings.";
export const PLATFORM_HIDDEN =
  "Platform-wide bindings are hidden. They apply to every mission without its own binding.";
export const COUNTS_UNAVAILABLE =
  "Cadence couldn't count the missions and live passes this affects, so it can't be switched now. Try again in a moment.";
export const REASON_HELP = "Recorded with your name and the time.";
export const REASON_BLANK = "Give a reason first.";

/**
 * What the binding carries, for the sentences: the logical source key without its `default_` /
 * `default_flight_` prefix, underscores as spaces (`default_flight_telemetry` → "telemetry").
 * ux names telemetry only; this keeps the same shape for limits, events and observables.
 */
export function bindingNoun(logicalSource: string): string {
  return logicalSource.replace(/^default_(flight_)?/, "").replaceAll("_", " ");
}

const missions = (n: number) => plural(n, "mission");

export const sheetTitle = (name: string, affected: number) =>
  `Switch ${name} for ${missions(affected)}?`;

/**
 * "This changes telemetry for all 12 missions that use it. They'll read from <to> instead of <from>."
 * Both sides are display names (qa: never a name against an id); `fromName` is the picker list's
 * name for the current source, the server's from.display_name standing in.
 */
export function blastLine(
  r: BlastRadius,
  to: string | null,
  fromName: string | null = null,
): string {
  const n = r.affected_missions;
  const who =
    n === 1 ? "the one mission that uses it" : `all ${formatCount(n)} missions that use it`;
  const first = `This changes ${bindingNoun(r.binding.logical_source)} for ${who}.`;
  const from = fromName ?? r.binding.from.display_name;
  return to && from ? `${first} They'll read from ${to} instead of ${from}.` : first;
}

/** §4: a time today is `03:10Z`; another day `11-13 23:58Z`. */
const when = (aos: string, now: Date) => {
  const at = new Date(aos);
  return at.toISOString().slice(0, 10) === now.toISOString().slice(0, 10)
    ? formatHourMinute(at)
    : formatShort(at);
};

/** The crit line, or null with no live pass: up to 3 named, "and K more" for the rest. */
export function livePassesLine(r: BlastRadius, now: Date): string | null {
  const { total, first } = r.live_passes;
  if (total === 0) return null;
  const noun = bindingNoun(r.binding.logical_source);
  const named = first
    .slice(0, 3)
    .map((p) =>
      [p.spacecraft_name, p.station_code ? `${p.station_code} ${when(p.aos, now)}` : null]
        .filter((x) => x !== null)
        .join(" · "),
    );
  const more = total - named.length;
  const list = `${named.join(", ")}${more > 0 ? ` and ${formatCount(more)} more` : ""}`;
  return total === 1
    ? `1 pass is live right now, and its ${noun} switches mid-pass: ${list}.`
    : `${formatCount(total)} passes are live right now, and their ${noun} switches mid-pass: ${list}.`;
}

const passes = (n: number) => plural(n, "live pass", "live passes");

/** After 409 blast_radius_changed: the caution line above the updated lines. */
export const changedLine = (r: BlastRadius) =>
  `This changed while you were confirming: it now affects ${missions(r.affected_missions)} and ${passes(r.live_passes.total)}.`;

/** The outcome, from the counts the server recorded. */
export const outcomeLine = (name: string, to: string, affected: number) =>
  `Switched ${name} to ${to}. ${affected === 1 ? "One mission reads" : `${missions(affected)} read`} from it now.`;

/** Two reads that differ in what the operator confirms: the typed name is cleared (ux). */
export const countsDiffer = (a: BlastRadius | null, b: BlastRadius | null) =>
  a !== null &&
  b !== null &&
  (a.affected_missions !== b.affected_missions || a.live_passes.total !== b.live_passes.total);

/** The switch is offered once a reason is given, the name typed exactly, and another target picked. */
export const switchReady = (
  f: Readonly<{ reason: string; typed: string; name: string; target: string; current: string }>,
) => f.reason.trim() !== "" && f.typed === f.name && f.target !== "" && f.target !== f.current;

/**
 * Why the Switch is still disabled: the first missing field in the sheet's order, top to bottom
 * (ux): the source picker, then the reason, then the typed name.
 */
export function blockedReason(
  f: Readonly<{ reason: string; typed: string; name: string; target: string; current: string }>,
): string {
  if (f.target === "" || f.target === f.current) return "Choose another source.";
  if (f.reason.trim() === "") return REASON_BLANK;
  return `Type ${f.name} to confirm.`;
}

export const switchLabel = (affected: number) => `Switch for ${missions(affected)}`;

/** Platform rows show only when the toggle is on (off by default). */
export const visibleBindings = (rows: readonly MissionBinding[], showPlatform: boolean) =>
  showPlatform ? rows : rows.filter((b) => !b.shared);

const name = (x: { display_name: string | null } | null) => x?.display_name ?? "an unknown source";

/**
 * A binding's history line (actor and time have their own columns). A platform-wide switch reads
 * 'Switched platform binding X from A to B · 12 missions, 3 live passes: “reason”'.
 */
/**
 * What a platform-wide binding can switch to: another active, platform-shared source serving the
 * same logical source. The current one isn't offered (qa); the organization's own sources aren't
 * either (api-ops: 422 platform_target_required).
 */
export const platformTargets = (
  sources: readonly DataSource[],
  current: Readonly<{ data_source_id: string; logical_source: string }> | null,
) =>
  sources.filter(
    (s) =>
      s.id !== current?.data_source_id &&
      s.shared === true &&
      s.state !== "disabled" &&
      s.logical_source?.key === current?.logical_source,
  );

/**
 * Who changed a binding. Outside admin mode a platform-wide binding's events come without the
 * actor (api-ops): a platform admin made them, so say that rather than "Cadence".
 */
export function historyWho(e: BindingEvent, shared: boolean): string {
  if (e.actor?.name) return e.actor.name;
  return shared ? "A platform admin" : "Cadence";
}

export function eventLine(e: BindingEvent, logicalSource: string): string {
  if (typeof e.kind !== "string") return e.kind.unrecognized.replaceAll("_", " ");
  switch (e.kind) {
    case "switched": {
      if (e.affected_missions !== null && e.live_passes_total !== null)
        return `Switched platform binding ${logicalSource} from ${name(e.from)} to ${name(e.to)} · ${missions(e.affected_missions)}, ${passes(e.live_passes_total)}: “${e.reason ?? ""}”`;
      return `Switched from ${name(e.from)} to ${name(e.to)}.${e.reason ? ` “${e.reason}”` : ""}`;
    }
    case "registered":
      return `Bound to ${name(e.to)}.`;
    case "changed":
      return `Changed to read from ${name(e.to)}.`;
    case "enabled":
      return "Enabled.";
    case "disabled":
      return "Disabled.";
    case "superseded":
      return "Superseded.";
  }
}
