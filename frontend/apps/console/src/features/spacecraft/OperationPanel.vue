<script setup lang="ts">
import { computed } from "vue";
import { ApPanel, ApTag } from "@/ui";
import type { SpacecraftDetail } from "./detail.ts";
import { operationRows } from "./operation.ts";

/** U40 Operation: Commanding and Telemetry as running now. Changing one stages it (Edit, L17). */
const props = defineProps<{ detail: SpacecraftDetail }>();
const rows = computed(() => operationRows(props.detail));
</script>

<template>
  <ApPanel index="D5" title="Operation">
    <ul class="m-0 flex list-none flex-col divide-y divide-hairline p-0">
      <li
        v-for="row in rows"
        :key="row.key"
        class="flex flex-wrap items-start justify-between gap-3 py-3 first:pt-0 last:pb-0"
      >
        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <span class="text-base text-readout">{{ row.label }}</span>
          <span class="text-sm text-text-2">{{ row.help }}</span>
          <span class="text-md text-readout">{{ row.sentence }}</span>
        </div>
        <ApTag v-if="row.on === null" state="off" label="Not set" />
        <ApTag v-else-if="row.on" state="nominal" label="On" />
        <ApTag v-else state="off" label="Off" />
      </li>
    </ul>
  </ApPanel>
</template>
