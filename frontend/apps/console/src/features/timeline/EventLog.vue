<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { formatClock, plural, ApEventLine } from "@/ui";
import type { MissionEvent } from "./api.ts";
import { byHour, severityState } from "./model.ts";

/** E2 · Events newest first under UTC hour headers; spacecraft names link to the spacecraft. */
const props = defineProps<{ events: readonly MissionEvent[] }>();
const groups = computed(() => byHour(props.events));
/** Distinct spacecraft of a folded row, in scid order. */
const spacecraftOf = (members: readonly MissionEvent[]) =>
  [
    ...new Map(
      members.flatMap((m) => (m.spacecraft ? [[m.spacecraft.id, m.spacecraft] as const] : [])),
    ).values(),
  ].sort((a, b) => a.scid - b.scid);
</script>

<template>
  <section v-for="group in groups" :key="group.hour" :aria-label="group.hour">
    <h3 class="ap-label m-0 border-b border-hairline px-4 pt-3 pb-1.5">{{ group.hour }}</h3>
    <ol class="m-0 list-none px-4 py-1">
      <ApEventLine
        v-for="{ key, event, count, firstAt, members } in group.rows"
        :key="key"
        :time="`${formatClock(new Date(event.at))}Z`"
        :datetime="event.at"
        :state="severityState(event.severity)"
      >
        <details v-if="members.length" class="inline">
          <summary class="cursor-pointer">
            {{ event.text }} ·
            <span class="font-mono">{{
              plural(spacecraftOf(members).length, "spacecraft", "spacecraft")
            }}</span>
          </summary>
          <span class="flex flex-wrap gap-x-3 pt-1 font-mono text-sm">
            <RouterLink
              v-for="sc in spacecraftOf(members)"
              :key="sc.id"
              :to="{ name: 'ops.spacecraft', params: { scId: String(sc.scid) } }"
              class="max-md:hit-44 text-readout no-underline hover:underline"
              >{{ sc.name }}</RouterLink
            >
          </span>
        </details>
        <template v-else>
          <RouterLink
            v-if="event.spacecraft"
            :to="{ name: 'ops.spacecraft', params: { scId: String(event.spacecraft.scid) } }"
            class="text-readout no-underline hover:underline"
            >{{ event.spacecraft.name }}</RouterLink
          ><template v-if="event.spacecraft"> · </template>{{ event.text
          }}<span v-if="count > 1" class="font-mono text-text-3">
            × {{ count }} since {{ formatClock(new Date(firstAt)) }}Z</span
          >
        </template>
      </ApEventLine>
    </ol>
  </section>
</template>
