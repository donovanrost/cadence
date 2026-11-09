<script setup lang="ts">
import { RouterLink } from "vue-router";
import type { RemoteState } from "@/api/index.ts";
import { ApButton, ApCallout, ApListRow, ApPanel, ApRemote } from "@/ui";
import type { QueueItem } from "./queue.ts";

/** A2 · Action queue: the server-ranked queue (M6), in server order. */
defineProps<{ state: RemoteState<QueueItem[]>; nominal: number }>();
defineEmits<{ retry: [] }>();
</script>

<template>
  <ApPanel
    index="A2"
    title="Action queue"
    :meta="state.status === 'ready' ? `${state.value.length} open · sorted by urgency` : undefined"
    pane
    flush
  >
    <ApRemote :state="state" loading-label="LOADING QUEUE…" @retry="$emit('retry')">
      <template #default="{ value: items }">
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
      </template>
    </ApRemote>
  </ApPanel>
</template>
