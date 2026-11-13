<script setup lang="ts">
import { computed } from "vue";
import { ApField, ApSelect } from "@/ui";
import type { FleetSpacecraft, FleetState } from "./api.ts";
import { fleetStateWord } from "./matrix.ts";
import { isFiltered, NO_FILTER, type FleetFilter } from "./filters.ts";
import PlanePicker from "./PlanePicker.vue";
import StateToggles from "./StateToggles.vue";

/** Filter row: plane · profile · state · in contact · search, plus Clear filters. Owner keeps them in the URL. */
const props = defineProps<{ filter: FleetFilter; spacecraft: readonly FleetSpacecraft[] }>();
const emit = defineEmits<{ change: [filter: FleetFilter] }>();
const set = (patch: Partial<FleetFilter>) => emit("change", { ...props.filter, ...patch });

const planes = computed(() =>
  [...new Set(props.spacecraft.flatMap((sc) => (sc.plane === null ? [] : [sc.plane])))].sort(
    (a, b) => a - b,
  ),
);
const profiles = computed(() => {
  const seen = new Map<string, string>();
  for (const sc of props.spacecraft)
    if (sc.profile) seen.set(sc.profile.id, sc.profile.name ?? sc.profile.id);
  return [
    { value: "all", label: "All profiles" },
    ...[...seen].map(([value, label]) => ({ value, label })),
  ];
});
const profile = computed({
  get: () => props.filter.profile ?? "all",
  set: (value: string) => set({ profile: value === "all" || value === "" ? null : value }),
});
const stateSummary = computed(() =>
  props.filter.states.length ? props.filter.states.map(fleetStateWord).join(", ") : "all",
);
const q = computed({ get: () => props.filter.q, set: (value: string) => set({ q: value.trim() }) });
</script>

<template>
  <div class="flex flex-none flex-wrap items-end gap-3">
    <PlanePicker
      v-if="planes.length"
      :planes="planes"
      :selected-plane="filter.plane"
      @select-plane="set({ plane: $event })"
    />
    <ApSelect
      v-if="profiles.length > 2"
      v-model="profile"
      label="Profile"
      hidden-label
      size="compact"
      :options="profiles"
    />
    <StateToggles
      class="max-md:hidden"
      :selected="filter.states"
      @change="(states: FleetState[]) => set({ states })"
    />
    <!-- Under 768 the five state toggles collapse into one disclosure (ux pass 1 #12). -->
    <details class="w-full border border-line md:hidden">
      <summary
        class="flex h-11 cursor-pointer items-center px-3 font-display text-md font-semibold tracking-tag text-text-2 uppercase"
      >
        State: {{ stateSummary }}
      </summary>
      <div class="p-2">
        <StateToggles
          :selected="filter.states"
          @change="(states: FleetState[]) => set({ states })"
        />
      </div>
    </details>
    <button
      type="button"
      class="inline-flex h-11 cursor-pointer items-center border px-3 font-display text-md font-semibold tracking-tag uppercase"
      :class="
        filter.contact
          ? 'border-readout bg-raised text-readout'
          : 'border-line text-text-3 hover:text-readout'
      "
      :aria-pressed="filter.contact"
      @click="set({ contact: !filter.contact })"
    >
      In contact
    </button>
    <div class="w-56 max-md:w-full">
      <ApField
        v-model="q"
        label="Search name or SCID"
        hidden-label
        type="search"
        placeholder="Name or SCID"
        mono
      />
    </div>
    <button
      v-if="isFiltered(filter)"
      type="button"
      class="h-11 cursor-pointer px-2 font-mono text-xs text-text-3 uppercase hover:text-readout"
      @click="emit('change', NO_FILTER)"
    >
      Clear filters
    </button>
  </div>
</template>
