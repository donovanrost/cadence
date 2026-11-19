<script setup lang="ts">
import { computed, nextTick, ref } from "vue";
import { RouterLink } from "vue-router";
import type { RemoteState, Unshown } from "@/api/index.ts";
import { ApButton, ApCallout, ApListRow, ApPanel, ApRemote, formatRelative, useNow } from "@/ui";
import type { QueueItem } from "./queue.ts";
import type { Attention } from "./attention.ts";
import DiscardSheet from "./DiscardSheet.vue";
import JobSheets from "./JobSheets.vue";
import StuckSheet from "./StuckSheet.vue";
import UnshownCallout from "./UnshownCallout.vue";
import { stuckAction } from "./stuckRow.ts";
import QueueListSheet from "./QueueListSheet.vue";
import QueueReveal from "./QueueReveal.vue";
import { QUEUE_CAP } from "./queueCap.ts";
import { useFreshFlash } from "./useFreshFlash.ts";
import { jobOffers } from "./jobs.ts";
import { useQueueCommand, type RetryOutcome } from "./useQueueCommand.ts";
import { landFocus } from "./landFocus.ts";
import { useMissionScope } from "@/shell/index.ts";
import { useCommandAccess } from "@/features/commands/index.ts";

/** A2 · Action queue: the server-ranked queue (M6), in server order. */
const props = defineProps<{
  state: RemoteState<QueueItem[]>;
  nominal: number;
  /** U86: items this console couldn't read; the total counts them, the rows can't. */
  unshown: readonly Unshown[];
}>();
const emit = defineEmits<{ retry: []; retried: [row: QueueItem, outcome: RetryOutcome] }>();
const now = useNow();
const sheet = ref<InstanceType<typeof QueueListSheet> | null>(null);
const discardSheet = ref<InstanceType<typeof DiscardSheet> | null>(null);
/** U49: the discarded item comes back resolved; the row takes it as a Retry's does. */
/** A write answered: the screen patches the row; focus lands on its resolved line (a11y C). */
function retried(row: QueueItem, outcome: RetryOutcome) {
  emit("retried", row, outcome);
  void landFocus(list.value, row.key);
}
function discarded(row: QueueItem, item: Attention | null) {
  retried(row, { text: null, items: item ? [item] : [], emptied: false, failed: false });
}
let discarding: QueueItem | null = null;
/** U54: Retry… / Close without retry… open their sheets; the returned item patches the row. */
const jobSheets = ref<InstanceType<typeof JobSheets> | null>(null);
let deciding: QueueItem | null = null;
function openJob(row: QueueItem, kind: "retry" | "close") {
  if (!row.job) return;
  deciding = row;
  if (kind === "retry") jobSheets.value?.openRetry(row.job);
  else jobSheets.value?.openClose(row.job);
}
/** U84: Acknowledge… / Details open the Stuck processing sheet; its ack patches the row. */
const stuckSheet = ref<InstanceType<typeof StuckSheet> | null>(null);
let acking: QueueItem | null = null;
function openStuck(row: QueueItem) {
  if (!row.stuck) return;
  acking = row;
  stuckSheet.value?.open(row.stuck);
}
function openDiscard(row: QueueItem) {
  if (!row.discard) return;
  discarding = row;
  discardSheet.value?.open(row.discard);
}
/** U37 Retry storing: operate_mission, the same flag Recover uses (access.abort). */
const scope = useMissionScope();
const access = useCommandAccess();
const command = useQueueCommand(
  computed(() => scope.value.mission.id),
  (row, outcome) => retried(row, outcome),
);
/**
 * A newly arrived crit P1 flashes once (design-language §6): the wash comes on at once and fades
 * out (≤600 ms in all); reduced motion gets a 2 s `raised` wash and no fade.
 */
const flash = useFreshFlash(
  computed(() => (props.state.status === "ready" ? props.state.value : null)),
);
const flashClass = (key: string) =>
  flash.flashing.value.has(key)
    ? flash.reduced
      ? "bg-raised"
      : "bg-[var(--apogee-wash-crit)]"
    : "transition-colors duration-[450ms] motion-reduce:transition-none";
/** Now.md A2 'Over 100 open': the first QUEUE_CAP rows until the operator shows the rest. */
const revealed = ref(false);
const shownOf = (items: readonly QueueItem[]) =>
  revealed.value ? items : items.slice(0, QUEUE_CAP);
const list = ref<HTMLElement | null>(null);
/** Scroll stays put; focus goes to the first newly shown row's first control. */
async function reveal() {
  revealed.value = true;
  await nextTick();
  const row = list.value?.children.item(QUEUE_CAP);
  row?.querySelector<HTMLElement>("a, button")?.focus({ preventScroll: true });
}
/** Static meta, then the live countdown when the row has a consequence time. */
function metaProps(item: QueueItem): { meta: string; metaLive: boolean } | Record<string, never> {
  const due = item.due
    ? `${item.due.label ? `${item.due.label} ` : ""}${formatRelative(new Date(item.due.at), now.value)}`
    : null;
  const meta = [item.meta, due].filter((p): p is string => p !== null).join(" · ");
  return meta ? { meta, metaLive: due !== null } : {};
}
</script>

