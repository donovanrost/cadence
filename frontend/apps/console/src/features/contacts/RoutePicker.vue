<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApTag } from "@/ui";
import { hiddenLine, routeLabel, uplinkNote, visibleRoutes, type Route } from "./routes.ts";

/**
 * Book a pass's Route (ux Contacts.md §Book a pass, A16b): 'Any route', or chips grouped by station
 * ('SVA · Northlight'), unpinned routes under their provider ('Northlight · any of its stations').
 * Uplink routes carry the UP tag; the others say 'downlink only' or 'uplink varies by station'.
 */
const props = defineProps<{ routes: readonly Route[]; withUplink: boolean; spacecraft: string }>();
const chosen = defineModel<string[]>({ required: true });
const view = computed(() => visibleRoutes(props.routes, props.withUplink, chosen.value));
const flip = (key: string) =>
  (chosen.value = chosen.value.includes(key)
    ? chosen.value.filter((k) => k !== key)
    : [...chosen.value, key]);
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <span class="ap-label">Route</span>
    <p class="m-0 text-sm text-text-3">Station, provider and path.</p>
    <div role="group" aria-label="Route" class="flex flex-wrap items-center gap-1.5">
      <ApButton
        size="compact"
        :variant="chosen.length === 0 ? 'primary' : 'ghost'"
        :aria-pressed="chosen.length === 0"
        @click="chosen = []"
        >Any route</ApButton
      >
      <span v-for="r in view.shown" :key="r.key" class="inline-flex items-center gap-1.5">
        <ApButton
          size="compact"
          :variant="chosen.includes(r.key) ? 'primary' : 'ghost'"
          :aria-pressed="chosen.includes(r.key)"
          @click="flip(r.key)"
          >{{ routeLabel(r, routes) }}</ApButton
        >
        <ApTag v-if="r.uplink === true" state="neutral" label="Up" />
        <span v-else class="text-sm text-text-3">{{ uplinkNote(r) }}</span>
      </span>
    </div>
    <p v-if="view.hidden" class="m-0 text-sm text-text-3">
      {{ hiddenLine(view.hidden, spacecraft) }}
    </p>
  </div>
</template>
