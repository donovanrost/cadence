<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApButton, ApCallout } from "@/ui";
import { useCommandAccess } from "@/features/commands/index.ts";
import {
  NO_ACCESS,
  NO_ACCESS_SEEN,
  retryTargets,
  seenTargets,
  useSettlement,
} from "@/features/now/index.ts";

/**
 * U37 drawer block (#71): this pass's telemetry not yet stored, or lost (journal off). Retry
 * storing once Cadence stopped retrying; Mark as seen on lost telemetry (ux bda6f91d). Both need
 * operate_mission, the flag Recover uses (access.abort). The returned item shows at once.
 */
const props = defineProps<{ missionId: MissionId; passId: string }>();
const read = useSettlement(
  computed(() => props.missionId),
  computed(() => props.passId),
);
const settlement = read.item;
const access = useCommandAccess();
const busy = ref(false);
const note = ref<string | null>(null);
const action = computed(() => {
  const s = settlement.value;
  if (!s) return null;
  if (s.lost) return { label: "Mark as seen", busy: "Marking…", noAccess: NO_ACCESS_SEEN };
  return s.manual ? { label: "Retry storing", busy: "Retrying…", noAccess: NO_ACCESS } : null;
});
async function act() {
  const s = settlement.value;
  if (!s || busy.value) return;
  busy.value = true;
  note.value = null;
  try {
    const outcome = await (s.lost ? seenTargets : retryTargets)(props.missionId, [s.attention]);
    note.value = outcome.text;
    const returned = outcome.items[0];
    if (returned) read.patch(returned);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApCallout v-if="settlement" tone="caution">
    <p class="m-0 font-semibold">
      Telemetry from this pass {{ settlement.lost ? "was lost" : "isn't stored yet" }}.
    </p>
    <p class="m-0 text-text-2">{{ busy && action ? action.busy : settlement.evidence }}</p>
    <p v-if="settlement.tried && !settlement.lost" class="m-0 text-sm text-text-3">
      {{ settlement.tried }}
    </p>
    <p v-if="action && !access.abort" class="m-0 text-sm text-text-3">{{ action.noAccess }}</p>
    <p v-if="note" class="m-0 text-sm text-caution-text">{{ note }}</p>
    <template v-if="action && access.abort" #action>
      <ApButton size="compact" :disabled="busy" @click="act">{{ action.label }}</ApButton>
    </template>
  </ApCallout>
</template>
