<script setup lang="ts">
import { computed, toRef } from "vue";
import { describeApiError, type MissionId } from "@/api/index.ts";
import { useSpacecraftNames } from "@/features/scheduling/names.ts";
import { formatClock, formatCount, ApButton, ApEventLine, ApRemote } from "@/ui";
import type { Group } from "../groups/show.ts";
import { releaseLogContext } from "../groups/release.ts";
import { eventState, eventText, type PersonName } from "../groups/words.ts";
import { eventTargets } from "./eventNames.ts";
import { useGroupEvents } from "./useGroupPages.ts";

/**
 * The request log, newest first: under the decision while it's open, under its record after, and
 * Uplink & verify's U3. #795: a page of events at a time (the latest first; Load older reads
 * back), re-read when the group says events were added.
 */
const props = defineProps<{
  group: Group;
  nameOf: PersonName;
  missionId: MissionId;
  /** U3 marks the lines that need someone; the decision's log stays gray. */
  marked?: boolean;
}>();
const pages = useGroupEvents(toRef(props, "missionId"), toRef(props, "group"));
const loaded = computed(() =>
  pages.state.value.status === "ready" ? pages.state.value.value : null,
);
const events = computed(() =>
  [...(loaded.value?.items ?? [])].sort((a, b) => Date.parse(b.at) - Date.parse(a.at)),
);
const craftName = useSpacecraftNames(toRef(props, "missionId"));
const targets = computed(() => eventTargets(events.value, props.group, craftName));
const release = computed(() =>
  releaseLogContext(
    props.group.uplink,
    props.group.target_count === 1 ? (props.group.targets[0]?.name ?? null) : null,
  ),
);
</script>

<template>
  <!-- The decision's log carries its own label; U3's panel names it. -->
  <p v-if="!marked" class="ap-label m-0 pb-1.5">Request log</p>
  <ApRemote
    :state="pages.state.value"
    loading-label="Loading the request log…"
    @retry="pages.refetch"
  >
    <template #default="{ value: page }">
      <p v-if="pages.refreshError.value" role="status" class="m-0 py-1 text-sm text-caution-text">
        Couldn't refresh the log: {{ describeApiError(pages.refreshError.value) }}. Showing what was
        read before.
      </p>
      <ol class="m-0 list-none p-0">
        <ApEventLine
          v-for="e in events"
          :key="e.id"
          :time="formatClock(new Date(e.at))"
          :datetime="e.at"
          :state="marked ? eventState(e) : 'neutral'"
          :mono="marked"
          >{{ eventText(e, nameOf, targets, release) }}</ApEventLine
        >
      </ol>
      <div
        v-if="page.next !== null || pages.moreError.value"
        class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-2.5 text-sm text-text-3"
      >
        <span
          >{{ formatCount(page.items.length) }} of {{ formatCount(page.meta.total) }} entries
          shown</span
        >
        <ApButton
          size="compact"
          :disabled="pages.moreBusy.value || page.next === null"
          :disabled-reason="pages.moreBusy.value ? 'Loading…' : 'Every entry is shown'"
          @click="pages.more"
          >Load older</ApButton
        >
        <!-- It answers the person's own click: an alert, always mounted (a11y B6). -->
        <span role="alert" class="text-caution-text">{{
          pages.moreError.value
            ? `Couldn't load older entries: ${describeApiError(pages.moreError.value)}`
            : ""
        }}</span>
      </div>
    </template>
  </ApRemote>
</template>
