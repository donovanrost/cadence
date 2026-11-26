<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { ref } from "vue";
import { ApButton, ApCallout, ApSheet } from "@/ui";
import { rotateServiceIdentity, tokenFailure } from "./api.ts";
import TokenShown from "./TokenShown.vue";

/** Rotate (api-ops): confirms, then shows the new token once; the old one stops working now. */
const props = defineProps<{ id: string; name: string; organizationId: OrganizationId }>();
const emit = defineEmits<{ rotated: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const token = ref<string | null>(null);
const stored = ref(false);
const failure = ref<string | null>(null);
const busy = ref(false);
function open() {
  token.value = failure.value = null;
  stored.value = false;
  sheet.value?.open();
}
async function rotate() {
  busy.value = true;
  try {
    const r = await rotateServiceIdentity(props.id, props.organizationId);
    if (!r.ok) {
      failure.value = tokenFailure(r.error, "rotate");
      if (r.error.kind === "malformed") emit("rotated");
      return;
    }
    token.value = r.value.token;
    emit("rotated");
  } finally {
    busy.value = false;
  }
}
function done() {
  token.value = null;
  sheet.value?.close();
}
</script>

<template>
  <ApButton size="compact" variant="ghost" @click="open">Rotate…</ApButton>
  <ApSheet
    ref="sheet"
    :title="token ? 'Store the new token' : `Rotate ${name}'s token?`"
    :dismissible="!token"
  >
    <TokenShown v-if="token" v-model="stored" :token="token" />
    <p v-else class="m-0 text-md text-text-2">
      The old token stops working now. Anything using it needs the new one.
    </p>
    <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    <template #footer>
      <ApButton
        v-if="token"
        variant="primary"
        :disabled="!stored"
        disabled-reason="Tick “I've stored the token” first."
        @click="done"
        >Done</ApButton
      >
      <template v-else>
        <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
        <ApButton variant="danger" :disabled="busy" disabled-reason="Rotating…" @click="rotate"
          >Rotate</ApButton
        >
      </template>
    </template>
  </ApSheet>
</template>
