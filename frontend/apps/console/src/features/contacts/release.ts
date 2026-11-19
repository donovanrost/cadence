import type { MissionId } from "@/api/index.ts";
import { decoders as d, describeApiError, detailsOf, isError, request } from "@/api/index.ts";
import { passReader, reservationStates } from "./api.ts";

/**
 * D2 Release (contacts.md §Contact drawer D2 actions): cancels the booking at the provider. U20
 * outcomes: refused / not sent = nothing changed; unknown = unclear until the provider answers.
 */
export type ReleaseOutcome = Readonly<{ tone: "info" | "caution" | "crit"; text: string }>;

const failed = d.object({
  // An outcome this console doesn't know reads as unclear (the default branch below).
  outcome: d.known(["refused", "not_sent", "unknown"] as const),
  // free-text: the provider's own sentence, shown in parentheses
  reason: d.optional(d.nullable(d.string)),
  state: d.optional(d.nullable(d.known(reservationStates))),
});
const noStop = (s: string) => s.trim().replace(/[.!?]+$/, "");

export async function releasePass(
  missionId: MissionId,
  passId: string,
  expectedRevision: number,
  provider: string,
  bookedBy: string | null = null,
): Promise<ReleaseOutcome> {
  const r = await request(
    `/missions/${encodeURIComponent(missionId)}/passes/${encodeURIComponent(passId)}/release`,
    passReader,
    { method: "POST", body: { expected_provider_revision: expectedRevision } },
  );
  if (r.ok)
    return {
      tone: "info",
      text:
        // ux (U20): say what the server knows, never just "Released."
        r.value.state === "canceled"
          ? `${provider} accepted the cancel. The pass leaves the plan.`
          : `Cancel sent to ${provider}. It hasn't confirmed yet.`,
    };
  return releaseErrorWords(r.error, provider, bookedBy);
}

/**
 * Who may release (DECISIONS #78): an off-plan booking's own operator or an org admin; a planned
 * one, org admins. The same words as the panel's caption, so a refusal names the booker too.
 */
export const whoMayRelease = (bookedBy: string | null) =>
  bookedBy
    ? `${bookedBy} or an org admin can release this booking.`
    : "Org admins can release a booking.";

export function releaseErrorWords(
  e: Parameters<typeof describeApiError>[0],
  provider: string,
  bookedBy: string | null = null,
): ReleaseOutcome {
  const f = isError(e, "provider_cancel_failed") ? detailsOf(e, failed) : null;
  if (f) {
    {
      const why = f.reason ? ` (${noStop(f.reason)})` : "";
      if (f.outcome === "refused")
        return { tone: "crit", text: `Nothing changed: ${provider} refused the cancel${why}.` };
      if (f.outcome === "not_sent")
        return { tone: "crit", text: `Nothing changed: the cancel wasn't sent${why}.` };
      return {
        tone: "caution",
        text: `It's unclear whether ${provider} canceled it${why}. The pass reads Unknown until ${provider} answers.`,
      };
    }
  }
  if (isError(e, "pass_changed"))
    return { tone: "caution", text: "The pass changed while you looked; it's been reloaded." };
  if (isError(e, "pass_not_releasable"))
    return { tone: "crit", text: "Nothing changed: this pass can't be released any more." };
  if (e.kind === "forbidden") return { tone: "crit", text: whoMayRelease(bookedBy) };
  if (e.kind === "unavailable" || e.kind === "malformed")
    return {
      tone: "caution",
      text: "No answer from the server, so it may or may not have been released. Reload the pass to check.",
    };
  return { tone: "crit", text: `Nothing changed: ${noStop(describeApiError(e))}.` };
}
