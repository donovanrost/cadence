<script setup lang="ts">
import { computed } from "vue";
import { formatClock, ApEventLine } from "@/ui";
import type { Group } from "../groups/show.ts";
import { releaseLogContext } from "../groups/release.ts";
import { eventText, type PersonName } from "../groups/words.ts";

/** D's request log, newest first: under the decision while it's open, and under its record after. */
const props = defineProps<{ group: Group; nameOf: PersonName }>();
const events = computed(() =>
  [...props.group.events].sort((a, b) => Date.parse(b.at) - Date.parse(a.at)),
);
const release = computed(() =>
  releaseLogContext(
    props.group.uplink,
    props.group.targets.length === 1 ? (props.group.targets[0]?.name ?? null) : null,
  ),
);
</script>

<template>
  <p class="ap-label m-0 pb-1.5">Request log</p>
  <ol class="m-0 list-none p-0">
    <ApEventLine
      v-for="e in events"
      :key="e.id"
      :time="formatClock(new Date(e.at))"
      :datetime="e.at"
      state="neutral"
      >{{ eventText(e, nameOf, group.targets, release) }}</ApEventLine
    >
  </ol>
</template>
