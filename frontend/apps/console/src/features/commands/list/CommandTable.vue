<script setup lang="ts">
import { RouterLink } from "vue-router";
import { expiredRowLabel } from "../groups/expiryReader.ts";
import { formatRelative, plural, useNow, ApTable, ApTag, type ApColumn } from "@/ui";
import { groupBlockedLine, type StationLookup } from "@/features/contacts/readiness.ts";
import type { GroupRow } from "../groups/api.ts";
import { statusTag, type PersonName } from "../groups/words.ts";
import { priorityTag } from "../priority.ts";

/** Command requests. The Title cell links to the request (name-cell link); no row actions yet. */
defineProps<{ rows: readonly GroupRow[]; nameOf: PersonName; stations: StationLookup }>();
const now = useNow();
const columns: readonly ApColumn[] = [
  { key: "title", label: "Request" },
  { key: "scope", label: "Scope", mono: true },
  { key: "by", label: "Requested by" },
  { key: "at", label: "Requested", mono: true },
  { key: "state", label: "State" },
];
const view = (r: GroupRow) => (r.awaiting_me ? "review" : undefined);
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(row) => row.id" caption="Command requests">
    <template #cell-title="{ row }">
      <RouterLink
        :to="{ name: 'ops.commands.request', params: { requestId: row.id, view: view(row) } }"
        class="max-md:hit-44 text-readout no-underline hover:text-bright hover:underline"
        >{{ row.title }}</RouterLink
      >
      <ApTag v-if="row.second_go_required" class="ml-2" label="2-PERSON" />
      <ApTag
        v-if="priorityTag(row.priority)"
        class="ml-2"
        :label="priorityTag(row.priority) ?? ''"
      />
      <!-- U33: rows carry no expiry, so the line names it only on the request page. -->
      <p
        v-if="groupBlockedLine(row.uplink, null, stations)"
        class="m-0 mt-1 max-w-[60ch] text-sm text-crit-text"
      >
        {{ groupBlockedLine(row.uplink, null, stations) }}
      </p>
    </template>
    <template #cell-scope="{ row }">
      <span class="whitespace-nowrap text-text-2"
        >{{ plural(row.target_count, "target") }} × {{ row.command_count }}</span
      >
    </template>
    <template #cell-by="{ row }">
      <span class="text-text-2">{{ nameOf(row.requested_by.user_id) }}</span>
    </template>
    <template #cell-at="{ row }">
      <time :datetime="row.requested_at" class="text-text-3">{{
        formatRelative(new Date(row.requested_at), now)
      }}</time>
    </template>
    <template #cell-state="{ row }">
      <ApTag v-if="row.awaiting_me" state="caution" label="Awaits your GO" /><ApTag
        v-else-if="row.expiry"
        state="off"
        :label="expiredRowLabel(row.expiry)"
      /><ApTag v-else v-bind="statusTag(row.state, row.progress, row.target_count)" />
    </template>
  </ApTable>
</template>
