<script setup lang="ts">
import type { Station } from "@/features/stations/index.ts";
import { ref } from "vue";
import { ApChip, ApSelect, focusAfterRemove } from "@/ui";

/** A rule's stations as removable chips, plus a select of the active stations not yet in it. */
const props = defineProps<{ stations: readonly Station[] }>();
const ids = defineModel<string[]>({ required: true });
const stationLabel = (id: string) => {
  const s = props.stations.find((x) => x.id === id);
  // U25 (#308): a station the list doesn't have reads "Unknown station", never its id.
  return s ? (s.code ?? s.display_name) : "Unknown station";
};
const options = () =>
  props.stations
    .filter((s) => s.lifecycle_state === "active" && !ids.value.includes(s.id))
    .map((s) => ({ value: s.id, label: `${s.code ?? ""} ${s.display_name}`.trim() }));
// a11y A5: removing a chip takes its focused ×; land on the next chip's ×, else Add station.
const box = ref<HTMLElement | null>(null);
function remove(id: string) {
  const at = ids.value.indexOf(id);
  ids.value = ids.value.filter((s) => s !== id);
  void focusAfterRemove(box.value, 'button[aria-label^="Remove "]', at, () =>
    box.value?.querySelector("select"),
  );
}
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <span class="ap-label">Stations</span>
    <div ref="box" class="flex flex-wrap items-center gap-2">
      <ApChip
        v-for="id in ids"
        :key="id"
        removable
        :remove-label="`Remove ${stationLabel(id)}`"
        @remove="remove(id)"
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
