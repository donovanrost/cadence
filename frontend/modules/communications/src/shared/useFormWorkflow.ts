import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { FormFeedback, FormInput, FormPort } from "./form-workflow.contracts";
import { FormActionFailure } from "./form-workflow.contracts";
import { href, record } from "./read-validation";
import type { ReadContext } from "./read-contracts";

export function useFormWorkflow<T>(
  port: () => FormPort,
  context: () => ReadContext,
  admitValidation: (receipt: unknown, input: FormInput) => T,
  canSubmit: (result: T) => boolean = () => true,
) {
  const validating = ref(false),
    saving = ref(false),
    accepted = ref(false);
  const message = ref<string | null>(null);
  const outcome = shallowRef<T | null>(null);
  let revision = 0,
    disposed = false,
    saved = false;
  let running: number | null = null;
  let latest: { revision: number; input: FormInput; identity: string } | null = null;
  function reset() {
    ++revision;
    running = null;
    latest = null;
    accepted.value = false;
    validating.value = false;
    saving.value = false;
    outcome.value = null;
    message.value = null;
    saved = false;
  }
  watch([port, context], reset, { flush: "sync" });
  onBeforeUnmount(() => {
    disposed = true;
    ++revision;
    latest = null;
  });
  const feedback = computed<FormFeedback>(() => ({
    canSubmit: accepted.value && !validating.value && !saving.value && !saved,
    validating: validating.value,
    saving: saving.value,
    message: message.value,
    canRevalidate: !saved && !saving.value && !validating.value && message.value !== null,
  }));
  function validate(input: FormInput) {
    if (disposed || saving.value || saved) return;
    const identity = JSON.stringify(input);
    latest = { revision: ++revision, input: JSON.parse(identity), identity };
    accepted.value = false;
    outcome.value = null;
    message.value = null;
    validating.value = true;
    void drain();
  }
  async function drain() {
    if (running !== null || disposed || !latest) return;
    const request = latest;
    running = request.revision;
    try {
      const result = admitValidation(
        await port().execute("validate", request.input),
        request.input,
      );
      if (!disposed && revision === request.revision) {
        accepted.value = canSubmit(result);
        outcome.value = result;
      }
    } catch {
      if (!disposed && revision === request.revision) {
        accepted.value = false;
        message.value = "The draft could not be validated. Check the values and try again.";
      }
    } finally {
      if (running !== request.revision) return;
      running = null;
      if (!disposed && latest && revision !== request.revision) void drain();
      else if (!disposed) validating.value = false;
    }
  }
  async function save(input: FormInput) {
    if (disposed || saved || saving.value) return;
    // The submitted values must be the exact draft accepted by the latest reply.
    if (!feedback.value.canSubmit || !latest || latest.identity !== JSON.stringify(input)) {
      validate(input);
      return;
    }
    saving.value = true;
    message.value = null;
    const saveRevision = revision;
    const activePort = port();
    const activeContext = context();
    try {
      const receipt = await activePort.execute("save", latest.input);
      if (disposed || revision !== saveRevision) return;
      // A successful save must never be repeated merely because its navigation is unusable.
      saved = true;
      accepted.value = false;
      const envelope = record(receipt);
      const result = record(envelope.result ?? envelope);
      const navigation = record(result.navigation);
      const target = href(navigation.href, activeContext);
      activePort.navigate(target);
    } catch (reason) {
      if (!disposed && revision === saveRevision) {
        const uncertain =
          !saved && !(reason instanceof FormActionFailure && reason.outcome === "rejected");
        message.value = saved
          ? "The save returned, but its destination could not be opened. Check the mission records before another attempt."
          : uncertain
            ? "The save outcome is unknown. Your draft is still here. Check the mission records before trying again."
            : "The save was rejected. Your draft is still here; check the values and try again.";
        if (uncertain) {
          saved = true;
          accepted.value = false;
        }
      }
    } finally {
      if (!disposed && revision === saveRevision) saving.value = false;
    }
  }
  return { feedback, outcome, validate, save, saving, reset };
}
