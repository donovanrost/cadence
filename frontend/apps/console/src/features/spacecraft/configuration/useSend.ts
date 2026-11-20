import { ref, shallowRef, type Ref } from "vue";
import { submitWorkspace, type ConfigurationSnapshot, type WorkspaceKey } from "./api.ts";
import {
  needsApproval,
  sendOutcome,
  sendRefusal,
  type SendOutcome,
  type SendRefusal,
} from "./send-words.ts";

/**
 * #595c (U94): send the saved draft. A mission that needs a second person's approval gets
 * `intent: review` (a request on L10); one that doesn't gets `activate`. The snapshot's token and
 * policy token go back as read; the result or refusal is the person's own act (said once).
 */
export function useSend(
  key: Readonly<Ref<WorkspaceKey | null>>,
  snapshot: () => ConfigurationSnapshot | null,
  refetch: () => void,
) {
  const sending = ref(false);
  const outcome = shallowRef<SendOutcome | null>(null);
  const failure = shallowRef<SendRefusal | null>(null);

  async function send() {
    const k = key.value;
    const s = snapshot();
    if (sending.value || !k || !s) return;
    sending.value = true;
    outcome.value = null;
    failure.value = null;
    try {
      const intent = needsApproval(s) ? "review" : "activate";
      const r = await submitWorkspace(k, s.token, s.approval.policy_token, intent);
      if (r.ok) {
        outcome.value = sendOutcome(r.value, s);
        refetch();
      } else failure.value = sendRefusal(r.error, s);
    } finally {
      sending.value = false;
    }
  }
  /** A new edit or save starts over: the last send's lines no longer describe the draft. */
  function clear() {
    outcome.value = null;
    failure.value = null;
  }
  return { sending, outcome, failure, send, clear };
}
