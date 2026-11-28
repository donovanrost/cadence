import type { MissionId } from "@/api/index.ts";
import { PRIORITY_NORMAL } from "../priority.ts";
import { ref, shallowRef, type Ref } from "vue";
import type { Release } from "./draft.ts";
import { loadResend } from "./resend.ts";
import type { StackItem } from "./stack.ts";
import type { TargetQuery } from "./targets.ts";

export type ResendTargets = Readonly<{
  query: Ref<TargetQuery>;
  stack: Ref<StackItem[]>;
  title: Ref<string>;
  log: Ref<string>;
  approver: Ref<string>;
  release: Ref<Release>;
}>;

/** `?from=group:<id>` → the group id, else null. */
export function resendFrom(value: unknown): string | null {
  return typeof value === "string" && value.startsWith("group:") && value.length > 6
    ? value.slice(6)
    : null;
}

type Callout = Readonly<{ tone: "info" | "caution"; role: "status" | "alert" }>;
const INFO: Callout = { tone: "info", role: "status" };
const CAUTION: Callout = { tone: "caution", role: "alert" };

/**
 * Prefills Compose once from a sent-back group: its explicit targets, stack (values as sent),
 * title, log, approver and hold time. The reviewer's note shows above the form.
 */
export function useResend(
  missionId: Ref<MissionId>,
  fromId: string | null,
  into: ResendTargets,
  /** Uplink N `Re-send` (DECISIONS #69): only these targets of the group. */
  only: readonly string[] = [],
) {
  const sentBackFrom = ref<string | null>(null);
  /**
   * a11y B6 (#243): the callout's tone and role together; an outcome object's caution (a failed
   * load, commands left out) is an alert, its info a status.
   */
  const notice = shallowRef<{ callout: Callout; text: string } | null>(null);
  if (fromId === null) return { sentBackFrom, notice };
  notice.value = { callout: INFO, text: "Loading the request you're resending…" };
  loadResend(missionId.value, fromId)
    .then((r) => {
      if (!r.ok) {
        notice.value = { callout: CAUTION, text: `Couldn't load that request: ${r.message}` };
        return;
      }
      const { group, targetIds, stack, missing } = r.value;
      sentBackFrom.value = group.id;
      into.query.value = {
        plane: null,
        profile: null,
        states: [],
        explicit: targetIds.filter((id) => only.length === 0 || only.includes(id)),
      };
      into.stack.value = stack;
      into.title.value = group.title;
      into.log.value = group.log_entry ?? "";
      into.approver.value = group.requested_approver_user_id ?? "";
      const nb = group.release?.not_before;
      // U68: a resend keeps its priority (a low one becomes 'Low (as before)'); a past expiry isn't
      // carried, since it would refuse at once.
      into.release.value = {
        ...(nb
          ? { mode: "not_before" as const, notBefore: Date.parse(nb) }
          : { mode: "next_contact" as const, notBefore: null }),
        expiresAt: null,
        priority: group.release?.priority ?? PRIORITY_NORMAL,
      };
      const note = group.decision?.note;
      const gone = missing.length
        ? ` ${missing.join(", ")} ${missing.length === 1 ? "is" : "are"} no longer in the active catalog and ${missing.length === 1 ? "was" : "were"} left out.`
        : "";
      notice.value = {
        callout: missing.length ? CAUTION : INFO,
        // The quoted note ends the sentence itself; no period after the closing quote.
        text: `Resending “${group.title}”${only.length ? ` to ${only.length} of ${group.target_count} targets` : ""}${note ? `, sent back with: “${note}”` : "."}${gone}`,
      };
    })
    .catch((e: unknown) => console.error("Resend prefill failed", e));
  return { sentBackFrom, notice };
}

/** `?only=a,b` → the target ids to keep. */
export const onlyFrom = (value: unknown): string[] =>
  typeof value === "string" && value ? value.split(",").filter(Boolean) : [];
