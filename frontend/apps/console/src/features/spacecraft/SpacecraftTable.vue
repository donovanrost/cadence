<script setup lang="ts">
import { formatShort } from "@/lib/index.ts";
import { ApStatusMark, ApTable, type ApColumn } from "@/ui/index.ts";
import type { SpacecraftRow } from "./api.ts";

/** Directory rows. The Name cell is the row link (setup spacecraft detail). */
defineProps<{ rows: readonly SpacecraftRow[] }>();

const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "scid", label: "SCID", mono: true, align: "end" },
  { key: "profile", label: "Profile" },
  { key: "orbit", label: "Plane · slot", mono: true },
  { key: "heard", label: "Last heard", mono: true },
];

const orbit = (row: SpacecraftRow) =>
  row.plane === null
    ? "—"
    : `P${String(row.plane).padStart(2, "0")}${row.slot === null ? "" : ` · ${String(row.slot).padStart(2, "0")}`}`;
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(row) => row.id" caption="Spacecraft">
    <template #cell-name="{ row }">
      <RouterLink
        :to="{ name: 'setup.spacecraft.one', params: { scId: row.id } }"
        class="text-readout no-underline hover:text-bright hover:underline"
        >{{ row.name }}</RouterLink
      >
    </template>
    <template #cell-scid="{ row }">
      <span v-if="row.scid !== null">{{ row.scid }}</span>
      <span v-else class="text-caution-text">not set</span>
    </template>
    <template #cell-profile="{ row }">
      <span v-if="row.profile" class="text-text-2"
        >{{ row.profile.name ?? "Deleted profile"
        }}<span class="font-mono text-xs text-text-4"> v{{ row.profile.version }}</span></span
      >
      <span v-else class="text-caution-text">No profile</span>
    </template>
    <template #cell-orbit="{ row }">
      <span :class="row.plane === null ? 'text-text-4' : ''">{{ orbit(row) }}</span>
    </template>
    <template #cell-heard="{ row }">
      <time v-if="row.lastReceivedAt" :datetime="row.lastReceivedAt" class="text-text-3">{{
        formatShort(new Date(row.lastReceivedAt))
      }}</time>
      <span v-else class="inline-flex items-center gap-2 font-sans text-text-3"
        ><ApStatusMark state="off" />Awaiting first AOS</span
      >
    </template>
  </ApTable>
</template>
