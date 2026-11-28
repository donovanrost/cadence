<script setup lang="ts">
import { computed, ref } from "vue";
import { describeApiError, usePagedQuery } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { useSession } from "@/shell/index.ts";
import { refreshUnreadNotices } from "@/shell/unread-notices.ts";
import { ApButton, ApPanel, ApRemote, formatCount, plural } from "@/ui";
import NoticeRow from "./NoticeRow.vue";
import { fetchNoticesPage, markNoticeRead } from "./notices.ts";

/**
 * #709: my notices (the legacy bell's; today "added to an organization"), newest first, a page at
 * a time. Loading, failure and retry show; the panel is hidden only when the first page is empty.
 * Mark read is each unread row's one action, then the list and the menu's count re-read.
 */
const session = useSession();
const list = usePagedQuery(
  () => true as const,
  fetchNoticesPage,
  (n) => n.id,
);
const hidden = computed(
  () => list.state.value.status === "ready" && list.state.value.value.items.length === 0,
);
const unread = computed(() =>
  list.state.value.status === "ready"
    ? list.state.value.value.items.filter((n) => n.read_at === null).length
    : 0,
);
const busy = ref<string | null>(null);
const failure = ref<string | null>(null);

async function markRead(id: string) {
  busy.value = id;
  failure.value = null;
  try {
    const r = await markNoticeRead(id);
    if (!r.ok)
      failure.value = `Couldn't mark it read. ${failureOutcome(r.error, "changed").sentence}`;
    list.refetch();
    void refreshUnreadNotices();
  } finally {
    busy.value = null;
  }
}
</script>

<template>
  <ApPanel
    v-if="!hidden"
    id="notices"
    index="A0B"
    title="Notices"
    :meta="unread > 0 ? `${plural(unread, 'unread')} shown` : undefined"
    flush
  >
    <ApRemote :state="list.state.value" loading-label="Loading your notices…" @retry="list.refetch">
      <template #default="{ value: page }">
        <!-- It answers the person's own click: an alert, always mounted (a11y B6). -->
        <p role="alert" class="m-0 px-4 text-sm text-caution-text" :class="failure ? 'pt-3' : ''">
          {{ failure ?? "" }}
        </p>
        <p
          v-if="list.refreshError.value"
          role="status"
          class="m-0 px-4 pt-3 text-sm text-caution-text"
        >
          Couldn't refresh the list: {{ describeApiError(list.refreshError.value) }}. Showing what
          was read before.
        </p>
        <ul class="m-0 list-none p-0">
          <NoticeRow
            v-for="n in page.items"
            :key="n.id"
            :notice="n"
            :organizations="session.organizations"
            :busy="busy !== null"
            @read="markRead(n.id)"
          />
        </ul>
        <div
          class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-2.5 text-sm text-text-3"
        >
          <span>{{ formatCount(page.items.length) }} shown</span>
          <ApButton
            size="compact"
            :disabled="list.moreBusy.value || page.next === null"
            :disabled-reason="list.moreBusy.value ? 'Loading…' : 'No more notices'"
            @click="list.more"
            >Load more</ApButton
          >
          <span role="alert" class="text-caution-text">{{
            list.moreError.value
              ? `Couldn't load more: ${describeApiError(list.moreError.value)}`
              : ""
          }}</span>
        </div>
      </template>
    </ApRemote>
  </ApPanel>
</template>
