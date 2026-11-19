<script setup lang="ts">
import { computed } from "vue";
import { useMissionScope } from "@/shell";
import { useSpacecraftNames } from "@/features/scheduling/index.ts";
import type { AppHold } from "./holds.ts";

/**
 * U63: a HOLD that needs an app installed first links to that app's page in Setup › Apps (where
 * install happens). The sentence names up to 3 spacecraft; above that, their names are under Show.
 */
defineProps<{ holds: readonly AppHold[] }>();
const scope = useMissionScope();
const nameOf = useSpacecraftNames(computed(() => scope.value.mission.id));
const SHOWN_IN_SENTENCE = 3;
</script>

<template>
  <div
    v-for="h in holds"
    :key="h.appKey"
    class="flex flex-col gap-1 border-t border-hairline px-4 py-2.5 text-sm text-text-2"
  >
    <RouterLink
      :to="{ name: 'setup.app', params: { appKey: h.appKey } }"
      class="text-primary no-underline hover:underline"
      >Open Setup › Apps{{ h.appName ? ` (${h.appName})` : "" }}</RouterLink
    >
    <details v-if="h.spacecraftIds.length > SHOWN_IN_SENTENCE">
      <summary class="cursor-pointer text-text-2">Show {{ h.spacecraftIds.length }}</summary>
      <ul class="m-0 mt-1 flex list-none flex-col gap-0.5 p-0 font-mono text-xs text-text-2">
        <li v-for="id in h.spacecraftIds" :key="id">{{ nameOf(id)?.name ?? id }}</li>
      </ul>
    </details>
  </div>
</template>
