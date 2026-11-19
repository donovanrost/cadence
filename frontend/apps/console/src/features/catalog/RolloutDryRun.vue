<script setup lang="ts">
import { computed } from "vue";
import { ApCallout } from "@/ui";
import { dryRunLines } from "./rollout.ts";
import type { DryRun } from "./useRolloutDryRun.ts";

/** C3's counts, only from the server's dry run (ux): moves, who stays and why, cancels. */
const props = defineProps<{
  dryRun: DryRun;
  revision: Readonly<{ id: string; number: number }>;
  from: string | null;
  unprofiled: number;
}>();
const lines = computed(() =>
  props.dryRun.status === "ready"
    ? dryRunLines(props.dryRun.preview, props.revision, props.from, props.unprofiled)
    : [],
);
</script>

<template>
  <p v-if="dryRun.status === 'checking'" class="m-0 font-mono text-xs text-text-3 uppercase">
    Checking…
  </p>
  <ApCallout v-else-if="dryRun.status === 'failed'" tone="crit">{{ dryRun.text }}</ApCallout>
  <template v-else-if="dryRun.status === 'ready'">
    <ApCallout v-if="dryRun.noGo" tone="crit">NO-GO: {{ dryRun.noGo }}</ApCallout>
    <ul class="m-0 flex list-none flex-col gap-1 p-0 text-md">
      <li
        v-for="line in lines"
        :key="line.text"
        :class="line.tone === 'caution' ? 'text-caution' : 'text-readout'"
      >
        {{ line.text }}
      </li>
    </ul>
  </template>
</template>
