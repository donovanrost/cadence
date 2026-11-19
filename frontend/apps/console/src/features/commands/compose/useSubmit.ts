import type { MissionId } from "@/api/index.ts";
import { shallowRef, type Ref } from "vue";
import { describeApiError, decoders as d, decode, detailsOf, isError } from "@/api/index.ts";
import { fetchGroups, submitGroup, type Draft, type HoldAck } from "../groups/api.ts";
import { checkLabel } from "../groups/checks.ts";

/**
 * Submit (M16) with ux U20 outcomes: a rejection says nothing changed (with the server's reason);
 * an unclear outcome offers a check by operation_id, never a blind retry. One operation_id per
 * attempt chain, so a resend after an unclear outcome can't create a second group.
 */
export type SubmitState =
  | { status: "idle" }
  | { status: "sending" }
  | { status: "checking" }
  | { status: "done"; groupId: string }
  /** `stale`: the preflight or its HOLDs changed under the operator (the outcome offers a re-check). */
  | { status: "rejected"; stale: boolean; message: string }
  | { status: "unclear"; message: string };

const duplicate = d.object({ command_group_id: d.token });
const unacked = d.object({ holds: d.array(d.object({ key: d.token }), 50) });

/** 422 holds_unacknowledged (#60): which HOLDs the server still counts as open. */
function unackedWords(details: unknown): string {
  const r = decode(unacked, details);
  const names = r.ok ? [...new Set(r.value.holds.map((h) => checkLabel(h.key)))] : [];
  return names.length
    ? `the ${names.join(" and ")} HOLD isn't acknowledged against the latest checks.`
    : "a HOLD isn't acknowledged against the latest checks.";
}

export function useSubmit(missionId: Ref<MissionId>, onStale: () => void) {
  const state = shallowRef<SubmitState>({ status: "idle" });
  let operationId: string | null = null;

  async function submit(
    draft: Draft,
    digest: string,
    acks: readonly HoldAck[] = [],
    draftRevision: number | null = null,
  ) {
    operationId ??= crypto.randomUUID();
    state.value = { status: "sending" };
    const outcome = await submitGroup(
      missionId.value,
      draft,
      digest,
      operationId,
      acks,
      draftRevision,
    );
    if (outcome.status === "done") {
      state.value = { status: "done", groupId: outcome.value.id };
      return;
    }
    if (outcome.status === "unclear") {
      state.value = { status: "unclear", message: describeApiError(outcome.error) };
      return;
    }
    const e = outcome.error;
    const prior = isError(e, "duplicate_operation") ? detailsOf(e, duplicate) : null;
    if (prior) {
      state.value = { status: "done", groupId: prior.command_group_id };
      return;
    }
    // Definitely not created: the next attempt is a new operation.
    operationId = null;
    const stale = isError(e, "preflight_stale") || isError(e, "holds_unacknowledged");
    if (stale) onStale();
    const message =
      isError(e, "holds_unacknowledged") && "details" in e
        ? unackedWords(e.details)
        : describeApiError(e);
    state.value = { status: "rejected", stale, message };
  }

  /** Resolve an unclear submit: did the server create the group? */
  async function check() {
    if (operationId === null) return;
    state.value = { status: "checking" };
    const result = await fetchGroups(missionId.value, { operationId });
    if (!result.ok) {
      state.value = { status: "unclear", message: describeApiError(result.error) };
      return;
    }
    const found = result.value[0];
    state.value = found
      ? { status: "done", groupId: found.id }
      : {
          status: "rejected",
          stale: false,
          message: "The server has no record of it.",
        };
  }

  /** Editing the draft after a rejection starts over. */
  function reset() {
    if (state.value.status === "rejected") state.value = { status: "idle" };
  }

  return { state, submit, check, reset };
}
