import type { MissionId } from "@/api/index.ts";
import {
  actor,
  decoders as d,
  detailsOf,
  orNull,
  fieldErrors,
  isError,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  outcomeUnknown,
} from "@/api";

/**
 * DECISIONS #53 / ux U32: resolve a placed booking the provider hasn't answered past the #52 window.
 * Contract: docs/apogee/api/scheduling.md, `POST /contact-plans/:plan_id/unconfirmed/:snapshot_id/resolve`.
 */
export type ResolveAction = "booked" | "not_booked";

export const resolveReader = d.object({
  outcome: d.oneOf(["provider_answered", "attested", "not_booked"]),
  provider_answer: d.nullable(d.oneOf(["booked", "not_booked"])),
  resolution: d.nullable(
    d.object({
      actor: d.nullable(actor),
      at: d.nullable(d.string),
      note: d.nullable(d.string),
      provider_reference: d.nullable(d.string),
    }),
  ),
});
export type Resolved = Decoded<typeof resolveReader>;

export function resolveUnconfirmed(
  missionId: MissionId,
  planId: string,
  snapshotId: string,
  body: Readonly<{ action: ResolveAction; note: string; provider_reference?: string }>,
): Promise<ApiResult<Resolved>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/contact-plans/${encodeURIComponent(planId)}/unconfirmed/${encodeURIComponent(snapshotId)}/resolve`,
    resolveReader,
    { method: "POST", body },
  );
}

/** U32 outcome line (shown in the sheet's place, then the list refreshes). */
export function outcomeText(r: Resolved, provider: string): string {
  switch (r.outcome) {
    case "provider_answered":
      return `${provider} answered: ${r.provider_answer === "not_booked" ? "not booked" : "booked"}. Nothing was marked.`;
    case "attested": {
      const ref = r.resolution?.provider_reference;
      return `Marked booked by you${ref ? ` · ref ${ref}` : ""}.`;
    }
    case "not_booked":
      // Don't claim the cancel was accepted: a failed cancel arrives in the Now queue (U31).
      return `Marked not booked. The cancel went to ${provider}.`;
  }
}

export type ResolveFailure = Readonly<{
  /** Sheet-level line, or null when every problem is inline under a field. */
  text: string | null;
  /** Inline errors keyed `note` / `provider_reference`. */
  fields: Readonly<Record<string, string>>;
  /** The list is stale: refresh it (the booking moved on, or we can't tell). */
  refresh: boolean;
}>;

/** U32 / U20 error copy; never claims something saved when the reply doesn't say so. */
export function failureText(e: ApiError, provider: string): ResolveFailure {
  if (isError(e, "booking_not_unconfirmed"))
    return {
      text: `This booking isn't unconfirmed any more. ${provider} may have answered.`,
      fields: {},
      refresh: true,
    };
  if (isError(e, "booking_already_resolved"))
    return {
      text: `${resolverName(e) ?? "Someone"} already resolved this.`,
      fields: {},
      refresh: true,
    };
  if (isError(e, "booking_not_found"))
    return { text: "This booking isn't on the plan any more.", fields: {}, refresh: true };
  if (isError(e, "invalid_params")) {
    const fields = fieldErrors(e);
    const inline = Object.keys(fields).every((k) => k === "note" || k === "provider_reference");
    return {
      text:
        inline && Object.keys(fields).length > 0 ? null : "Nothing was marked. Check the fields.",
      fields,
      refresh: false,
    };
  }
  if (isError(e, "forbidden") || e.kind === "forbidden")
    return { text: "Org admins resolve unconfirmed bookings.", fields: {}, refresh: false };
  if (outcomeUnknown(e))
    return {
      text: "No clear answer from the server, so it may or may not have been recorded. The list has been reloaded; check it before trying again.",
      fields: {},
      refresh: true,
    };
  return {
    text: `Nothing was marked. ${"message" in e ? e.message : ""}`.trim(),
    fields: {},
    refresh: false,
  };
}

/** booking_already_resolved names who resolved it: details.actor, the shared actor (§12 A5). */
const alreadyResolved = d.object({ actor: orNull(actor) });
function resolverName(e: ApiError): string | null {
  return detailsOf(e, alreadyResolved)?.actor?.name || null;
}
