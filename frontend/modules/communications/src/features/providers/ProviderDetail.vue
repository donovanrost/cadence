<script setup lang="ts">
import { computed, shallowRef, watch } from "vue";
import CommsProviderShow from "./CommsProviderShow.vue";
import { readDetail } from "./read-validation";
import type { ProviderDetailModel } from "./provider-detail.contracts";
import type { ProviderAction, ProviderPort } from "./provider-port";
import type { ReadContext } from "../../shared/read-contracts";
import { invalid, missionPath } from "../../shared/read-validation";
import { providerReceipt, useProviderOperation } from "./useProviderOperation";
const props = defineProps<{
  model: ProviderDetailModel;
  port: ProviderPort;
  context: ReadContext;
  locked?: boolean;
}>();
const model = shallowRef(props.model);
let minimumVersion = Number(props.model.provider.version.slice(1));
const operation = useProviderOperation(
  () => props.port,
  () => props.context,
);
watch(
  () => props.model,
  (value) => {
    const changedProvider = value.provider.provider_id !== model.value.provider.provider_id;
    // Host snapshots can arrive before the action receipt. Keep that operation
    // alive so its confirmed navigation or refresh can finish.
    if (!changedProvider && (operation.pending.value || operation.locked.value)) return;
    const version = Number(value.provider.version.slice(1));
    if (!changedProvider && version < minimumVersion) return;
    model.value = value;
    minimumVersion = version;
    if (changedProvider) operation.reset();
  },
  { flush: "sync" },
);
const actions = computed(
  () =>
    Object.fromEntries(
      Object.entries(model.value.actions).map(([key, action]) => [
        key,
        {
          ...action,
          disabled:
            action.disabled || props.locked || operation.pending.value || operation.locked.value,
        },
      ]),
    ) as ProviderDetailModel["actions"],
);
async function refresh(port: ProviderPort, current: () => boolean) {
  const id = model.value.provider.provider_id,
    context = props.context;
  const next = readDetail(await port.query(), context);
  if (next.provider.provider_id !== id || Number(next.provider.version.slice(1)) < minimumVersion)
    invalid();
  if (current()) {
    model.value = next;
    minimumVersion = Number(next.provider.version.slice(1));
  }
  return "ready" as const;
}
function execute(action: Exclude<ProviderAction, "create_provider">) {
  const mapping = {
    validate_provider: "validate",
    sync_provider: "sync",
    archive_provider: "archive",
  } as const;
  if (actions.value[mapping[action]].disabled) return;
  const id = model.value.provider.provider_id;
  const context = props.context;
  void operation.run(async (port, current) => {
    const receipt = providerReceipt(await port.execute(action, { provider_id: id }));
    if (!current()) return "done";
    if (receipt.id !== id || receipt.version < Number(model.value.provider.version.slice(1)))
      invalid();
    if (action === "archive_provider") {
      port.navigate(missionPath(context) + "/comms/providers");
      return "done";
    }
    minimumVersion = receipt.version;
    try {
      return await refresh(port, current);
    } catch {
      throw new Error("Provider state could not be confirmed after the operation.");
    }
  });
}
</script>
<template>
  <div>
    <div
      id="provider-operation-status"
      role="status"
      aria-live="polite"
      class="mb-4 text-sm text-base-content/70"
    >
      <p v-if="operation.pending.value">Updating provider state…</p>
      <p v-else-if="operation.message.value">{{ operation.message.value }}</p>
      <button
        v-if="operation.message.value || operation.locked.value || props.locked"
        id="refresh-provider-state"
        type="button"
        class="btn btn-sm mt-3"
        :disabled="operation.pending.value"
        @click="operation.run(refresh, true)"
      >
        Refresh provider state
      </button>
    </div>
    <CommsProviderShow
      v-bind="model"
      :actions="actions"
      @validate-provider="execute('validate_provider')"
      @sync-provider="execute('sync_provider')"
      @archive-provider="execute('archive_provider')"
    />
  </div>
</template>
