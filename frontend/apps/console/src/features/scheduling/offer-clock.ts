import { formatCountdown, formatHourMinute } from "@/ui";
import { stationCode, type PlanDetail, type PlanPass } from "./api.ts";
import type { SpacecraftName } from "./names.ts";

/**
 * K1 header clock (ux, ScheduleFlow K1): providers publish no day-level cutoff, so the clock is
 * the next offer expiry among passes not yet sent (domain c38bb5de). An expired offer can't be
 * fixed, so the clock never counts up from one: it moves to the next live offer and adds a
 * caution count ("NEXT OFFER EXPIRES T−01:12:40 · KSAT · 1 EXPIRED"); with every unsent offer
 * lapsed it reads "3 OFFERS EXPIRED" with no clock. Absent when nothing is left to send.
 */
export type OfferClock = Readonly<{
  label: string;
  tone: "readout" | "caution";
  /** "KSAT's offer for EARENDIL-012 · SVB-1 · 03:00Z expires at 02:30Z. Send before …" */
  detail: string;
  /** `detail` around the pass: lead + passText + tail (the pass is a link to its bar). */
  lead: string;
  tail: string;
  /** The pass the detail is about, for the link to its bar in B. */
  snapshotId: string | null;
  passText: string | null;
  /** "KSAT T−15:15:51 · Northlight T−18:02:10" with several providers, earliest first. */
  providers: string | null;
  /** "3 more offers expire in the next hour." */
  more: string | null;
}>;

type Plan = Pick<PlanDetail, "provider_freeze" | "passes" | "state">;
type Provider = Readonly<{ id: string | null; name: string | null }>;
const HOUR = 3_600_000;
const providerName = (p: Provider | null) => p?.name ?? p?.id ?? null;

/**
 * Passes not yet sent, when the read can tell: every pass before execution; afterwards the
 * ones whose booking (api 8e) is still never_sent. Null when it can't tell (executing, no 8e).
 */
export function unsentPasses(plan: Pick<PlanDetail, "passes" | "state">): PlanPass[] | null {
  if (plan.state === "draft" || plan.state === "pending_approval") return [...plan.passes];
  if (plan.passes.some((p) => p.booking))
    return plan.passes.filter((p) => p.booking?.state === "never_sent");
  return null;
}

const expiry = (p: PlanPass) => (p.expires_at ? Date.parse(p.expires_at) : null);

/** Expired unsent offers lead Demand like rejections (ux). */
export function expiredRows(plan: Pick<PlanDetail, "passes" | "state">, now: Date) {
  return (unsentPasses(plan) ?? []).flatMap((p) => {
    const at = expiry(p);
    if (at === null || at > now.getTime()) return [];
    return [
      {
        snapshotId: p.snapshot_id,
        spacecraftId: p.spacecraft_id,
        sentence: `Expired · ${stationCode(p.station)} ${p.starts_at.slice(11, 16)}Z: the offer lapsed at ${formatHourMinute(new Date(at))} before it was sent.`,
        next: "replan" as const,
        code: null,
      },
    ];
  });
}

export function offerClock(
  plan: Plan,
  nameOf: (id: string | null) => SpacecraftName | null,
  now: Date,
): OfferClock | null {
  const freeze = plan.provider_freeze;
  if (!freeze) return null;
  const t = now.getTime();
  const byProvider = [...(freeze.by_provider ?? [])].sort(
    (a, b) => Date.parse(a.at) - Date.parse(b.at),
  );
  /** A pass's provider: the freeze's, or the by-provider entry whose earliest expiry it is. */
  const providerOf = (p: PlanPass): Provider | null =>
    p.snapshot_id === freeze.snapshot_id
      ? freeze.provider
      : (byProvider.find((b) => p.expires_at !== null && b.at === p.expires_at)?.provider ?? null);

  const unsent = (unsentPasses(plan) ?? []).filter((p) => expiry(p) !== null);
  const known = unsent.length > 0;
  const expired = known
    ? unsent.filter((p) => (expiry(p) ?? 0) <= t)
    : Date.parse(freeze.at) <= t
      ? plan.passes.filter((p) => p.snapshot_id === freeze.snapshot_id)
      : [];
  const live = known
    ? unsent.filter((p) => (expiry(p) ?? 0) > t).sort((a, b) => (expiry(a) ?? 0) - (expiry(b) ?? 0))
    : [];
  // Without per-pass expiries, the freeze itself is the next offer when it's still ahead.
  const fromFreeze = !known && Date.parse(freeze.at) > t;
  const next =
    live[0] ??
    (fromFreeze ? plan.passes.find((p) => p.snapshot_id === freeze.snapshot_id) : undefined);
  const nextAt = next ? (expiry(next) ?? Date.parse(freeze.at)) : null;
  const subject = next ?? expired[0] ?? null;

  const passText = subject
    ? [
        nameOf(subject.spacecraft_id)?.name ?? subject.spacecraft_id ?? "unknown spacecraft",
        stationCode(subject.station),
        formatHourMinute(new Date(subject.starts_at)),
      ].join(" · ")
    : null;
  const who = providerName(subject ? providerOf(subject) : freeze.provider) ?? "The provider";
  const subjectAt = subject ? (expiry(subject) ?? Date.parse(freeze.at)) : Date.parse(freeze.at);
  const lead = `${who}'s offer${passText ? " for " : ""}`;
  const tail = next
    ? ` expires at ${formatHourMinute(new Date(subjectAt))}. Send before then, or that pass can't be booked.`
    : ` expired at ${formatHourMinute(new Date(subjectAt))}. That pass can't be booked; re-plan to replace it.`;

  const lapsed = expired.length;
  const nextWho = next ? providerName(providerOf(next)) : null;
  const label =
    next && nextAt !== null
      ? [
          `Next offer expires ${formatCountdown(new Date(nextAt), now)}`,
          nextWho,
          lapsed > 0 ? `${lapsed} expired` : null,
        ]
          .filter((p): p is string => p !== null)
          .join(" · ")
      : `${lapsed} ${lapsed === 1 ? "offer" : "offers"} expired`;
  const liveProviders = byProvider.filter((b) => Date.parse(b.at) > t);
  const soon = live.slice(1).filter((p) => (expiry(p) ?? 0) - t <= HOUR).length;
  return {
    label,
    tone: !next || lapsed > 0 || (nextAt !== null && nextAt - t < HOUR) ? "caution" : "readout",
    detail: `${lead}${passText ?? ""}${tail}`,
    lead,
    tail,
    snapshotId: subject ? subject.snapshot_id : null,
    passText,
    providers:
      liveProviders.length > 1
        ? liveProviders
            .map(
              (b) => `${providerName(b.provider) ?? "?"} ${formatCountdown(new Date(b.at), now)}`,
            )
            .join(" · ")
        : null,
    more:
      soon === 0
        ? null
        : `${soon} more ${soon === 1 ? "offer expires" : "offers expire"} in the next hour.`,
  };
}
