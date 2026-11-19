<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchPassTechnical } from "./api.ts";

/**
 * The selected pass's own Technical details (ux U50): second connections refused while its own
 * connection was up. They never open an item; the count shows here only when above 0.
 */
const props = defineProps<{ missionId: MissionId; passId: string }>();
const detail = useRemoteQuery(
  computed(() => ({ m: props.missionId, pass: props.passId })),
  (k, signal) => fetchPassTechnical(k.m, k.pass, signal),
);
useMissionInvalidation(
  computed(() => props.missionId),
  ["contacts"],
  detail.refetch,
);
const second = computed(() => {
  const s = detail.state.value;
  const n = s.status === "ready" ? (s.value.second_connections_refused ?? null) : null;
  return n !== null && n > 0 ? n : null;
});
</script>

<template>
  <details v-if="second !== null" class="text-xs text-text-3">
    <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
    <p class="m-0 pt-1 font-mono">Second connections refused: {{ second }}</p>
  </details>
</template>
