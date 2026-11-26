import { ref, type Ref } from "vue";
import { describeApiError } from "@/api/index.ts";
import {
  approvalOps,
  approveRevision,
  rejectRevision,
  runComparison,
  type ModelKey,
} from "./api.ts";
import { decisionFailure, type DecisionFailure } from "./words.ts";

/**
 * U65 writes: run the comparison, approve against it, reject with a reason. Each success
 * re-reads the revision (`refetch`), which carries the newest report and the decision.
 */
export function useApproval(
  key: Readonly<Ref<ModelKey>>,
  rev: () => number | null,
  refetch: () => void,
  /** #260: the signed-in person, so an already-approved refusal can say "You already approved…". */
  viewerId: string | null = null,
  /** U109: a composed base's name in a sentence ("composition 3"); null for one catalog. */
  composedName: () => string | null = () => null,
) {
  const ops = approvalOps();
  const busy = ref<"run" | "approve" | "reject" | null>(null);
  /** The last refusal, and which write it came from (a reject's shows in its sheet). */
  const failure = ref<(DecisionFailure & { from: "run" | "approve" | "reject" }) | null>(null);

  async function run() {
    if (busy.value) return;
    busy.value = "run";
    failure.value = null;
    try {
      const r = await runComparison(key.value);
      if (r.ok) refetch();
      else
        failure.value = {
          text: `The comparison didn't run: ${describeApiError(r.error)}`,
          runAgain: false,
          from: "run",
        };
    } finally {
      busy.value = null;
    }
  }

  async function approve(reportId: string) {
    if (busy.value) return;
    busy.value = "approve";
    failure.value = null;
    try {
      const r = await approveRevision(key.value, reportId, ops(key.value.revisionId, reportId));
      if (r.ok) refetch();
      else
        failure.value = {
          ...decisionFailure(r.error, rev(), "approve", viewerId, composedName()),
          from: "approve",
        };
    } finally {
      busy.value = null;
    }
  }

  /** True when it was rejected (the sheet closes); a refusal is in `failure`. */
  async function reject(reason: string): Promise<boolean> {
    if (busy.value) return false;
    busy.value = "reject";
    failure.value = null;
    try {
      const r = await rejectRevision(key.value, reason);
      if (r.ok) refetch();
      else failure.value = { ...decisionFailure(r.error, rev(), "reject"), from: "reject" };
      return r.ok;
    } finally {
      busy.value = null;
    }
  }

  return { busy, failure, run, approve, reject };
}
