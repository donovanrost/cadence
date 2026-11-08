<script setup lang="ts">
import { computed } from "vue";
import { useConfigState } from "./useConfigState.ts";

/** Setup top bar: `CONFIG r5 · 2 STAGED`. Nothing until the mission has change sets (U2). */
const props = defineProps<{ missionId: string }>();
const { state } = useConfigState(props.missionId);
const config = computed(() => (state.value.status === "ready" ? state.value.value : null));
const staged = computed(() => config.value?.change_set?.staged_count ?? 0);
</script>

<template>
  <RouterLink
    v-if="config"
    :to="{ name: staged > 0 ? 'setup.changes' : 'setup.revisions' }"
    class="flex items-center gap-2 px-3 font-mono text-sm text-readout no-underline hover:text-bright"
  >
    <span class="text-text-4">CONFIG</span> r{{ config.head.revision
    }}<span v-if="staged > 0" class="text-text-3"> · {{ staged }} STAGED</span>
  </RouterLink>
</template>