<template>
  <ApPanel
    index="A2"
    title="Action queue"
    :meta="
      state.status === 'ready'
        ? `${state.value.length + unshown.length} open · sorted by urgency`
        : undefined
    "
    pane
    flush
  >
    <!-- a11y B6 (#243): a row command's outcome, announced without moving focus (always present). -->
    <p class="sr-only" role="status">{{ command.said.value.status }}</p>
    <p class="sr-only" role="alert">{{ command.said.value.alert }}</p>
    <ApRemote :state="state" loading-label="LOADING QUEUE…" @retry="$emit('retry')">
      <template #default="{ value: items }">
        <UnshownCallout :unshown="unshown" />
        <ApCallout v-if="items.length === 0 && unshown.length === 0" tone="nominal">
          Nothing needs you. {{ nominal }} spacecraft fresh and in limits.
        </ApCallout>
        <ul v-else-if="items.length > 0" ref="list" class="m-0 list-none p-0">
          <ApListRow
            v-for="(item, i) in shownOf(items)"
            :key="item.key"
            :data-key="item.key"
            :class="flashClass(item.key)"
            :priority="`P${item.priority}`"
            :state="item.state"
            :sentence="command.sentenceFor(item, access.abort)"
            v-bind="metaProps(item)"
          >
            <!-- U66: a sentence with links (the buffer disk's holders). -->
            <template v-if="item.sentenceParts" #sentence>
              <template v-for="(part, n) in item.sentenceParts" :key="n">
                <template v-if="typeof part === 'string'">{{ part }}</template>
                <RouterLink
                  v-else-if="'to' in part"
                  :to="part.to"
                  class="text-readout underline hover:text-bright"
                  >{{ part.text }}</RouterLink
                >
                <span v-else class="whitespace-nowrap">{{ part.text }}</span>
              </template>
            </template>
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
              <!-- U84: one sheet behind Acknowledge… (operators, while open) or Details. -->
              <ApButton
                v-if="item.stuck"
                size="compact"
                :variant="stuckAction(item.stuck, access.abort).primary ? 'primary' : 'secondary'"
                @click="openStuck(item)"
                >{{ stuckAction(item.stuck, access.abort).label }}</ApButton
              >
              <!-- U37: a write (Retry storing / Retry all N) where the operator may run it. -->
              <ApButton
                v-else-if="item.command && access.abort"
                size="compact"
                variant="secondary"
                :disabled="command.running.value.has(item.key)"
                @click="command.run(item)"
                >{{ item.command.label }}</ApButton
              >
              <!-- A folded row (U37) opens its members in a sheet instead of routing. -->
              <!-- U54: both slots go to the job's two decisions (operators only). -->
              <template v-else-if="item.job && access.abort">
                <ApButton
                  v-if="jobOffers(item.job, 'retry')"
                  size="compact"
                  variant="secondary"
                  @click="openJob(item, 'retry')"
                  >Retry…</ApButton
                >
                <ApButton
                  v-if="jobOffers(item.job, 'close')"
                  size="compact"
                  variant="secondary"
                  @click="openJob(item, 'close')"
                  >Close without retry…</ApButton
                >
              </template>
              <ApButton
                v-else-if="item.list"
                size="compact"
                variant="secondary"
                @click="sheet?.open(item)"
                >{{ item.action.label }}</ApButton
              >
              <ApButton
                v-else-if="!item.noAction"
                size="compact"
                :variant="
                  item.primary || (i === 0 && item.priority === 1 && !item.acknowledged)
                    ? 'primary'
                    : 'secondary'
                "
                :to="item.action.to"
                >{{ item.action.label }}</ApButton
              >
              <!-- U49: Discard… sits beside Retry and opens its sheet (danger, reason required). -->
              <ApButton
                v-if="item.discard && access.abort"
                size="compact"
                variant="danger"
                :disabled="command.running.value.has(item.key)"
                @click="openDiscard(item)"
                >Discard…</ApButton
              >
            </template>
          </ApListRow>
          <QueueReveal v-if="!revealed" :items="items" @reveal="reveal" />
        </ul>
      </template>
    </ApRemote>
    <QueueListSheet ref="sheet" />
    <JobSheets
      ref="jobSheets"
      :mission-id="scope.mission.id"
      @done="(item) => deciding && discarded(deciding, item)"
    />
    <StuckSheet
      ref="stuckSheet"
      :mission-id="scope.mission.id"
      :can-ack="access.abort"
      @done="(item) => acking && discarded(acking, item)"
    />
    <DiscardSheet
      ref="discardSheet"
      :mission-id="scope.mission.id"
      @done="(item) => discarding && discarded(discarding, item)"
    />
  </ApPanel>
</template>
