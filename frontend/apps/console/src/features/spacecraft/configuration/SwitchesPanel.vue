<script setup lang="ts">
import { RouterLink } from "vue-router";
import { ApPanel } from "@/ui";
import type { ConfigurationSnapshot } from "./api.ts";
import { switchLine } from "./words.ts";

/**
 * DECISIONS #109 (U94): change sets own Telemetry and Commanding, so both are read-only here, each
 * with Open Operation (U40's panel on the craft's page, where they're staged).
 */
const props = defineProps<{ snapshot: ConfigurationSnapshot }>();
const rows = () => [
  {
    key: "telemetry",
    label: "Telemetry",
    line: switchLine(
      props.snapshot.switches?.telemetry_enabled,
      props.snapshot.document.telemetry_enabled,
      props.snapshot.name,
    ),
  },
  {
    key: "commanding",
    label: "Commanding",
    line: switchLine(
      props.snapshot.switches?.commanding_enabled,
      props.snapshot.document.commanding_enabled,
      props.snapshot.name,
    ),
  },
];
</script>

<template>
  <ApPanel index="C3" title="Operation" flush>
    <ul class="m-0 list-none divide-y divide-hairline p-0">
      <li v-for="r in rows()" :key="r.key" class="flex flex-col gap-1 px-4 py-3">
        <span class="ap-label">{{ r.label }}</span>
        <span class="text-md text-readout">{{ r.line }}</span>
        <RouterLink
          :to="{ name: 'setup.spacecraft.one', params: { spacecraftId: snapshot.spacecraft_id } }"
          class="max-md:hit-44 self-start text-sm text-readout underline hover:text-bright"
          >Open Operation</RouterLink
        >
      </li>
    </ul>
  </ApPanel>
</template>
