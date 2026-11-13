import { isError, request, type ApiError, type ApiResult } from "@/api/index.ts";
import { attentionReader, type Attention } from "@/features/now/index.ts";

/**
 * Contact drawer attention block (ux U32; contacts.md d2632794): the resolution record, what to do
 * per conflict, and Acknowledge / Resolve. Cadence can't act at the provider here, so no copy
 * says it did.
 */

export type AttentionOutcome =
  | { status: "done"; value: Attention }
  | { status: "rejected"; error: ApiError }
  | { status: "unclear"; error: ApiError };

function outcome(result: ApiResult<Attention>): AttentionOutcome {
  if (result.ok) return { status: "done", value: result.value };
  const e = result.error;
  const rejected =
    e.kind === "forbidden" ||
    e.kind === "not_found" ||
    e.kind === "conflict" ||
    e.kind === "invalid" ||
    e.kind === "unauthenticated";
  return rejected ? { status: "rejected", error: e } : { status: "unclear", error: e };
}

const itemPath = (missionId: string, a: Attention) =>
  `/missions/${encodeURIComponent(missionId)}/attention/${encodeURIComponent(a.source)}/${encodeURIComponent(a.id)}`;

export async function acknowledgeAttention(
  missionId: string,
  a: Attention,
): Promise<AttentionOutcome> {
  return outcome(
    await request(`${itemPath(missionId, a)}/acknowledge`, attentionReader, { method: "POST" }),
  );
}

export async function resolveAttention(
  missionId: string,
  a: Attention,
  actionText: string,
): Promise<AttentionOutcome> {
  return outcome(
    await request(`${itemPath(missionId, a)}/resolve`, attentionReader, {
      method: "POST",
      body: { action_text: actionText },
    }),
  );
}

export const ACTION_TEXT_MAX = 200;

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;

/** "Marked booked by Mira K. 10:52Z · ref NL-48213 · ‘Called the Northlight ops desk.’" */
export function resolutionRecord(a: Attention): string | null {
  const r = a.resolution;
  if (!r) return null;
  const what = r.action.includes("not_booked")
    ? "Marked not booked"
    : r.action.includes("book") || r.action.includes("attest")
      ? "Marked booked"
      : r.action.replaceAll("_", " ").replace(/^./, (c) => c.toUpperCase());
  return [
    `${what} by ${r.actor.name ?? "an operator"} ${hhmm(r.at)}`,
    r.provider_reference ? `ref ${r.provider_reference}` : null,
    r.note ? `‘${r.note}’` : null,
  ]
    .filter((p): p is string => p !== null)
    .join(" · ");
}

/** One "what to do" line per conflict (U32). */
export function whatToDo(a: Attention): Readonly<{ text: string; plan: boolean }> {
  const provider = a.provider?.name ?? "the provider";
  switch (a.conflict) {
    case "cancel_failed":
      return {
        text: `Check with ${provider} that the pass is canceled. If it can't be, keep it and record what you did.`,
        plan: false,
      };
    case "late_confirmation":
      return {
        text: `${provider} booked it after it was marked not booked. Cancel it with ${provider} or use the pass, then record what you did.`,
        plan: false,
      };
    case "contradicts_attestation":
      return {
        text: "Don't count on this contact. Re-plan the spacecraft if it needs this contact.",
        plan: true,
      };
    case null:
    default:
      return { text: `Check the booking with ${provider}, then record what you did.`, plan: false };
  }
}

/** U20/U32 words for a write that didn't land. `refresh` asks the caller to reload the pass. */
export function attentionErrorWords(error: ApiError): Readonly<{ text: string; refresh: boolean }> {
  if (isError(error, "attention_item_not_found") || isError(error, "attention_item_not_open"))
    return { text: "This was already resolved.", refresh: true };
  if (error.kind === "forbidden")
    return {
      text: "Nothing changed: you can't act on attention items for this mission.",
      refresh: false,
    };
  const message = "message" in error ? error.message : "the server didn't say why";
  return { text: `Nothing changed: ${message.replace(/[.!?]+$/, "")}.`, refresh: false };
}
