import { short, type Attention } from "./attention.ts";

/** U91: while nothing runs, passes can't start (said only with applied_generation null). */
export const NO_TELEMETRY =
  "Until this is fixed, passes can't start, so their telemetry isn't received. Cadence keeps trying to start a pass while its window is open, so it receives telemetry from the moment this is fixed.";

/** "EARENDIL-004's SVA pass", dropping what's missing; never an id (U91). */
function whosePass(name: string | null, station: string | null): string {
  if (name && station) return `${name}'s ${station} pass`;
  if (name) return `${name}'s pass`;
  return station ? `The ${station} pass` : "The pass";
}

/**
 * U91: the pass at stake. Not started yet: "The next pass starts at 15:10Z: EARENDIL-004, SVA."
 * Started before this: its telemetry is kept. In its window but not started: it isn't received.
 * The station reads its code, else its name (U47's pass label).
 */
export function nextPassLine(np: Attention["next_pass"], now: Date = new Date()): string | null {
  if (!np) return null;
  const station = np.station ? (np.station.code ?? np.station.name) : null;
  const pass = whosePass(np.spacecraft_name, station);
  if (np.started === true)
    return `${pass} started before this, so its telemetry is kept and processed once the runtime is back.`;
  if (np.in_progress)
    return np.started === false
      ? `${pass} couldn't start, so its telemetry isn't being received.`
      : `${pass} is in progress.`;
  const who = [np.spacecraft_name, station].filter((p): p is string => Boolean(p)).join(", ");
  return `The next pass starts at ${short(np.starts_at, now)}${who ? `: ${who}` : ""}.`;
}
