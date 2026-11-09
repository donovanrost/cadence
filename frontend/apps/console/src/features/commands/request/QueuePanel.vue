<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { formatRelative, plural, useNow, ApEmptyState, ApListRow, ApPanel } from "@/ui";
import type { GroupRow } from "../groups/api.ts";
import type { PersonName } from "../groups/words.ts";

/**
 * Q · Waiting on you (CommandFlow C2): requests you can give the GO, oldest first; your own pending
 * requests follow as notes you can open but not approve.
 */
const props = defineProps<{
  rows: readonly GroupRow[];
  currentId: string;
  viewerId: string;
  nameOf: PersonName;
}>();
const now = useNow();
const oldestFirst = (a: GroupRow, b: GroupRow) =>
  Date.parse(a.requested_at) - Date.parse(b.requested_at);
const mine = computed(() =>
  props.rows.filter((r) => r.requested_by.user_id === props.viewerId).sort(oldestFirst),
);
const waiting = computed(() => props.rows.filter((r) => r.awaiting_me).sort(oldestFirst));
const meta = (r: GroupRow) =>
  `${props.nameOf(r.requested_by.user_id)} · ${formatRelative(new Date(r.requested_at), now.value)}`;
const scopeLine = (r: GroupRow) =>
  `${plural(r.target_count, "target")} × ${plural(r.command_count, "command")}`;
</script>

<template>
  <ApPanel index="Q" title="Waiting on you" :meta="String(waiting.length)" pane flush>
    <ApEmptyState v-if="waiting.length === 0 && mine.length === 0" headline="Nothing waiting" />
    <ul class="m-0 list-none p-0">
      <ApListRow
        v-for="r in waiting"
        :key="r.id"
        :state="r.id === currentId ? 'live' : undefined"
        :sentence="scopeLine(r)"
        :meta="meta(r)"
      >
        <template #title>
          <RouterLink
            :to="{ name: 'ops.commands.request', params: { requestId: r.id, view: 'review' } }"
            class="text-readout hover:underline"
            :aria-current="r.id === currentId ? 'page' : undefined"
            >{{ r.title }}</RouterLink
          >
        </template>
      </ApListRow>
      <ApListRow
        v-for="r in mine"
        :key="r.id"
        sentence="Yours: someone else gives the GO."
        :meta="meta(r)"
      >
        <template #title>
          <RouterLink
            :to="{ name: 'ops.commands.request', params: { requestId: r.id } }"
            class="text-text-2 hover:underline"
            >{{ r.title }}</RouterLink
          >
        </template>
      </ApListRow>
    </ul>
  </ApPanel>
</template>
