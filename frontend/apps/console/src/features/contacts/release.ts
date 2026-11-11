import { decode, decoders as d, describeApiError, request } from "@/api/index.ts";
import { passReader } from "./api.ts";

/**
 * D2 Release (contacts.md §Contact drawer D2 actions): cancels the booking at the provider. U20
 * outcomes: refused / not sent = nothing changed; unknown = unclear until the provider answers.
 */
export type ReleaseOutcome = Readonly<{ tone: "info" | "caution" | "crit"; text: string }>;

const failed = d.object({
  outcome: d.token,
  reason: d.optional(d.nullable(d.string)),
  state: d.optional(d.nullable(d.token)),
});
const noStop = (s: string) => s.trim().replace(/[.!?]+$/, "");

export async function releasePass(
  missionId: string,
  passId: string,
  expectedRevision: number,
  provider: string,
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
  return releaseErrorWords(r.error, provider);
}

export function releaseErrorWords(
  e: Parameters<typeof describeApiError>[0],
  provider: string,
): ReleaseOutcome {
  const code = "code" in e ? e.code : null;
  if (code === "provider_cancel_failed" && "details" in e) {
    const f = decode(failed, e.details);
    if (f.ok) {
      const why = f.value.reason ? ` (${noStop(f.value.reason)})` : "";
      if (f.value.outcome === "refused")
        return { tone: "crit", text: `Nothing changed: ${provider} refused the cancel${why}.` };
      if (f.value.outcome === "not_sent")
        return { tone: "crit", text: `Nothing changed: the cancel wasn't sent${why}.` };
      return {
        tone: "caution",
        text: `It's unclear whether ${provider} canceled it${why}. The pass reads Unknown until ${provider} answers.`,
      };
    }
  }
  if (code === "pass_changed")
    return { tone: "caution", text: "The pass changed while you looked; it's been reloaded." };
  if (code === "pass_not_releasable")
    return { tone: "crit", text: "Nothing changed: this pass can't be released any more." };
  if (e.kind === "forbidden") return { tone: "crit", text: "Org admins can release a booking." };
  if (e.kind === "unavailable" || e.kind === "malformed")
    return {
      tone: "caution",
      text: "No answer from the server, so it may or may not have been released. Reload the pass to check.",
    };
  return { tone: "crit", text: `Nothing changed: ${noStop(describeApiError(e))}.` };
}
