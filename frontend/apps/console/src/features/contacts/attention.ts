import {
  decoders as d,
  describeApiError,
  detailsOf,
  fieldErrors,
  isError,
  request,
  type ApiError,
  type ApiResult,
} from "@/api/index.ts";
import { attentionReader, serverKey, type Attention } from "@/features/now/index.ts";

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
  `/missions/${encodeURIComponent(missionId)}/attention/${encodeURIComponent(serverKey(a.source))}/${encodeURIComponent(a.id)}`;

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
    // pass_resolution only: other sources have their own blocks (settlement, provider change, …).
    case "unsettled":
    case "generation_not_applied":
    case "apply_failed":
    case "apply_stalled":
    case "approval_required":
    case "acknowledgment_required":
    case "configuration_failure":
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

/** §11 L14 / U44: the three decisions on a provider change. */
export type ChangeDecision = "approve" | "reject" | "acknowledge";

export type ChangeOutcome =
  | { status: "done"; item: Attention | null }
  /** Refused: say why; `item` is the current change when the provider changed it again. */
  | {
      status: "refused";
      text: string;
      item?: Attention | null;
      reasonError?: string;
      /** 409 deadline passed: both decisions go (api 84f58b73d). */
      deadlinePassed?: boolean;
    }
  | { status: "unclear"; text: string };

const replyReader = d.object({ item: d.nullable(attentionReader) });

/** POST …/attention/provider_change/:id/<decision> {reason, proposal_hash} (api 30b3f60b9). */
export async function decideProviderChange(
  missionId: string,
  a: Attention,
  decision: ChangeDecision,
  reason: string,
): Promise<ChangeOutcome> {
  const r = await request(`${itemPath(missionId, a)}/${decision}`, replyReader, {
    method: "POST",
    body: { reason, proposal_hash: a.provider_change?.proposal_hash ?? "" },
  });
  if (r.ok) return { status: "done", item: r.value.item };
  const e = r.error;
  const provider = a.provider?.name ?? "The provider";
  const deadline = a.deadline_at ?? a.provider_change?.deadline_at ?? null;
  if (isError(e, "provider_change_stale")) {
    const item = detailsOf(e, replyReader)?.item ?? null;
    return item
      ? {
          status: "refused",
          text: `${provider} changed it again. Here's the current change.`,
          item,
        }
      : { status: "refused", text: "This change was already decided or replaced.", item: null };
  }
  if (isError(e, "attention_item_not_found"))
    return { status: "refused", text: "This change was already decided or replaced.", item: null };
  // api 84f58b73d: past the deadline neither approve nor reject lands; the provider's next
  // revision replaces the change (ux U44 re-ruling pending).
  if (isError(e, "provider_change_deadline_passed"))
    return {
      status: "refused",
      text: `The deadline passed${deadline ? ` at ${hhmm(deadline)}` : ""}. This change stays until ${a.provider?.name ?? "the provider"}'s next update replaces it.`,
      deadlinePassed: true,
    };
  if (e.kind === "forbidden")
    return { status: "refused", text: "Org admins decide provider changes." };
  if (isError(e, "invalid_params")) {
    const f = fieldErrors(e);
    return f.reason
      ? { status: "refused", text: "", reasonError: f.reason }
      : { status: "refused", text: f.proposal_hash ?? describeApiError(e) };
  }
  return {
    status: "unclear",
    text: `It's unclear whether it was recorded (${describeApiError(e)}).`,
  };
}
