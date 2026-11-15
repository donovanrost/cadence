<script setup lang="ts">
// The console federation smoke's surfaces (mission_contracts, spacecraft_contracts): show what the
// host handed this remote and which release is serving it, and send one bridged action. Plain
// markup with stable ids, so the smoke can read it; no product UI.
import type { FullPageSurfaceProps, HostActionReceipt } from "@cadence/plugin-sdk";
import { onMounted, ref, shallowRef } from "vue";

const props = defineProps<FullPageSurfaceProps>();
const release = __CADENCE_REMOTE_RELEASE__;
const snapshot = shallowRef<Record<string, unknown>>();
const error = ref<string>();
const receipt = shallowRef<HostActionReceipt<{ accepted: boolean; nonce: string }>>();
const actionError = ref<string>();

onMounted(async () => {
  try {
    snapshot.value = await props.bridge.query<Record<string, unknown>>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
      context: props.context,
    });
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : String(reason);
  }
});

async function record(): Promise<void> {
  actionError.value = undefined;
  try {
    receipt.value = await props.bridge.execute({
      applicationKey: "contract_probe",
      applicationVersion: 1,
      surfaceId: props.surface.surfaceId,
      surfaceVersion: 1,
      actionId: "record_probe",
      input: { nonce: `nonce-${Date.now()}` },
      context: props.context,
    });
  } catch (reason) {
    actionError.value = reason instanceof Error ? reason.message : String(reason);
  }
}
</script>

<template>
  <section id="contract-probe-smoke" :data-surface="props.surface.surfaceId">
    <h2>Contract probe</h2>
    <p id="contract-probe-release" :data-release="release">{{ release }}</p>
    <pre v-if="snapshot" id="contract-probe-context">{{ JSON.stringify(snapshot) }}</pre>
    <p v-else-if="error" id="contract-probe-error">{{ error }}</p>
    <template v-if="props.surface.actions.includes('record_probe')">
      <button id="contract-probe-record" type="button" @click="record">Record probe</button>
      <p v-if="receipt" id="contract-probe-receipt" :data-nonce="receipt.result.nonce">
        {{ receipt.receiptId }}
      </p>
      <p v-if="actionError" id="contract-probe-action-error">{{ actionError }}</p>
    </template>
  </section>
</template>
