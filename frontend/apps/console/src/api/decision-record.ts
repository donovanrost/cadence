import {
  boolean,
  DecodeError,
  integer,
  knownText,
  nullable,
  object,
  optional,
  string,
} from "./decode.ts";
import type { Reader } from "./decode.ts";

/**
 * The four-eyes decision record's fields as readers see them (P3, dashboards' shape diff 11-17;
 * DECISIONS #112). Every decision row carries them once its path's P3 step lands, which is in or
 * after the dev reset. Until then the readers are tolerant: each field is optional.
 * TIGHTEN (#227, with or after the dev reset): `admin_mode`, `subject` and `separated_from`
 * become required.
 */
export const decisionKinds = [
  "approved",
  "rejected",
  "sent_back",
  "withdrawn",
  "acknowledged",
  "not_required",
] as const;
export type DecisionKind = (typeof decisionKinds)[number];
/** A future decision value reads as its server word, never as an error. */
export const decisionKind = knownText(decisionKinds);

/** What was decided. The digest is read but never shown (P3 §3, U89). */
export const decisionSubject = object({
  version: optional(nullable(integer)),
  digest: optional(nullable(string)),
});

/** The actor ids the separation check compared against; ids may arrive as numbers. */
export const separatedFrom: Reader<readonly string[]> = (value, path = "") => {
  if (!Array.isArray(value)) throw new DecodeError(path, "array");
  if (value.length > 100) throw new DecodeError(path, "at most 100 items");
  return value.map((id: unknown, i) => {
    if (typeof id === "string") return id;
    if (typeof id === "number" && Number.isInteger(id)) return String(id);
    throw new DecodeError(`${path}[${i}]`, "actor id");
  });
};

/**
 * The contract fields a decision row gains, all optional while readers ship first. Absent and null
 * both read (lists are strict arrays, so one null must never fail a whole screen: fe-ops, #227).
 */
export const decisionRecordFields = {
  subject: optional(nullable(decisionSubject)),
  separated_from: optional(nullable(separatedFrom)),
  admin_mode: optional(nullable(boolean)),
} as const;

/** U89: the ADMIN MODE tag's title and accessible name. Only `true` shows the tag. */
export const ADMIN_MODE_NAME = "Acting as a platform admin, not as a member of this organization.";
