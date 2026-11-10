import {
  decoders as d,
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

const actor = d.object({ kind: d.string, id: d.nullable(d.string), name: d.nullable(d.string) });

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
  missionId: string,
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

const codeOf = (e: ApiError) => ("code" in e ? e.code : null);

/** U32 / U20 error copy; never claims something saved when the reply doesn't say so. */
export function failureText(e: ApiError, provider: string): ResolveFailure {
  switch (codeOf(e)) {
    case "booking_not_unconfirmed":
      return {
        text: `This booking isn't unconfirmed any more. ${provider} may have answered.`,
        fields: {},
        refresh: true,
      };
    case "booking_already_resolved": {
      const name = resolverName("details" in e ? e.details : null);
      return {
        text: `${name ?? "Someone"} already resolved this.`,
        fields: {},
        refresh: true,
      };
    }
    case "booking_not_found":
      return { text: "This booking isn't on the plan any more.", fields: {}, refresh: true };
    case "invalid_params": {
      const fields = fieldMessages("details" in e ? e.details : null);
      const inline = Object.keys(fields).every((k) => k === "note" || k === "provider_reference");
      return {
        text:
          inline && Object.keys(fields).length > 0 ? null : "Nothing was marked. Check the fields.",
        fields,
        refresh: false,
      };
    }
    case "forbidden":
      return { text: "Org admins resolve unconfirmed bookings.", fields: {}, refresh: false };
    case null:
    default:
      break;
  }
  if (e.kind === "forbidden")
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

function resolverName(details: unknown): string | null {
  if (details === null || typeof details !== "object") return null;
  const a = (details as Record<string, unknown>)["actor"];
  if (a === null || typeof a !== "object") return null;
  const name = (a as Record<string, unknown>)["name"];
  return typeof name === "string" && name ? name : null;
}

function fieldMessages(details: unknown): Record<string, string> {
  if (details === null || typeof details !== "object") return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(details as Record<string, unknown>)) {
    const text = Array.isArray(v) ? v.filter((x) => typeof x === "string").join(" ") : v;
    if (typeof text === "string" && text) out[k] = text;
  }
  return out;
}
