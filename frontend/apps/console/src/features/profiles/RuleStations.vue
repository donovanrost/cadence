<script setup lang="ts">
import type { Station } from "@/features/stations/index.ts";
import { ApChip, ApSelect } from "@/ui";

/** A rule's stations as removable chips, plus a select of the active stations not yet in it. */
const props = defineProps<{ stations: readonly Station[] }>();
const ids = defineModel<string[]>({ required: true });
const stationLabel = (id: string) => {
  const s = props.stations.find((x) => x.id === id);
  return s ? (s.code ?? s.display_name) : id;
};
const options = () =>
  props.stations
    .filter((s) => s.lifecycle_state === "active" && !ids.value.includes(s.id))
    .map((s) => ({ value: s.id, label: `${s.code ?? ""} ${s.display_name}`.trim() }));
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <span class="ap-label">Stations</span>
    <div class="flex flex-wrap items-center gap-2">
      <ApChip
        v-for="id in ids"
        :key="id"
        removable
        :remove-label="`Remove ${stationLabel(id)}`"
        @remove="ids = ids.filter((s) => s !== id)"
        >{{ stationLabel(id) }}</ApChip
      >
      <div class="w-56">
        <ApSelect
          model-value=""
          label="Add station"
          hidden-label
          placeholder="+ station"
          :options="options()"
          @update:model-value="$event && (ids = [...ids, $event])"
        />
      </div>
    </div>
  </div>
</template>
