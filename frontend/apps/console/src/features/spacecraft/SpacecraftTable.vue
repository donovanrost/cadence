<script setup lang="ts">
import { formatShort, ApStatusMark, ApTable, ApTag, type ApColumn } from "@/ui";
import type { SpacecraftRow } from "./api.ts";
import { orbitLabel } from "./format.ts";

/** Directory rows. The Name cell is the row link (setup spacecraft detail). */
/** `degraded`: the history store isn't answering, so a missing last-received isn't "never heard". */
defineProps<{ rows: readonly SpacecraftRow[]; degraded?: boolean }>();

const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "scid", label: "SCID", mono: true, align: "end" },
  { key: "norad", label: "NORAD", mono: true, align: "end" },
  { key: "profile", label: "Profile" },
  { key: "orbit", label: "Plane · slot", mono: true },
  { key: "routes", label: "Routing rules", mono: true, align: "end" },
  { key: "setup", label: "Setup" },
  { key: "heard", label: "Last heard", mono: true },
];
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(row) => row.id" caption="Spacecraft">
    <template #cell-name="{ row }">
      <RouterLink
        :to="{ name: 'setup.spacecraft.one', params: { spacecraftId: row.id } }"
        class="text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
        >{{ row.name }}</RouterLink
      >
    </template>
    <template #cell-scid="{ row }">
      <span v-if="row.scid !== null">{{ row.scid }}</span>
      <span v-else class="text-caution-text">not set</span>
    </template>
    <template #cell-norad="{ row }">
      <span v-if="row.noradId !== null">{{ row.noradId }}</span>
      <span v-else class="text-text-4">—</span>
    </template>
    <template #cell-routes="{ row }">
      <span v-if="row.routingRuleCount > 0">{{ row.routingRuleCount }}</span>
      <span v-else class="text-caution-text">none</span>
    </template>
    <template #cell-setup="{ row }">
      <span v-if="row.ready" class="inline-flex items-center gap-2 text-text-3"
        ><ApStatusMark state="nominal" />Ready</span
      >
      <ApTag v-else state="caution" label="Incomplete" />
    </template>
    <template #cell-profile="{ row }">
      <span v-if="row.profile" class="text-text-2"
        >{{ row.profile.name ?? "Deleted profile"
        }}<span class="font-mono text-xs text-text-4"> v{{ row.profile.version }}</span></span
      >
      <span v-else class="text-caution-text">No profile</span>
    </template>
    <template #cell-orbit="{ row }">
      <span :class="row.plane === null ? 'text-text-4' : ''">{{
        orbitLabel(row.plane, row.slot) ?? "—"
      }}</span>
    </template>
    <template #cell-heard="{ row }">
      <time v-if="row.lastReceivedAt" :datetime="row.lastReceivedAt" class="text-text-3">{{
        formatShort(new Date(row.lastReceivedAt))
      }}</time>
      <span v-else-if="degraded" class="font-sans text-text-3">Not known right now</span>
      <span v-else class="inline-flex items-center gap-2 font-sans text-text-3"
        ><ApStatusMark state="off" />Awaiting first AOS</span
      >
    </template>
  </ApTable>
</template>
