<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { formatClock, ApEventLine } from "@/ui";
import type { MissionEvent } from "./api.ts";
import { byHour, severityState } from "./model.ts";

/** E2 · Events newest first under UTC hour headers; spacecraft names link to the spacecraft. */
const props = defineProps<{ events: readonly MissionEvent[] }>();
const groups = computed(() => byHour(props.events));
</script>

<template>
  <section v-for="group in groups" :key="group.hour" :aria-label="group.hour">
    <h3 class="ap-label m-0 border-b border-hairline px-4 pt-3 pb-1.5">{{ group.hour }}</h3>
    <ol class="m-0 list-none px-4 py-1">
      <ApEventLine
        v-for="event in group.events"
        :key="event.id"
        :time="`${formatClock(new Date(event.at))}Z`"
        :datetime="event.at"
        :state="severityState(event.severity)"
      >
        <RouterLink
          v-if="event.spacecraft"
          :to="{
            name: 'ops.spacecraft',
            params: { scId: String(event.spacecraft.scid) },
            ...(event.refs.alarm_id ? { query: { alarm: event.refs.alarm_id } } : {}),
          }"
          class="text-readout no-underline hover:underline"
          >{{ event.spacecraft.name }}</RouterLink
        ><template v-if="event.spacecraft"> · </template>{{ event.text }}
      </ApEventLine>
    </ol>
  </section>
</template>
