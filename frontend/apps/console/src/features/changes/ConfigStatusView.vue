<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import type { RouteLocationRaw } from "vue-router";
import { computed } from "vue";
import { outageText, useMissionScope, useRuntimeStatus } from "@/shell";
import { configRuntime, runtimeWord } from "./runtime.ts";
import { useConfigState } from "./useConfigState.ts";

/**
 * Setup top bar: `CONFIG r5 · 2 STAGED`; after an apply `CONFIG r6 · APPLYING` (readout) or
 * `CONFIG r6 · NOT APPLIED` (caution, lead's U38 sentence as its title; ux). Nothing until the
 * mission has change sets (U2).
 */
const props = defineProps<{ missionId: MissionId }>();
const { state } = useConfigState(props.missionId);
const scope = useMissionScope();
const runtimeStatus = useRuntimeStatus();
const config = computed(() => (state.value.status === "ready" ? state.value.value : null));
const staged = computed(() => config.value?.change_set?.staged_count ?? 0);
const runtime = computed(() => configRuntime(runtimeStatus.value));
const title = computed(() =>
  runtime.value === "not_applied" && runtimeStatus.value
    ? outageText(runtimeStatus.value, scope.value.mission.name)
    : undefined,
);
/** Staged changes lead to review; a runtime state to the revision it's about; else the list. */
const to = computed((): RouteLocationRaw =>
  staged.value > 0
    ? { name: "setup.changes" }
    : runtime.value && config.value
      ? { name: "setup.revision", params: { revision: String(config.value.head.revision) } }
      : { name: "setup.revisions" },
);
</script>

<template>
  <RouterLink
    v-if="config"
    :to="to"
    :title="title"
    class="flex items-center gap-2 px-3 font-mono text-sm text-readout no-underline hover:text-bright"
  >
    <span class="text-text-4">CONFIG</span> r{{ config.head.revision
    }}<span
      v-if="runtime"
      :class="runtime === 'not_applied' ? 'text-caution-text' : 'text-readout'"
    >
      · {{ runtimeWord[runtime] }}</span
    ><span v-if="staged > 0" class="text-text-3"> · {{ staged }} STAGED</span>
  </RouterLink>
</template>
