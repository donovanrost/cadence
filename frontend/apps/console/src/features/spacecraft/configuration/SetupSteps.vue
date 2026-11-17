<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { ApCallout, ApPanel } from "@/ui";
import type { ConfigurationSnapshot } from "./api.ts";
import { notSetUpLine, setupSteps } from "./words.ts";

/** U94: "Not set up" and the steps before the draft can be sent, numbered, each to its section. */
const props = defineProps<{ snapshot: ConfigurationSnapshot }>();
const steps = computed(() => setupSteps(props.snapshot.document, props.snapshot.name));
const telemetryOn = computed(
  () =>
    props.snapshot.switches?.telemetry_enabled.value ?? props.snapshot.document.telemetry_enabled,
);
</script>

<template>
  <ApCallout v-if="snapshot.active === null" tone="info">{{
    notSetUpLine(snapshot.name, telemetryOn)
  }}</ApCallout>
  <ApPanel v-if="steps.length" index="C1" title="Steps before it can be sent" flush>
    <ol class="m-0 flex list-decimal flex-col gap-2 py-3 pr-4 pl-9">
      <li v-for="s in steps" :key="s.key" class="text-md text-readout">
        <RouterLink
          :to="{
            name: 'setup.spacecraft.configuration',
            params: { spacecraftId: snapshot.spacecraft_id, section: 'catalog' },
          }"
          class="max-md:hit-44 text-readout underline hover:text-bright"
          >{{ s.label }}</RouterLink
        >
        <span class="block text-sm text-text-2">{{ s.detail }}</span>
      </li>
    </ol>
  </ApPanel>
</template>
