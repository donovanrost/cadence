<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { ApButton, ApCallout } from "@/ui";
import { recoverUplink, type RecoverOutcome } from "./readiness.ts";

/**
 * `Recover uplink` (U33): a secondary button, no confirm; while it runs it's disabled with
 * "Qualifying now". The outcome shows in words beside it.
 */
const props = defineProps<{
  missionId: MissionId;
  passId: string;
  recovering: boolean;
  canRecover: boolean;
}>();
const emit = defineEmits<{ changed: [] }>();
const busy = ref(false);
const outcome = ref<RecoverOutcome | null>(null);

async function recover() {
  busy.value = true;
  try {
    outcome.value = await recoverUplink(props.missionId, props.passId);
    emit("changed");
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <p v-if="!canRecover" class="m-0 text-sm text-text-2">
      Operators with mission access can recover the uplink.
    </p>
    <div v-else class="flex flex-wrap items-center gap-2">
      <ApButton size="compact" variant="secondary" :disabled="busy || recovering" @click="recover"
        >Recover uplink</ApButton
      >
      <span v-if="busy || recovering" class="font-mono text-xs text-text-2 uppercase"
        >Qualifying now</span
      >
    </div>
    <ApCallout v-if="outcome" :tone="outcome.tone">{{ outcome.text }}</ApCallout>
  </div>
</template>
