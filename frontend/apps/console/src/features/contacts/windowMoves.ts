import type { Pass } from "./api.ts";

/**
 * U56 window_moved, the pass history line (ux's table, in step with api's Timeline sentence):
 * "later"/"earlier", never "+30 s"; times to the second, because a 30 s move vanishes at minutes.
 */
type Revision = NonNullable<Pass["window_moves"]>[number];
type Window = NonNullable<Revision["before"]>;
/** A revision that moved the window: both its windows known. */
export type WindowMove = Revision & Readonly<{ before: Window; after: Window }>;

/**
 * The moves among a pass's provider revisions: one without a before or after window (qa 11-16:
 * an approval_required revision from 11-13 carries none) didn't move anything we can say.
 */
export function windowMoves(revisions: readonly Revision[] | undefined): WindowMove[] {
  return (revisions ?? []).flatMap((r) =>
    r.before && r.after ? [{ ...r, before: r.before, after: r.after }] : [],
  );
}

/** "30 s", "2 min", "1 min 30 s". */
export function moveDuration(ms: number): string {
  const s = Math.round(Math.abs(ms) / 1000);
  if (s < 60) return `${s} s`;
  const min = Math.floor(s / 60);
  const rest = s % 60;
  return rest ? `${min} min ${rest} s` : `${min} min`;
}

const hms = (iso: string) => iso.slice(11, 19);
const md = (iso: string) => iso.slice(5, 10);
/**
 * A window to the second (ux U56): no date on the move's own day; once when both ends share
 * another day ("11-15 00:00:00–00:08:00Z"); on both ends across midnight.
 */
function span(w: { starts_at: string; ends_at: string }, day: string): string {
  const d0 = w.starts_at.slice(0, 10);
  const d1 = w.ends_at.slice(0, 10);
  if (d0 === day && d1 === day) return `${hms(w.starts_at)}–${hms(w.ends_at)}Z`;
  if (d0 === d1) return `${md(w.starts_at)} ${hms(w.starts_at)}–${hms(w.ends_at)}Z`;
  return `${md(w.starts_at)} ${hms(w.starts_at)}–${md(w.ends_at)} ${hms(w.ends_at)}Z`;
}

/**
 * "Northlight moved this pass 30 s later: now 12:11:27–12:19:27Z (was 12:10:57–12:18:57Z)."
 * AOS or LOS only: "…moved this pass's LOS 60 s later…"; both ends differently: "…changed this
 * pass's window: now … (was …)."
 */
export function windowMoveLine(m: WindowMove, provider: string | null): string {
  const p = provider ?? "The provider";
  const day = m.at.slice(0, 10);
  const dStart = Date.parse(m.after.starts_at) - Date.parse(m.before.starts_at);
  const dEnd = Date.parse(m.after.ends_at) - Date.parse(m.before.ends_at);
  const way = (d: number) => `${moveDuration(d)} ${d > 0 ? "later" : "earlier"}`;
  const tail = `: now ${span(m.after, day)} (was ${span(m.before, day)}).`;
  if (dStart !== 0 && dStart === dEnd) return `${p} moved this pass ${way(dStart)}${tail}`;
  if (dStart === 0 && dEnd !== 0) return `${p} moved this pass's LOS ${way(dEnd)}${tail}`;
  if (dEnd === 0 && dStart !== 0) return `${p} moved this pass's AOS ${way(dStart)}${tail}`;
  return `${p} changed this pass's window${tail}`;
}

/** While live and the end moved: "Cadence now listens until 12:19:27Z." (newest move only). */
export function listensUntil(m: WindowMove, live: boolean): string | null {
  const ended = Date.parse(m.after.ends_at) !== Date.parse(m.before.ends_at);
  return live && ended ? `Cadence now listens until ${m.after.ends_at.slice(11, 19)}Z.` : null;
}
