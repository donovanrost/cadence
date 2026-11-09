<script setup lang="ts">
import { fieldId } from "../field-id.ts";
import { formatDayTime } from "../lib/format.ts";
import type { TimePreset } from "./types.ts";

defineProps<{ presets: readonly TimePreset[]; selected: string | null }>();
defineEmits<{ pick: [preset: TimePreset] }>();
const uid = fieldId("ap-tp-presets");
</script>

<template>
  <section :aria-labelledby="uid" class="flex min-w-0 flex-col">
    <h3 :id="uid" class="ap-label px-1 pb-2">Mission times</h3>
    <p v-if="presets.length === 0" class="m-0 px-1 text-md text-text-3">
      No mission times for this context yet.
    </p>
    <ul class="m-0 flex list-none flex-col gap-px p-0">
      <li v-for="preset in presets" :key="preset.id">
        <button
          type="button"
          :aria-pressed="preset.id === selected"
          class="grid w-full cursor-pointer grid-cols-[minmax(0,1fr)_auto] items-baseline gap-x-3 border-0 px-3 py-2 text-left hover:bg-raised"
          :class="
            preset.id === selected
              ? 'bg-raised shadow-[inset_2px_0_0_var(--color-readout)]'
              : 'bg-transparent'
          "
          @click="$emit('pick', preset)"
        >
          <span class="text-base font-semibold text-readout">{{ preset.label }}</span>
          <span class="font-mono text-sm text-text-2">{{
            formatDayTime(new Date(preset.at)).slice(6)
          }}</span>
          <span v-if="preset.sub" class="col-span-2 text-sm text-text-3">{{ preset.sub }}</span>
        </button>
      </li>
    </ul>
  </section>
</template>
