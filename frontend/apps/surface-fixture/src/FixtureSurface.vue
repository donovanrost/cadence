<script setup lang="ts">
// Shows what the host handed this remote (the query's host context) and which release is serving
// it, and sends one bridged action. Plain markup with stable ids for the smoke; no product UI.
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
      applicationKey: "surface_fixture",
      applicationVersion: 1,
      surfaceId: props.surface.surfaceId,
      surfaceVersion: 1,
      actionId: "record_nonce",
      input: { nonce: `nonce-${Date.now()}` },
      context: props.context,
    });
  } catch (reason) {
    actionError.value = reason instanceof Error ? reason.message : String(reason);
  }
}
</script>

<template>
  <section id="surface-fixture" :data-surface="props.surface.surfaceId">
    <h2>Surface fixture</h2>
    <p id="surface-fixture-release" :data-release="release">{{ release }}</p>
    <pre v-if="snapshot" id="surface-fixture-context">{{ JSON.stringify(snapshot) }}</pre>
    <p v-else-if="error" id="surface-fixture-error">{{ error }}</p>
    <template v-if="props.surface.actions.includes('record_nonce')">
      <button id="surface-fixture-record" type="button" @click="record">Record nonce</button>
      <p v-if="receipt" id="surface-fixture-receipt" :data-nonce="receipt.result.nonce">
        {{ receipt.receiptId }}
      </p>
      <p v-if="actionError" id="surface-fixture-action-error">{{ actionError }}</p>
    </template>
  </section>
</template>
