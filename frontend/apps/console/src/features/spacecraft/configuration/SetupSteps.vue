<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { ApCallout } from "@/ui";
import type { ConfigurationSnapshot } from "./api.ts";
import { notSetUpLine, setupSteps } from "./words.ts";

/** U94: "Not set up" and the steps before the draft can be sent, each linking to its section. */
const props = defineProps<{ snapshot: ConfigurationSnapshot }>();
const steps = computed(() => setupSteps(props.snapshot.document, props.snapshot.name));
</script>

<template>
  <ApCallout v-if="snapshot.active === null" tone="info">{{
    notSetUpLine(snapshot.name)
  }}</ApCallout>
  <ul v-if="steps.length" class="m-0 flex list-none flex-col gap-2 p-0" aria-label="Steps left">
    <li v-for="s in steps" :key="s.key" class="flex flex-col gap-0.5">
      <RouterLink
        :to="{
          name: 'setup.spacecraft.configuration',
          params: { spacecraftId: snapshot.spacecraft_id, section: 'catalog' },
        }"
        class="max-md:hit-44 text-md text-readout underline-offset-2 hover:underline"
        >{{ s.label }}</RouterLink
      >
      <span class="text-sm text-text-2">{{ s.detail }}</span>
    </li>
  </ul>
</template>
