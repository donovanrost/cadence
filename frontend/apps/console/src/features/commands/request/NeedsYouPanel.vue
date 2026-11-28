<script setup lang="ts">
import type { RouteLocationRaw } from "vue-router";
import { computed, toRef } from "vue";
import { describeApiError, type MissionId } from "@/api/index.ts";
import { ApButton, ApCallout, ApListRow, ApPanel, ApRemote, formatCount } from "@/ui";
import { needsYouCards } from "../groups/needsYou.ts";
import { NEEDS_YOU } from "../groups/words.ts";
import { useGroupTargets } from "./useGroupPages.ts";
import { expiryCounts, expirySummary } from "../groups/expiry.ts";
import type { VerifierSeries } from "../groups/series.ts";
import type { Group, GroupTarget } from "../groups/show.ts";

/**
 * N · Needs you (CommandFlow C3): one card per target a human has to look at, with what happened
 * in a sentence. No automatic retry (DECISIONS #69): `Re-send` opens Compose cloned from this group,
 * narrowed to those targets, through the normal GO. A released request with nothing to do says so.
 */
const props = defineProps<{
  group: Group;
  series: VerifierSeries | null;
  missionId: MissionId;
}>();
defineEmits<{ history: [target: GroupTarget] }>();
/** #795: the server keeps exactly Needs you's targets (failed, unclear, or held), a page at a time. */
const pages = useGroupTargets(
  toRef(props, "missionId"),
  toRef(props, "group"),
  computed(() => ({ needsYou: true })),
);
const loaded = computed(() =>
  pages.state.value.status === "ready" ? pages.state.value.value : null,
);
const cards = computed(() => needsYouCards(props.group, loaded.value?.items ?? [], props.series));
const total = computed(() => loaded.value?.meta.total ?? 0);
/** Failed or unclear targets by the group's own counts, so the panel shows while it loads. */
const expected = computed(() => NEEDS_YOU.some((s) => (props.group.progress[s] ?? 0) > 0));
const resendable = computed(() => cards.value.filter((c) => c.resend));
/** ux U75: one card per request when it expired part-way (none sent: no card). */
const expired = computed(() =>
  expiryCounts(props.group).sent > 0 ? expirySummary(props.group) : null,
);
const editAndResend: RouteLocationRaw = {
  name: "ops.commands.new",
  query: { from: `group:${props.group.id}` },
};
const resend = (ids: readonly string[]): RouteLocationRaw => ({
  name: "ops.commands.new",
  query: { from: `group:${props.group.id}`, only: ids.join(",") },
});
</script>

<template>
  <ApPanel
    v-if="expected || cards.length || expired || pages.state.value.status === 'failed'"
    index="N"
    title="Needs you"
    :meta="total ? `${formatCount(total)} ${total === 1 ? 'target' : 'targets'}` : 'request'"
    flush
  >
    <template v-if="resendable.length > 1" #meta>
      <ApButton
        size="compact"
        variant="secondary"
        :to="resend(resendable.map((c) => c.target.spacecraft_id))"
        >{{
          loaded?.next === null
            ? `Re-send to all ${resendable.length}`
            : `Re-send to the ${resendable.length} shown`
        }}</ApButton
      >
    </template>
    <ApRemote
      :state="pages.state.value"
      loading-label="Loading what needs you…"
      @retry="pages.refetch"
    >
      <template #default="{ value: page }">
        <p
          v-if="pages.refreshError.value"
          role="status"
          class="m-0 px-4 py-2 text-sm text-caution-text"
        >
          Couldn't refresh this list: {{ describeApiError(pages.refreshError.value) }}. Showing what
          was read before.
        </p>
        <ul class="m-0 list-none p-0">
          <ApListRow v-if="expired" state="off" title="Request expired" :sentence="expired">
            <template #action>
              <ApButton size="compact" variant="secondary" :to="editAndResend"
                >Edit and resend</ApButton
              >
            </template>
          </ApListRow>
          <ApListRow
            v-for="c in cards"
            :key="c.target.spacecraft_id"
            :state="c.state"
            :title="c.target.name ?? 'Unknown spacecraft'"
            :meta="c.tag"
            :sentence="c.explanation"
          >
            <template #action>
              <span class="flex gap-1">
                <ApButton
                  v-if="c.resend"
                  size="compact"
                  variant="secondary"
                  :to="resend([c.target.spacecraft_id])"
                  >Re-send</ApButton
                >
                <ApButton
                  size="compact"
                  variant="ghost"
                  aria-haspopup="dialog"
                  :aria-label="`History of ${c.target.name ?? 'this target'}`"
                  @click="$emit('history', c.target)"
                  >History</ApButton
                >
                <ApButton
                  v-if="c.target.scid !== null"
                  size="compact"
                  variant="ghost"
                  :to="{
                    name: 'ops.spacecraft',
                    params: { scId: c.target.scid, tab: 'investigate' },
                  }"
                  >Open</ApButton
                >
              </span>
            </template>
          </ApListRow>
        </ul>
        <div
          v-if="page.next !== null || pages.moreError.value"
          class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-2.5 text-sm text-text-3"
        >
          <span>{{ formatCount(page.items.length) }} of {{ formatCount(total) }} shown</span>
          <ApButton
            size="compact"
            :disabled="pages.moreBusy.value || page.next === null"
            :disabled-reason="pages.moreBusy.value ? 'Loading…' : 'Every target is shown'"
            @click="pages.more"
            >Load more</ApButton
          >
          <!-- It answers the person's own click: an alert, always mounted (a11y B6). -->
          <span role="alert" class="text-caution-text">{{
            pages.moreError.value
              ? `Couldn't load more: ${describeApiError(pages.moreError.value)}`
              : ""
          }}</span>
        </div>
      </template>
    </ApRemote>
  </ApPanel>
  <ApCallout v-else-if="group.state === 'queued' && loaded" tone="nominal"
    >Nothing needs you.</ApCallout
  >
</template>
