<script setup lang="ts">
import { ApPanel } from "@/ui";
import type { PointCount } from "./list.ts";

/** L2 · Active alarms per point; choosing one filters L1 (spreading check). */
defineProps<{ points: readonly PointCount[]; selected: string | null }>();
const emit = defineEmits<{ select: [pointId: string | null] }>();
</script>

<template>
  <ApPanel index="L2" title="By point" pane flush>
    <ul class="m-0 list-none p-0">
      <li
        v-for="point in points"
        :key="point.pointId"
        class="border-t border-hairline first:border-t-0"
      >
        <button
          type="button"
          class="flex min-h-11 w-full cursor-pointer items-center gap-3 px-4 py-2 text-left hover:bg-raised"
          :class="
            point.pointId === selected ? 'bg-raised shadow-[inset_2px_0_0_var(--color-action)]' : ''
          "
          :aria-pressed="point.pointId === selected"
          @click="emit('select', point.pointId === selected ? null : point.pointId)"
        >
          <span class="w-32 truncate font-mono text-sm text-readout">{{ point.name }}</span>
          <span class="h-1.5 flex-1 bg-cell-empty" aria-hidden="true">
            <span
              class="block h-full"
              :class="point.critical > 0 ? 'bg-crit' : 'bg-caution'"
              :style="{ width: `${(point.count / (points[0]?.count ?? 1)) * 100}%` }"
            />
          </span>
          <span class="w-20 text-right font-mono text-sm text-text-3 tabular">
            {{ point.count
            }}<template v-if="point.critical > 0"> · {{ point.critical }} crit</template>
          </span>
        </button>
      </li>
    </ul>
  </ApPanel>
</template>
