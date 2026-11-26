<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { useRemoteQuery } from "@/api";
import { ApButton, ApEmptyState, ApPanel, ApRemote, formatShort, refocusFirst } from "@/ui";
import { fetchActivity, type ActivityEvent, type SettingsKey } from "./api.ts";
import { activityText } from "./present.ts";

/** Activity (ux): save, restore, archive, share, export, with actor and time; newest first. */
const props = defineProps<{ settingsKey: SettingsKey }>();
const first = useRemoteQuery(() => ({ ...props.settingsKey, before: null }), fetchActivity);
const older = ref<readonly ActivityEvent[]>([]);
const cursor = ref<string | null>(null);
const loading = ref(false);
/** B6: a failed Older is said, in a line that's always there so the words are announced. */
const olderFailed = ref(false);
watch(first.state, (s) => {
  if (s.status !== "ready") return;
  older.value = [];
  cursor.value = s.value.next;
  olderFailed.value = false;
});
async function loadOlder() {
  if (!cursor.value || loading.value) return;
  loading.value = true;
  olderFailed.value = false;
  try {
    const r = await fetchActivity(
      { ...props.settingsKey, before: cursor.value },
      new AbortController().signal,
    );
    if (!r.ok) return void (olderFailed.value = true);
    const firstNew = r.value.events[0]?.id;
    older.value = [...older.value, ...r.value.events];
    cursor.value = r.value.next;
    // A5: the last page takes Older away; focus goes to the first event it loaded.
    await nextTick();
    if (firstNew)
      refocusFirst(document.querySelector<HTMLElement>(`[data-activity="${firstNew}"]`));
  } finally {
    loading.value = false;
  }
}
const all = (events: readonly ActivityEvent[]) => [...events, ...older.value];
const hasMore = computed(() => cursor.value !== null);
</script>

<template>
  <ApPanel index="S5" title="Activity" flush>
    <ApRemote :state="first.state.value" loading-label="Loading activity…" @retry="first.refetch">
      <template #default="{ value }">
        <ApEmptyState v-if="value.events.length === 0" headline="No activity yet" />
        <ol v-else class="m-0 list-none p-0">
          <li
            v-for="e in all(value.events)"
            :key="e.id"
            :data-activity="e.id"
            class="grid grid-cols-[120px_minmax(0,1fr)] gap-3 border-t border-hairline px-4 py-2.5 first:border-t-0"
          >
            <time :datetime="e.at" class="font-mono text-xs text-text-3">{{
              formatShort(new Date(e.at))
            }}</time>
            <span class="text-md text-readout"
              >{{ activityText(e)
              }}<span class="text-text-3"> · {{ e.actor?.name ?? "Not recorded" }}</span></span
            >
          </li>
        </ol>
        <div v-if="hasMore" class="border-t border-hairline px-4 py-2.5">
          <ApButton size="compact" :disabled="loading" disabled-reason="Loading…" @click="loadOlder"
            >Older</ApButton
          >
          <p role="alert" class="m-0 text-sm text-caution-text">
            {{ olderFailed ? "Couldn't load older activity. Try Older again." : "" }}
          </p>
        </div>
      </template>
    </ApRemote>
  </ApPanel>
</template>
