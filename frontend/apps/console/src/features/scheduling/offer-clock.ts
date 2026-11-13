import { formatCountdown, formatHourMinute } from "@/ui";
import { stationCode, type PlanDetail } from "./api.ts";
import type { SpacecraftName } from "./names.ts";

/**
 * K1 header clock (ux, ScheduleFlow K1): providers publish no day-level cutoff, so the clock is
 * the earliest offer expiry among passes not yet sent (domain c38bb5de `provider_freeze`).
 * "NEXT OFFER EXPIRES T−15:15:51 · KSAT", white, caution under 1 h, absent when nothing is left
 * to send. An offer already past says so (approval refuses it).
 */
export type OfferClock = Readonly<{
  label: string;
  tone: "readout" | "caution";
  /** "KSAT's offer for EARENDIL-012 · SVB-1 · 03:00Z expires at 02:30Z. Send before …" */
  detail: string;
  /** `detail` around the pass: lead + passText + tail (the pass is a link to its bar). */
  lead: string;
  tail: string;
  /** The pass that sets the clock, for the link to its bar in B. */
  snapshotId: string | null;
  passText: string | null;
  /** "KSAT T−15:15:51 · Northlight T−18:02:10" with several providers, earliest first. */
  providers: string | null;
  /** "3 more offers expire in the next hour." */
  more: string | null;
}>;

const HOUR = 3_600_000;
const providerName = (p: Readonly<{ id: string | null; name: string | null }>) =>
  p.name ?? p.id ?? "The provider";

export function offerClock(
  plan: Pick<PlanDetail, "provider_freeze" | "passes" | "state">,
  nameOf: (id: string | null) => SpacecraftName | null,
  now: Date,
): OfferClock | null {
  const freeze = plan.provider_freeze;
  if (!freeze) return null;
  const at = new Date(freeze.at);
  const left = at.getTime() - now.getTime();
  const who = providerName(freeze.provider);
  const pass = plan.passes.find((p) => p.snapshot_id === freeze.snapshot_id) ?? null;
  const passText = pass
    ? [
        nameOf(pass.spacecraft_id)?.name ?? pass.spacecraft_id ?? "unknown spacecraft",
        stationCode(pass.station),
        `${formatHourMinute(new Date(pass.starts_at))}`,
      ].join(" · ")
    : null;
  const expired = left <= 0;
  const lead = `${who}'s offer${passText ? " for " : ""}`;
  const tail = expired
    ? ` expired at ${formatHourMinute(at)}. That pass can't be booked.`
    : ` expires at ${formatHourMinute(at)}. Send before then, or that pass can't be booked.`;
  const detail = `${lead}${passText ?? ""}${tail}`;
  const byProvider = [...(freeze.by_provider ?? [])].sort(
    (a, b) => Date.parse(a.at) - Date.parse(b.at),
  );
  const providers =
    byProvider.length > 1
      ? byProvider
          .map((p) => `${providerName(p.provider)} ${formatCountdown(new Date(p.at), now)}`)
          .join(" · ")
      : null;
  // Before execution every selected pass is unsent; after, the read can't tell which (api 8e).
  const unsentAll = plan.state === "draft" || plan.state === "pending_approval";
  const soon = unsentAll
    ? plan.passes.filter((p) => {
        if (!p.expires_at || p.snapshot_id === freeze.snapshot_id) return false;
        const t = Date.parse(p.expires_at) - now.getTime();
        return t > 0 && t <= HOUR;
      }).length
    : 0;
  return {
    label: expired
      ? `Offer expired ${formatCountdown(at, now)} · ${who}`
      : `Next offer expires ${formatCountdown(at, now)} · ${who}`,
    tone: left < HOUR ? "caution" : "readout",
    detail,
    lead,
    tail,
    snapshotId: pass ? pass.snapshot_id : null,
    passText,
    providers,
    more:
      soon === 0
        ? null
        : `${soon} more ${soon === 1 ? "offer expires" : "offers expire"} in the next hour.`,
  };
}
