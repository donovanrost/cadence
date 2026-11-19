<script setup lang="ts">
import type { FocusDay } from "./focus-day.ts";

/** K1 C's 24 h strip: pass blocks (buttons, select for D) and labelled gaps; the longest is brighter. */
defineProps<{ view: FocusDay; name: string; selected: string | null }>();
defineEmits<{ select: [snapshotId: string] }>();
const pct = (f: number) => `${(f * 100).toFixed(3)}%`;
const TICKS = [0, 6, 12, 18, 24];
</script>

<template>
  <div class="relative h-12 border-y border-hairline" role="group" :aria-label="`${name} passes`">
    <span
      v-for="(g, i) in view.gaps"
      :key="`gap-${i}`"
      aria-hidden="true"
      class="absolute top-1/2"
      :class="g.over ? 'h-0.5 bg-caution' : g.longest ? 'h-0.5 bg-text-2' : 'h-px bg-text-4'"
      :style="{ left: pct(g.from), width: pct(g.to - g.from) }"
    >
      <span
        class="absolute -top-4 left-1/2 -translate-x-1/2 font-mono text-xs whitespace-nowrap"
        :class="g.over ? 'text-caution-text' : g.longest ? 'text-readout' : 'text-text-4'"
        >{{ g.text }}</span
      >
    </span>
    <button
      v-for="p in view.passes"
      :key="p.id"
      type="button"
      class="absolute top-2 bottom-2 min-w-1 cursor-pointer border-0 p-0"
      :class="
        p.id === selected
          ? 'bg-readout shadow-[0_0_0_2px_var(--color-readout)]'
          : 'bg-text-2 hover:bg-readout'
      "
      :style="{ left: pct(p.from), width: pct(p.to - p.from) }"
      :aria-label="`Pass ${p.text}`"
      :aria-pressed="p.id === selected"
      :title="p.text"
      @click="$emit('select', p.id)"
    />
  </div>
  <div aria-hidden="true" class="relative h-4 font-mono text-xs text-text-4">
    <span
      v-for="h in TICKS"
      :key="h"
      class="absolute"
      :class="h === 0 ? '' : h === 24 ? '-translate-x-full' : '-translate-x-1/2'"
      :style="{ left: pct(h / 24) }"
      >{{ String(h).padStart(2, "0") }}Z</span
    >
  </div>
</template>
