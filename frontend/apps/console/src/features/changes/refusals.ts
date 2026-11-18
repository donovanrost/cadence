import type { RouteLocationRaw } from "vue-router";
import {
  decoders,
  detailsOf,
  isError,
  spacecraftRef,
  type ApiError,
  type Decoded,
  type Reader,
} from "@/api";
import { formatShort } from "@/ui";
import { failureOutcome, type FailureOutcome } from "./actions.ts";

/**
 * ux U82: '<name> is still in use, so it can't be archived:' (or, at submit or review, '… is in use
 * now, so this change set can't be applied:'), then one line per kind of use, up to three named
 * (links where ux puts them), then '… and N more'. Unnamed uses only add to the count. Never an id.
 * The details are api's 409 in_use (domain 16ee2ed00), the same at stage, submit and review.
 */
const { array, integer, nullable, object, oneOf, string, timestamp, token } = decoders;

const named = object({ id: token, name: string });
const count = <T>(item: Reader<T>) => object({ count: integer, items: array(item, 3) });
const details = object({
  entity: decoders.optional(
    object({ kind: oneOf(["transport", "ground_station"]), id: token, name: nullable(string) }),
  ),
  uses: object({
    routes: count(
      object({
        routing_rule_id: token,
        name: nullable(string),
        spacecraft: spacecraftRef,
        station: nullable(
          object({
            id: token,
            // free-text: the station's short code, an identifier (U25), shown as written.
            code: nullable(string),
            name: nullable(string),
          }),
        ),
        direction: oneOf(["downlink", "uplink"]),
      }),
    ),
    profile_routes: count(object({ profile: named, rule_id: token, label: nullable(string) })),
    booked_passes: object({ count: integer, next_at: nullable(timestamp) }),
    listening_now: count(
      object({
        realized_contact_id: token,
        spacecraft: spacecraftRef,
        // free-text: the station's short code, an identifier (U25), shown as written.
        station_code: nullable(string),
        starts_at: timestamp,
      }),
    ),
    transports: count(named),
  }),
});
export type InUse = Decoded<typeof details>;

/** One line of uses: its label, its named items (some linked), and how many more. */
export type UseLine = Readonly<{
  label: string;
  items: readonly Readonly<{ text: string; to?: RouteLocationRaw }>[];
  more: number;
}>;
/** A failure outcome that can also list what still uses the thing (U82). */
export type RefusalOutcome = FailureOutcome &
  Readonly<{ uses?: readonly UseLine[]; closing?: string; entityId?: string }>;

/** The change-set row to mark after an apply-time in-use refusal (ux U82): its entity, and why. */
export type InUseMark = Readonly<{ entityId: string; sentence: string }>;
export const inUseMark = (o: RefusalOutcome | null): InUseMark | null =>
  o?.entityId ? { entityId: o.entityId, sentence: o.sentence.replace(/:$/, ".") } : null;

const routeText = (r: InUse["uses"]["routes"]["items"][number]) => {
  const station = r.station?.code || r.station?.name;
  const craft = r.spacecraft.name ?? "Unknown spacecraft";
  return r.name
    ? `${craft} · ${r.name} — ${r.direction}`
    : `${craft} · ${station ? `${station} ` : ""}${r.direction}`;
};
const time = (iso: string) => formatShort(new Date(iso)).slice(-6);

export function useLines(uses: InUse["uses"]): readonly UseLine[] {
  const lines: UseLine[] = [];
  const add = (
    label: string,
    total: number,
    items: UseLine["items"],
    more = Math.max(0, total - items.length),
  ) => {
    if (total > 0) lines.push({ label, items, more });
  };
  add(
    "Routes",
    uses.routes.count,
    uses.routes.items.map((r) => ({
      text: routeText(r),
      to: { name: "setup.spacecraft.one", params: { spacecraftId: r.spacecraft.id } },
    })),
  );
  const profiles = [...new Set(uses.profile_routes.items.map((p) => p.profile.name))];
  add(
    "Profile routes",
    uses.profile_routes.count,
    profiles.map((text) => ({ text })),
  );
  const next = uses.booked_passes.next_at;
  add(
    "Booked passes",
    uses.booked_passes.count,
    [
      {
        text: `${uses.booked_passes.count}${next ? `, the next at ${formatShort(new Date(next))}` : ""}`,
        to: { name: "ops.contacts.plan" },
      },
    ],
    0,
  );
  add(
    "Listening now",
    uses.listening_now.count,
    uses.listening_now.items.map((l) => ({
      text: `the ${[l.spacecraft.name, l.station_code, time(l.starts_at)].filter(Boolean).join(" ")} pass`,
      to: { name: "ops.contact", params: { contactId: l.realized_contact_id } },
    })),
  );
  add(
    "Transports",
    uses.transports.count,
    uses.transports.items.map((t) => ({ text: t.name })),
  );
  return lines;
}

/** What the refusal calls the thing: its name, else 'This transport' / 'This station'. */
const subject = (entity: InUse["entity"]) =>
  entity?.name ?? (entity?.kind === "ground_station" ? "This station" : "This transport");

export function inUseOutcome(
  error: ApiError,
  verb: "staged" | "applied" | "changed",
): RefusalOutcome | null {
  if (!isError(error, "in_use")) return null;
  const d = detailsOf(error, details);
  if (!d) return null;
  const lines = useLines(d.uses);
  const atStage = verb === "staged";
  const sentence = atStage
    ? `${subject(d.entity)} is still in use, so it can't be archived:`
    : `${subject(d.entity)} is in use now, so this change set can't be applied:`;
  const entityId = d.entity?.id;
  if (lines.length === 0)
    return {
      changed: false,
      sentence: sentence.replace(/:$/, "."),
      closing: "Something still uses it.",
      ...(entityId ? { entityId } : {}),
    };
  return {
    changed: false,
    sentence,
    uses: lines,
    ...(entityId ? { entityId } : {}),
    closing: atStage
      ? "Move or remove these first."
      : "Move these first, or take the archive out of the change set.",
  };
}

/** failureOutcome, with U82's in-use refusal worded first (kept out of actions.ts, at its line cap). */
export const refusalOutcome = (
  error: ApiError,
  verb: "staged" | "applied" | "changed",
): RefusalOutcome => inUseOutcome(error, verb) ?? failureOutcome(error, verb);
