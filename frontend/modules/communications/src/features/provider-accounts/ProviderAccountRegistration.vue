<script setup lang="ts">
import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import ProviderAccountNew from "./ProviderAccountNew.vue";
import { RegistrationActionFailure, type RegistrationPort } from "./registration-port";
import type { ProviderAccountPayload, ProviderAccountValues } from "./registration.contracts";
import {
  readRegistrationPatch,
  registrationReady,
  registrationReceipt,
  registrationValues,
  sameRegistrationValues,
  type RegistrationModel,
} from "./registration.validation";

const props = defineProps<{
  model: RegistrationModel;
  port: RegistrationPort;
  organizationId: string;
}>();
const form = shallowRef(props.model.form);
const validating = ref(false),
  saving = ref(false),
  locked = ref(false),
  accepted = ref(false);
const message = ref<string | null>(null);
let generation = 0,
  revision = 0,
  disposed = false,
  running = false;
let latest: ProviderAccountValues | null = null;
const canSave = computed(
  () =>
    accepted.value &&
    !validating.value &&
    !saving.value &&
    !locked.value &&
    registrationReady(form.value),
);
watch(
  () => [props.model, props.port, props.organizationId],
  () => {
    ++generation;
    ++revision;
    running = false;
    latest = null;
    form.value = props.model.form;
    validating.value = false;
    saving.value = false;
    locked.value = false;
    accepted.value = false;
    message.value = null;
  },
  { flush: "sync" },
);
onBeforeUnmount(() => {
  disposed = true;
  ++generation;
});
function validate(payload: ProviderAccountPayload) {
  if (disposed || saving.value || locked.value) return;
  latest = { ...payload.provider_account };
  ++revision;
  accepted.value = false;
  validating.value = true;
  message.value = null;
  void drain();
}
async function drain() {
  if (running || !latest || disposed) return;
  running = true;
  const request = { ...latest },
    currentGeneration = generation,
    currentRevision = revision;
  try {
    const response = await props.port.execute("validate", { provider_account: request });
    if (disposed || generation !== currentGeneration || revision !== currentRevision) return;
    const result = readRegistrationPatch(response, props.model.form);
    form.value = result;
    latest = registrationValues(result);
    accepted.value = true;
  } catch {
    if (!disposed && generation === currentGeneration && revision === currentRevision) {
      message.value =
        "The draft could not be checked. Your entries are still here; recheck before registering.";
      accepted.value = false;
    }
  } finally {
    if (!disposed && generation === currentGeneration) {
      running = false;
      if (revision !== currentRevision) void drain();
      else validating.value = false;
    }
  }
}
function retry() {
  if (latest) validate({ provider_account: latest });
}
async function save(payload: ProviderAccountPayload) {
  if (disposed || saving.value || locked.value) return;
  if (
    !canSave.value ||
    !sameRegistrationValues(payload.provider_account, registrationValues(form.value))
  ) {
    validate(payload);
    return;
  }
  const currentGeneration = generation,
    activePort = props.port;
  saving.value = true;
  message.value = null;
  try {
    const result = await activePort.execute("save", {
      provider_account: { ...payload.provider_account },
    });
    if (disposed || generation !== currentGeneration) return;
    locked.value = true;
    accepted.value = false;
    const expected =
      "/provider-accounts/" + encodeURIComponent(form.value.fields.provider_account_id.value);
    if (registrationReceipt(result).navigate !== expected)
      throw new Error("Invalid registration destination");
    activePort.navigate(expected);
  } catch (reason) {
    if (disposed || generation !== currentGeneration) return;
    const rejected =
      !locked.value && reason instanceof RegistrationActionFailure && reason.outcome === "rejected";
    locked.value = !rejected;
    message.value = rejected
      ? "Registration was rejected. Your draft is still here; check the values and try again."
      : "The registration outcome could not be confirmed. Check provider accounts before another attempt.";
  } finally {
    if (!disposed && generation === currentGeneration) saving.value = false;
  }
}
</script>
<template>
  <div>
    <fieldset class="contents" :disabled="saving || locked">
      <ProviderAccountNew
        :page="model.page"
        :form="form"
        :managed-draft="true"
        :can-save="canSave"
        @validate="validate"
        @save="save"
      />
    </fieldset>
    <p
      id="provider-account-registration-status"
      role="status"
      aria-live="polite"
      class="mt-4 text-sm text-base-content/70"
    >
      {{
        saving
          ? "Registering provider account…"
          : validating
            ? "Checking the current draft…"
            : (message ??
              (canSave
                ? "Draft synchronized. Ready to register."
                : "Complete the form before registering."))
      }}
    </p>
    <button
      v-if="message && !locked && !saving && !validating"
      id="recheck-provider-account-draft"
      type="button"
      class="btn btn-sm btn-ghost mt-2"
      @click="retry"
    >
      Recheck draft
    </button>
    <a
      v-if="locked"
      id="check-provider-account-records"
      href="/provider-accounts"
      class="btn btn-sm mt-3"
      >Check provider accounts</a
    >
  </div>
</template>
