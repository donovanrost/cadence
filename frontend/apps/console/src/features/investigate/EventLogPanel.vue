<script setup lang="ts">
import { computed } from "vue";
import { formatClock, ApEmptyState, ApEventLine, ApPanel } from "@/ui";
import { eventState, eventText, type EpisodeEvent } from "@/features/alarms/index.ts";

/**
 * B2 · Event log. Until the mission events read exists it shows the shown alarm's episode
 * events (raised, escalated, acknowledged, assigned, notes, cleared), newest first, and says so.
 */
const props = defineProps<{ events: readonly EpisodeEvent[] | null }>();
const newestFirst = computed(() =>
  props.events ? [...props.events].sort((a, b) => Date.parse(b.at) - Date.parse(a.at)) : [],
);
</script>

<template>
  <ApPanel index="B2" title="Event log" :meta="events ? 'this alarm only' : undefined" pane flush>
    <template v-if="!events" #meta>
      <RouterLink
        :to="{ name: 'ops.timeline' }"
        class="max-md:hit-44 text-text-3 no-underline hover:text-readout"
        >Full timeline →</RouterLink
      >
    </template>
    <ol v-if="events && events.length" class="m-0 list-none px-4 py-2">
      <ApEventLine
        v-for="event in newestFirst"
        :key="event.id"
        :time="`${formatClock(new Date(event.at))}Z`"
        :datetime="event.at"
        :state="eventState(event)"
        >{{ eventText(event) }}</ApEventLine
      >
    </ol>
    <ApEmptyState
      v-else
      state="off"
      headline="Event log not available"
      sentence="Spacecraft events aren't connected to this console yet."
    />
  </ApPanel>
</template>
