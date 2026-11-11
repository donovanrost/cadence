<script setup lang="ts">
import { computed, ref } from "vue";
import { RouterLink } from "vue-router";
import type { RemoteState } from "@/api/index.ts";
import { ApButton, ApCallout, ApListRow, ApPanel, ApRemote, formatRelative, useNow } from "@/ui";
import type { QueueItem } from "./queue.ts";
import QueueListSheet from "./QueueListSheet.vue";
import { useQueueCommand } from "./useQueueCommand.ts";
import { useMissionScope } from "@/shell/index.ts";
import { useCommandAccess } from "@/features/commands/index.ts";

/** A2 · Action queue: the server-ranked queue (M6), in server order. */
defineProps<{ state: RemoteState<QueueItem[]>; nominal: number }>();
const emit = defineEmits<{ retry: []; changed: [] }>();
const now = useNow();
const sheet = ref<InstanceType<typeof QueueListSheet> | null>(null);
/** U37 Retry storing: operate_mission, the same flag Recover uses (access.abort). */
const scope = useMissionScope();
const access = useCommandAccess();
const command = useQueueCommand(
  computed(() => scope.value.mission.id),
  () => emit("changed"),
);
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
            :sentence="command.sentenceFor(item, access.abort)"
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
              <!-- U37: a write (Retry storing / Retry all N) where the operator may run it. -->
              <ApButton
                v-if="item.command && access.abort"
                size="compact"
                variant="secondary"
                :disabled="command.notes.value[item.key]?.running"
                @click="command.run(item)"
                >{{ item.command.label }}</ApButton
              >
              <!-- A folded row (U37) opens its members in a sheet instead of routing. -->
              <ApButton
                v-else-if="item.list"
                size="compact"
                variant="secondary"
                @click="sheet?.open(item)"
                >{{ item.action.label }}</ApButton
              >
              <ApButton
                v-else
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
    <QueueListSheet ref="sheet" />
  </ApPanel>
</template>
