<script setup lang="ts">
import { RouterLink } from "vue-router";
import { ApButton, ApCallout, ApListRow, ApPanel } from "@/ui";
import type { QueueItem } from "./queue.ts";

/** A2 · Action queue. Interim rows come from the fleet read (see queue.ts) until M6. */
defineProps<{ items: readonly QueueItem[]; nominal: number }>();
</script>

<template>
  <ApPanel
    index="A2"
    title="Action queue"
    :meta="`${items.length} open · sorted by urgency`"
    pane
    flush
  >
    <ApCallout v-if="items.length === 0" tone="nominal">
      Nothing needs you. {{ nominal }} spacecraft fresh and in limits.
    </ApCallout>
    <ul v-else class="m-0 list-none p-0">
      <ApListRow
        v-for="(item, i) in items"
        :key="item.key"
        :priority="`P${item.priority}`"
        :state="item.state"
        :sentence="item.sentence"
        v-bind="item.meta === null ? {} : { meta: item.meta }"
      >
        <template #title>
          <RouterLink
            v-if="item.titleTo"
            :to="item.titleTo"
            class="text-readout no-underline hover:text-bright hover:underline"
            >{{ item.title }}</RouterLink
          >
          <template v-else>{{ item.title }}</template>
        </template>
        <template #action>
          <ApButton
            size="compact"
            :variant="i === 0 && item.priority === 1 ? 'primary' : 'secondary'"
            :to="item.action.to"
            >{{ item.action.label }}</ApButton
          >
        </template>
      </ApListRow>
    </ul>
  </ApPanel>
</template>
