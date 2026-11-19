<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { formatClock, plural, ApEventLine } from "@/ui";
import type { MissionEvent } from "./api.ts";
import {
  byHour,
  craftLink,
  namedCraft,
  needsSpacecraftPrefix,
  severityState,
  subjectLink,
} from "./model.ts";

/**
 * E2 · Events newest first under UTC hour headers. The server sentence names its subject and links
 * to it (refs.subject), else to the spacecraft it names.
 */
/** `selectedId` makes each row's time a toggle for the event detail (ux U71 A8). */
const props = defineProps<{
  events: readonly MissionEvent[];
  selectedId?: string | null | undefined;
}>();
const emit = defineEmits<{ select: [id: string] }>();
const groups = computed(() => byHour(props.events));
/** Distinct named spacecraft of a folded row, in scid order (an unnamed one is left out). */
const spacecraftOf = (members: readonly MissionEvent[]) =>
  [
    ...new Map(
      members.flatMap((m) => {
        const sc = namedCraft(m);
        return sc ? [[sc.id, sc] as const] : [];
      }),
    ).values(),
  ].sort((a, b) => a.scid - b.scid);
</script>

<template>
  <section v-for="group in groups" :key="group.hour" :aria-label="group.hour">
    <h3 class="ap-label m-0 border-b border-hairline px-4 pt-3 pb-1.5">{{ group.hour }}</h3>
    <ol class="m-0 list-none px-4 py-1">
      <ApEventLine
        v-for="{ key, event, count, firstAt, members, label } in group.rows"
        :key="key"
        :time="`${formatClock(new Date(event.at))}Z`"
        :datetime="event.at"
        :state="severityState(event.severity)"
        :data-event-id="event.id"
        :selected="selectedId === undefined ? undefined : selectedId === event.id"
        @select="emit('select', event.id)"
      >
        <details v-if="members.length" class="inline">
          <summary class="cursor-pointer">
            {{ label }}
            <span class="font-mono">{{
              spacecraftOf(members).length
                ? `· ${plural(spacecraftOf(members).length, "spacecraft", "spacecraft")}`
                : `× ${members.length}`
            }}</span>
          </summary>
          <span class="flex flex-wrap gap-x-3 pt-1 font-mono text-sm">
            <RouterLink
              v-for="sc in spacecraftOf(members)"
              :key="sc.id"
              :to="{ name: 'ops.spacecraft', params: { scId: sc.scid } }"
              class="max-md:hit-44 text-readout no-underline hover:underline"
              >{{ sc.name }}</RouterLink
            >
          </span>
          <ul v-if="!spacecraftOf(members).length" class="m-0 list-none p-0 pt-1 text-sm">
            <li v-for="m in members" :key="m.id">
              <RouterLink
                v-if="subjectLink(m)"
                :to="subjectLink(m) ?? ''"
                class="max-md:hit-44 text-readout no-underline hover:underline"
                >{{ m.text }}</RouterLink
              ><template v-else>{{ m.text }}</template>
            </li>
          </ul>
        </details>
        <template v-else>
          <template v-if="craftLink(event) && needsSpacecraftPrefix(event)"
            ><RouterLink
              :to="craftLink(event)?.to ?? ''"
              class="text-readout no-underline hover:underline"
              >{{ craftLink(event)?.label }}</RouterLink
            >
            ·
          </template>
          <RouterLink
            v-if="subjectLink(event)"
            :to="subjectLink(event) ?? ''"
            class="text-readout no-underline hover:underline"
            >{{ event.text }}</RouterLink
          >
          <RouterLink
            v-else-if="craftLink(event)"
            :to="craftLink(event)?.to ?? ''"
            class="text-readout no-underline hover:underline"
            >{{ event.text }}</RouterLink
          ><template v-else>{{ event.text }}</template
          ><!-- detail is a finished line from the server (api f66f2a633): shown as is. -->
          <span v-if="event.detail" class="text-text-3"> {{ event.detail }}</span
          ><span v-if="count > 1" class="font-mono text-text-3">
            × {{ count }} since {{ formatClock(new Date(firstAt)) }}Z</span
          >
        </template>
      </ApEventLine>
    </ol>
  </section>
</template>
