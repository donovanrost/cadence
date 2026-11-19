import type { OpState } from "@/ui";
import type { Pass } from "@/features/contacts/index.ts";

/**
 * The one UI contact state model (ScheduleFlow.md: Opportunity → Drafted → Requested → Confirmed →
 * In contact → Realized; off-ramps Partial, Rejected, Missed, Unknown, Canceling → Canceled), decoded from the
 * passes read that lives in features/contacts. Screens use `contactState`, never raw lifecycles.
 */
export type ContactState =
  | "opportunity"
  | "drafted"
  /** Cadence is still sending the request (ux: a word claims only what's done). */
  | "requesting"
  | "requested"
  | "confirmed"
  | "in_contact"
  | "ended"
  | "realized"
  | "partial"
  | "rejected"
  | "missed"
  | "unknown"
  /** Cancel sent, provider hasn't confirmed it (ux: in-flight states say -ing). */
  | "canceling"
  | "canceled";

/**
 * Booked-contact decoding (reservation lifecycle + provider pass phase). `realized` / `partial`
 * need flown data (S9) and `missed` needs the scheduled contact's expiry, so none come from this read
 * yet: a completed reservation reads as `ended` (not verified), failed as unknown.
 */
export function contactState(p: Pick<Pass, "state" | "pass_phase">): ContactState {
  switch (p.state) {
    case "requesting":
      return "requesting";
    case "pending":
      return "requested";
    case "confirmed":
      return p.pass_phase === "pass" ? "in_contact" : "confirmed";
    case "active":
      return "in_contact";
    case "completed":
      // ux: "Ended · not verified" until S9 brings flown data; never green without evidence.
      return "ended";
    case "rejected":
      return "rejected";
    case "canceling":
      return "canceling";
    case "canceled":
      return "canceled";
    case "unknown":
    case "failed":
      return "unknown";
  }
}

export const contactStateWord: Readonly<Record<ContactState, string>> = {
  opportunity: "Opportunity",
  drafted: "Drafted",
  requesting: "Requesting",
  requested: "Requested",
  confirmed: "Confirmed",
  in_contact: "In contact",
  ended: "Ended · not verified",
  realized: "Realized",
  partial: "Partial",
  rejected: "Rejected",
  missed: "Missed",
  unknown: "Unknown",
  canceling: "Canceling",
  canceled: "Canceled",
};

/** Progress states are gray; only outcomes carry status (CommandFlow M1 rule, reused for contacts). */
export function contactOpState(state: ContactState): OpState {
  switch (state) {
    case "in_contact":
      return "live";
    case "realized":
      return "nominal";
    case "partial":
    case "rejected":
      return "caution";
    case "missed":
      return "crit";
    case "unknown":
      return "stale";
    case "opportunity":
    case "drafted":
    case "requesting":
    case "requested":
    case "confirmed":
    case "ended":
    case "canceling":
    case "canceled":
      return "neutral";
  }
}

/** UI source label (ux U22 Q7): `<SOURCE> · <KIND>`; the simulator always says so. */
export function sourceLabel(source: Pass["source"], kind: "window" | "contact"): string {
  const who = source.synthetic ? "Simulator" : (source.provider_name ?? source.provider);
  const what = source.synthetic
    ? "synthetic window"
    : kind === "window"
      ? "provider window"
      : "provider booking";
  return `${who} · ${what}`.toUpperCase();
}
