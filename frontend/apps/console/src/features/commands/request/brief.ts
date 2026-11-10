import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";
import { formatDayTime } from "@/ui";

/**
 * Approve A1 "What changes" (CommandFlow; commanding.md §brief): each argument's requested value
 * against its current value on each target (`1 → 3`, or a histogram when targets differ), and
 * callouts for targets a prior request set differently. Current values exist only where the
 * catalog links the argument to a point; otherwise "no current value known". Values are JSON text.
 */
const briefReader = d.object({
  command_request_id: d.token,
  spacecraft_id: d.token,
  arguments: d.array(
    d.object({
      name: d.string,
      value_json: d.string,
      current: d.nullable(
        d.object({
          point: d.nullable(d.string),
          value_json: d.nullable(d.string),
          at: d.nullable(d.timestamp),
          reason: d.nullable(d.token),
        }),
      ),
      current_basis: d.token,
    }),
    200,
  ),
  prior_requests: d.array(
    d.object({
      command_request_id: d.token,
      command_group_id: d.nullable(d.token),
      arguments_json: d.string,
      state: d.token,
      requested_at: d.timestamp,
      requested_by: d.nullable(
        d.object({ kind: d.token, id: d.nullable(d.token), name: d.nullable(d.string) }),
      ),
    }),
    5,
  ),
});
export type Brief = Decoded<typeof briefReader>;

export function fetchBrief(
  missionId: string,
  requestId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Brief>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/command-requests/${encodeURIComponent(requestId)}/brief`,
    briefReader,
    signal ? { signal } : {},
  );
}

export type ArgChange = Readonly<{
  name: string;
  to: string;
  /** "1", "1 ×6 · 0 ×2 · no value yet ×2", or null when no target has a known current value. */
  from: string | null;
  note: string | null;
}>;

/** One argument across targets: requested value, current values tallied, and why one is missing. */
export function argChanges(briefs: readonly Brief[]): ArgChange[] {
  const first = briefs[0];
  if (!first) return [];
  return first.arguments.map((arg, i) => {
    const per = briefs.map((b) => b.arguments[i]);
    const basis = per.find((a) => a)?.current_basis ?? "none";
    if (basis === "none")
      return { name: arg.name, to: arg.value_json, from: null, note: "no current value known" };
    if (basis === "unavailable")
      return {
        name: arg.name,
        to: arg.value_json,
        from: null,
        note: "current value can't be read: the request's revision isn't active",
      };
    const tally = new Map<string, number>();
    for (const a of per) {
      const v =
        a?.current?.value_json ?? (a?.current?.reason === "no_sample" ? "no value yet" : "unknown");
      tally.set(v, (tally.get(v) ?? 0) + 1);
    }
    const entries = [...tally.entries()].sort((x, y) => y[1] - x[1]);
    const from =
      entries.length === 1 && entries[0]
        ? entries[0][0]
        : entries.map(([v, n]) => `${v} ×${n}`).join(" · ");
    return { name: arg.name, to: arg.value_json, from, note: null };
  });
}

const SET_STATES = new Set([
  "verified",
  "executed",
  "no_verifier",
  "released",
  "queued",
  "approval_pending",
]);

/**
 * "EARENDIL-117 was set to {"mode":1} on 14 Sep 10:02Z by Mira K. This overwrites that." for
 * targets whose newest prior request (sent or still pending) had different values.
 */
export function overwriteCallouts(
  briefs: readonly Brief[],
  argsJson: string,
  nameOf: (spacecraftId: string) => string,
  max = 3,
): string[] {
  const norm = (j: string) => j.replace(/\s+/g, "");
  const hits = briefs.flatMap((b) => {
    const prior = b.prior_requests.find((p) => SET_STATES.has(p.state));
    return prior && norm(prior.arguments_json) !== norm(argsJson) ? [{ b, prior }] : [];
  });
  const lines = hits
    .slice(0, max)
    .map(
      ({ b, prior }) =>
        `${nameOf(b.spacecraft_id)} was set to ${prior.arguments_json} on ${formatDayTime(new Date(prior.requested_at))}${prior.requested_by?.name ? ` by ${prior.requested_by.name.replace(/[.]+$/, "")}` : ""}. This overwrites that.`,
    );
  return hits.length > max
    ? [...lines, `And ${hits.length - max} more targets set differently before.`]
    : lines;
}
