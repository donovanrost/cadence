import { onBeforeUnmount, ref, watch } from "vue";
import { FormActionFailure } from "../../shared/form-workflow.contracts";
import { identifier, integer, record, text } from "../../shared/read-validation";
import type { ProviderPort } from "./provider-port";

export function providerReceipt(value: unknown) {
  const envelope = record(value),
    result = record(envelope.result ?? envelope);
  return {
    id: identifier(result.provider_id),
    version: integer(result.version, 1),
    name: text(result.display_name),
  };
}
export function useProviderOperation(port: () => ProviderPort, identity: () => unknown) {
  const pending = ref(false),
    locked = ref(false),
    message = ref<string | null>(null);
  let generation = 0,
    disposed = false;
  function reset() {
    ++generation;
    pending.value = false;
    locked.value = false;
    message.value = null;
  }
  watch([port, identity], reset, { flush: "sync" });
  onBeforeUnmount(() => {
    disposed = true;
    ++generation;
  });
  async function run(
    operation: (port: ProviderPort, current: () => boolean) => Promise<"ready" | "done">,
    readOnly = false,
  ) {
    if (disposed || pending.value || (locked.value && !readOnly)) return;
    const revision = ++generation;
    const current = () => !disposed && generation === revision;
    pending.value = true;
    message.value = null;
    try {
      const disposition = await operation(port(), current);
      if (current()) locked.value = disposition === "done";
    } catch (reason) {
      if (!current()) return;
      const rejected = reason instanceof FormActionFailure && reason.outcome === "rejected";
      if (!readOnly) locked.value = !rejected;
      message.value = readOnly
        ? "The provider could not be refreshed. Try refreshing again."
        : rejected
          ? "The operation was rejected. Your page and draft are still available."
          : "The outcome could not be confirmed. Check the provider records before another attempt.";
    } finally {
      if (current()) pending.value = false;
    }
  }
  return { pending, locked, message, run, reset };
}
