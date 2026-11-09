<script setup lang="ts">
import { RouterLink } from "vue-router";
import type { RemoteState } from "@/api/index.ts";
import { ApButton, ApCallout, ApListRow, ApPanel, ApRemote, formatRelative, useNow } from "@/ui";
import type { QueueItem } from "./queue.ts";

/** A2 · Action queue: the server-ranked queue (M6), in server order. */
defineProps<{ state: RemoteState<QueueItem[]>; nominal: number }>();
defineEmits<{ retry: [] }>();
const now = useNow();
/** Static meta, then the live countdown when the row has a consequence time. */
function metaProps(item: QueueItem): { meta: string; metaLive: boolean } | Record<string, never> {
  const due = item.due
    ? `${item.due.label} ${formatRelative(new Date(item.due.at), now.value)}`
    : null;
  const meta = [item.meta, due].filter((p): p is string => p !== null).join(" · ");
  return meta ? { meta, metaLive: due !== null } : {};
}
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
            v-bind="metaProps(item)"
          >
            <template #title>
              <RouterLink
                v-if="item.titleTo"
                :to="item.titleTo"
                class="max-md:hit-44 text-readout no-underline hover:text-bright hover:underline"
                >{{ item.title }}</RouterLink
              >
              <template v-else>{{ item.title }}</template>
            </template>
            <template #action>
              <ApButton
                size="compact"
                :variant="
                  i === 0 && item.priority === 1 && !item.acknowledged ? 'primary' : 'secondary'
                "
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
