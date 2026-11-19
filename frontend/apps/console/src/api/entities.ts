import {
  knownText,
  object,
  string,
  timestamp,
  token,
  vocabularyText,
  type Decoded,
  type Reader,
  type Unrecognized,
} from "./decode.ts";
import { scid, spacecraftId, stationId } from "./ids.ts";

/**
 * Shared entity decoders (typing plan §12 A5, docs/apogee/typing-audit.md §1.5): one reader per
 * server entity instead of a copy per feature that disagrees with the others. Servers differ on
 * whether they omit a key or send null, so optional facts read as null either way.
 */

/** Absent or null both read as null (servers vary); anything else must satisfy `read`. */
export const orNull =
  <T>(read: Reader<T>): Reader<T | null> =>
  (value, path = "") =>
    value === undefined || value === null ? null : read(value, path);

/**
 * Who did something. The server sends `user`, `service` (service identities) and `system`
 * (automatic runs); an unknown kind keeps its raw word. `id` and `name` are null when the
 * server doesn't know them (a deleted user, an older record).
 */
export const actorKinds = ["user", "service", "system"] as const;
export type ActorKind = (typeof actorKinds)[number];
export const actor = object({
  kind: orNull(knownText(actorKinds)),
  id: orNull(string),
  name: orNull(string),
});
export type Actor = Decoded<typeof actor>;

/** The actor kind as the server's word (`user`, `service`, …), for exports and technical text. */
export const actorKindWord = (k: Actor["kind"]): string | null =>
  k === null ? null : typeof k === "string" ? k : k.unrecognized;

/** The actor's name for a sentence, or `fallback` ("Not recorded") when nobody is known. */
export const actorName = (a: Actor | null | undefined, fallback = "Not recorded") =>
  a?.name ?? fallback;

/** A spacecraft as other entities reference it: id always; name and SCID when sent. */
export const spacecraftRef = object({
  /** §12C: a SpacecraftId, so it keys spacecraft reads and routes directly. */
  id: spacecraftId,
  name: orNull(string),
  /** §12C: a Scid (the routes' address), so it reaches an ops.spacecraft link as is. */
  scid: orNull(scid),
});
export type SpacecraftRef = Decoded<typeof spacecraftRef>;

/**
 * A ground station as other entities reference it. `ref` is the provider's own reference; `id`,
 * `code` and `name` are Cadence's when the station is known to the mission.
 */
export const stationRef = object({
  ref: orNull(string),
  /** §12C: a StationId (never a code), so it keys the stations index directly. */
  id: orNull(stationId),
  code: orNull(string),
  name: orNull(string),
});
export type StationRef = Decoded<typeof stationRef>;

/** Organization roles (DECISIONS #2): one closed vocabulary and one set of words for it. */
export const roles = ["organization_admin", "member"] as const;
export type Role = (typeof roles)[number];
export const role: Reader<Role | Unrecognized> = knownText(roles);
export const roleWords: Readonly<Record<Role, string>> = {
  organization_admin: "Org admin",
  member: "Member",
};
/** `Org admin` / `Member`, or the server's own word for a role the console doesn't know. */
export const roleText = (r: Role | Unrecognized) => vocabularyText(r, roleWords);

/** Invitation lifecycle states across People, Account and the admin area. */
export const invitationStates = [
  "pending",
  "expired",
  "declined",
  "accepted",
  "revoked",
  "withdrawn",
] as const;
export type InvitationState = (typeof invitationStates)[number];
export const invitationState = knownText(invitationStates);

/** Who sent an invitation, when known. */
export const invitedBy = orNull(object({ name: string }));

/** The fields every invitation read shares; each endpoint adds its own (organization, status…). */
export const invitationCore = {
  id: token,
  role,
  invited_by: invitedBy,
  expires_at: orNull(timestamp),
} as const;
