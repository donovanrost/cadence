import type { MemberStage } from "./api.ts";
import { STAGE_WORDS } from "./words.ts";

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
  "excluded",
];
export const legendLooks = (stages: readonly MemberStage[]): CellLook[] => {
  const present = new Set(stages.map((s) => LOOK_OF[s]));
  return ORDER.filter((l) => present.has(l));
};
