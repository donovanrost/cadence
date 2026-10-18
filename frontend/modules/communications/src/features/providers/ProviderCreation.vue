<script setup lang="ts">
import { computed, ref, watch } from "vue";
import CommsProviderNew from "./CommsProviderNew.vue";
import type { ProviderNewModel } from "./form-validation";
import type { ProviderPort } from "./provider-port";
import type { ReadContext } from "../../shared/read-contracts";
import {
  providerFieldKeys,
  type ProviderPayload,
  type ProviderValues,
} from "./provider-new.contracts";
import { missionPath } from "../../shared/read-validation";
import { providerReceipt, useProviderOperation } from "./useProviderOperation";
const props = defineProps<{ model: ProviderNewModel; port: ProviderPort; context: ReadContext }>();
const initial = () =>
  Object.fromEntries(
    providerFieldKeys.map((key) => [key, props.model.form.fields[key].value]),
  ) as ProviderValues;
const draft = ref(initial());
const operation = useProviderOperation(
  () => props.port,
  () => props.context,
);
watch(
  () => props.model,
  () => {
    draft.value = initial();
    operation.reset();
  },
);
const binding = computed(() =>
  props.model.accounts.bindings.find(
    (binding) => binding.grant_id === draft.value.provider_account_grant_id,
  ),
);
const accounts = computed(() => ({
  ...props.model.accounts,
  selected: binding.value?.summary ?? null,
}));
const canSave = computed(() => {
  if (
    !binding.value ||
    !draft.value.display_name.trim() ||
    operation.pending.value ||
    operation.locked.value
  )
    return false;
  if (
    !["approval_required", "bounded_automatic"].includes(draft.value.policy_mode) ||
    !["retain_last_accepted", "cancel_if_actionable"].includes(draft.value.deadline_behavior)
  )
    return false;
  if (draft.value.policy_mode === "bounded_automatic") {
    for (const key of props.model.form.conditional.bounded_policy.field_keys) {
      const field = props.model.form.fields[key],
        value = draft.value[key];
      if (
        field.type === "number" &&
        (!/^\d+$/.test(value) ||
          !Number.isSafeInteger(Number(value)) ||
          Number(value) < (field.min ?? 0))
      )
        return false;
    }
  }
  return true;
});
function update(payload: ProviderPayload) {
  draft.value = { ...payload.provider };
}
function save(payload: ProviderPayload) {
  update(payload);
  if (!canSave.value || !binding.value) return;
  const selected = binding.value,
    context = props.context;
  const input = {
    provider: {
      ...draft.value,
      provider_account_id: selected.account_id,
      provider_account_version: String(selected.account_version),
      provider_account_grant_version: String(selected.grant_version),
    },
  };
  void operation.run(async (port, current) => {
    const receipt = providerReceipt(await port.execute("create_provider", input));
    if (current())
      port.navigate(missionPath(context) + "/comms/providers/" + encodeURIComponent(receipt.id));
    return "done";
  });
}
</script>
<template>
  <div>
    <fieldset class="contents" :disabled="operation.pending.value">
      <CommsProviderNew
        v-bind="model"
        :accounts="accounts"
        :managed-draft="true"
        :can-save="canSave"
        @validate="update"
        @save="save"
      />
    </fieldset>
    <p
      id="provider-creation-status"
      role="status"
      aria-live="polite"
      class="mt-4 text-sm text-base-content/70"
    >
      {{ operation.pending.value ? "Creating mission provider…" : operation.message.value }}
    </p>
    <a
      v-if="operation.locked.value"
      id="check-provider-records"
      :href="missionPath(context) + '/comms/providers'"
      class="btn btn-sm mt-3"
      >Check provider records</a
    >
  </div>
</template>
