<script setup lang="ts">
import type { RemoteState } from "@/api/index.ts";
import { formatClock, ApEmptyState, ApEventLine, ApPanel, ApRemote } from "@/ui";
import type { LogLine } from "./eventLog.ts";

/** B2 · Event log: the spacecraft's last 24 h (mission events + this alarm's lifecycle actions). */
defineProps<{ state: RemoteState<unknown>; lines: readonly LogLine[]; scid: number }>();
defineEmits<{ retry: [] }>();
</script>

<template>
  <ApPanel index="B2" title="Event log" pane flush>
    <template #meta>
      <RouterLink
        :to="{ name: 'ops.timeline', query: { sc: String(scid) } }"
        class="max-md:hit-44 text-text-3 no-underline hover:text-readout"
        >Full timeline →</RouterLink
      >
    </template>
    <ApRemote :state="state" loading-label="LOADING EVENTS…" @retry="$emit('retry')">
      <ApEmptyState v-if="lines.length === 0" headline="No events in the last 24 h" />
      <ol v-else class="m-0 list-none px-4 py-2">
        <ApEventLine
          v-for="line in lines"
          :key="line.key"
          :time="`${formatClock(new Date(line.at))}Z`"
          :datetime="line.at"
          :state="line.state"
          >{{ line.text
          }}<template v-if="line.sampleTo">
            ·
            <RouterLink :to="line.sampleTo" class="text-readout hover:underline"
              >Show sample</RouterLink
            ></template
          ></ApEventLine
        >
      </ol>
    </ApRemote>
  </ApPanel>
</template>
