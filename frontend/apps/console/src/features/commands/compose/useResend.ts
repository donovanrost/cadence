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

/**
 * Prefills Compose once from a sent-back group: its explicit targets, stack (values as sent),
 * title, log, approver and hold time. The reviewer's note shows above the form.
 */
export function useResend(missionId: Ref<string>, fromId: string | null, into: ResendTargets) {
  const sentBackFrom = ref<string | null>(null);
  const notice = shallowRef<{ tone: "info" | "caution"; text: string } | null>(null);
  if (fromId === null) return { sentBackFrom, notice };
  notice.value = { tone: "info", text: "Loading the request you're resending…" };
  loadResend(missionId.value, fromId)
    .then((r) => {
      if (!r.ok) {
        notice.value = { tone: "caution", text: `Couldn't load that request: ${r.message}` };
        return;
      }
      const { group, stack, missing } = r.value;
      sentBackFrom.value = group.id;
      into.query.value = {
        plane: null,
        profile: null,
        states: [],
        explicit: group.targets.map((t) => t.spacecraft_id),
      };
      into.stack.value = stack;
      into.title.value = group.title;
      into.log.value = group.log_entry ?? "";
      into.approver.value = group.requested_approver_user_id ?? "";
      const nb = group.release?.not_before;
      if (nb) into.release.value = { mode: "not_before", notBefore: Date.parse(nb) };
      const note = group.decision?.note;
      const gone = missing.length
        ? ` ${missing.join(", ")} ${missing.length === 1 ? "is" : "are"} no longer in the active catalog and ${missing.length === 1 ? "was" : "were"} left out.`
        : "";
      notice.value = {
        tone: missing.length ? "caution" : "info",
        text: `Resending “${group.title}”${note ? `, sent back with: “${note}”` : ""}.${gone}`,
      };
    })
    .catch((e: unknown) => console.error("Resend prefill failed", e));
  return { sentBackFrom, notice };
}
