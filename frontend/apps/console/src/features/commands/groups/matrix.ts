import type { MemberStage } from "./api.ts";
import { STAGE_WORDS } from "./words.ts";
import { targetExpired } from "./expiry.ts";
import type { GroupTarget } from "./show.ts";

/**
 * U1 Targets matrix cell looks (CommandFlow C3): verified nominal-dim, executed text-3 fill,
 * radiating white + ring, queued text-3 outline, no ACK caution fill, failed crit + ring, excluded
 * dashed. Progress stays gray; only outcomes carry status.
 */
export type CellLook =
  | "verified"
  | "executed"
  | "radiating"
  | "queued"
  | "no_ack"
  | "failed"
  | "excluded"
  | "expired"
  | "unverifiable";

export const LOOK_OF: Readonly<Record<MemberStage, CellLook>> = {
  awaiting_go: "queued",
  queued_for_contact: "queued",
  radiating: "radiating",
  executed: "executed",
  verified: "verified",
  no_verifier: "unverifiable",
  verify_failed: "failed",
  release_failed: "failed",
  indeterminate: "no_ack",
  canceled: "excluded",
  rejected: "excluded",
  excluded: "excluded",
};

export const LOOK_WORDS: Readonly<Record<CellLook, string>> = {
  verified: STAGE_WORDS.verified,
  executed: STAGE_WORDS.executed,
  radiating: STAGE_WORDS.radiating,
  queued: "Queued",
  no_ack: "No ACK",
  failed: "Failed",
  excluded: "Excluded or canceled",
  expired: "Expired",
  unverifiable: "Not verifiable",
};

/** The legend lists the looks present, in pipeline order. */
const ORDER: readonly CellLook[] = [
  "queued",
  "radiating",
  "executed",
  "verified",
  "unverifiable",
  "no_ack",
  "failed",
  "expired",
  "excluded",
];
/** ux U75: an expired target has its own look (dashed, off); else its stage's look. */
export const targetLook = (t: GroupTarget): CellLook =>
  targetExpired(t) ? "expired" : LOOK_OF[t.stage];

export const legendLooks = (targets: readonly GroupTarget[]): CellLook[] => {
  const present = new Set(targets.map(targetLook));
  return ORDER.filter((l) => present.has(l));
};
