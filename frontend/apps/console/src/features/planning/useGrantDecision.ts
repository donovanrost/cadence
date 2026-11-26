import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { fieldErrors } from "@/api";
import { approveFailure, rejectFailure } from "./grant-refusals.ts";
import { subject, type Worded } from "./grant-words.ts";
import { approveGrant, operationIds, rejectGrant, untilText, type Grant } from "./grants.ts";

/**
 * U105 decisions on a proposed grant: approve (at the hash read) and reject (with a reason), each
 * with an operation_id that a retry of the same request reuses (#257), so a replay answers the
 * original result, shown as this one's.
 */
export function useGrantDecision(
  missionId: () => MissionId,
  grant: () => Grant,
  viewerId: () => string | null,
  done: (said: string) => void,
) {
  const busy = ref<"approve" | "reject" | null>(null);
  const failure = ref<Worded | null>(null);
  /** After a separation refusal, Approve stays off with its up-front line (U105). */
  const disabled = ref<Worded | null>(null);
  const rejectError = ref<string | null>(null);
  const rejectFailed = ref<Worded | null>(null);
  const ops = operationIds();

  async function approve() {
    const g = grant();
    if (busy.value) return;
    busy.value = "approve";
    failure.value = null;
    try {
      const r = await approveGrant(missionId(), g, ops(`approve:${g.id}:${g.sha256}`));
      if (r.ok) {
        const a = r.value.grant;
        return done(
          a.state === "active" && a.valid_until
            ? `Approved. ${subject(a)} can act under it until ${untilText(a)}.`
            : "Cadence didn't confirm the approval. Reload to see it.",
        );
      }
      const f = approveFailure(r.error, g, viewerId());
      failure.value = f;
      if (f.disable) disabled.value = f.disable;
    } finally {
      busy.value = null;
    }
  }

  /** True when it was rejected (the sheet closes); a refusal stays in the sheet. */
  async function reject(reason: string): Promise<boolean> {
    const g = grant();
    if (busy.value) return false;
    busy.value = "reject";
    rejectError.value = rejectFailed.value = null;
    try {
      const r = await rejectGrant(missionId(), g, reason, ops(`reject:${g.id}:${reason}`));
      if (r.ok) {
        done(
          r.value.grant.state === "rejected"
            ? `Rejected. ${subject(r.value.grant)} won't act under this grant.`
            : "Cadence didn't confirm the rejection. Reload to see it.",
        );
        return true;
      }
      rejectError.value = fieldErrors(r.error)["reason"] ?? null;
      rejectFailed.value = rejectError.value ? null : rejectFailure(r.error);
      return false;
    } finally {
      busy.value = null;
    }
  }

  return { busy, failure, disabled, rejectError, rejectFailed, approve, reject };
}
