<script setup lang="ts">
import { ApStatusMark } from "@/ui";
import { fleetStates, type FleetState } from "./api.ts";
import { fleetOpState, fleetStateWord } from "./matrix.ts";

/** Multi-select of fleet states: mark + word toggles (never color alone), ≥44px targets. */
const props = defineProps<{ selected: readonly FleetState[] }>();
const emit = defineEmits<{ change: [states: FleetState[]] }>();

function toggle(state: FleetState) {
  const on = props.selected.includes(state);
  emit("change", on ? props.selected.filter((s) => s !== state) : [...props.selected, state]);
}
</script>

<template>
  <div role="group" aria-label="State" class="flex flex-wrap gap-1.5">
    <button
      v-for="state in fleetStates"
      :key="state"
      type="button"
      class="inline-flex h-11 cursor-pointer items-center gap-2 border px-3 font-display text-md font-semibold tracking-tag uppercase"
      :class="
        selected.includes(state)
          ? 'border-readout bg-raised text-readout'
          : 'border-line text-text-3 hover:text-readout'
      "
      :aria-pressed="selected.includes(state)"
      @click="toggle(state)"
    >
      <ApStatusMark :state="fleetOpState(state)" />{{ fleetStateWord(state) }}
    </button>
  </div>
</template>
