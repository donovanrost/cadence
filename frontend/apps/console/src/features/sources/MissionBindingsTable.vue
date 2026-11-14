<script setup lang="ts">
import { ApButton, ApTable, ApTag, type ApColumn } from "@/ui";
import type { MissionBinding } from "./bindings.ts";

/** D2's rows: logical source (PLATFORM tag when platform-wide) · reads from · status · actions. */
const props = defineProps<{
  rows: readonly MissionBinding[];
  canManage: boolean;
  platformAdmin: boolean;
}>();
defineEmits<{ switch: [binding: MissionBinding]; history: [binding: MissionBinding] }>();
const columns: readonly ApColumn[] = [
  { key: "logical", label: "Logical source", mono: true },
  { key: "reads", label: "Reads from" },
  { key: "status", label: "Status" },
  { key: "switch", label: "Switch", hiddenLabel: true },
  { key: "history", label: "History", hiddenLabel: true },
];
const STATUS: Readonly<Record<MissionBinding["status"], string>> = {
  active: "Active",
  disabled: "Disabled",
  superseded: "Superseded",
  unrecognized: "Unknown",
};
/** A mission's own binding: mission operators; a platform-wide one: platform admins in admin mode. */
const canSwitch = (b: MissionBinding) => (b.shared ? props.platformAdmin : props.canManage);
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(b) => b.id" caption="Bindings">
    <template #cell-logical="{ row }"
      ><span class="inline-flex items-center gap-2"
        >{{ row.logical_source }}<ApTag v-if="row.shared" state="neutral" label="PLATFORM"
      /></span>
    </template>
    <template #cell-reads="{ row }"
      ><RouterLink
        :to="{ name: 'setup.data-sources', params: { sourceId: row.data_source.id } }"
        class="text-readout hover:underline"
        >{{ row.data_source.display_name }}</RouterLink
      ></template
    >
    <template #cell-status="{ row }"
      ><span class="text-text-2">{{ STATUS[row.status] }}</span></template
    >
    <template #cell-switch="{ row }"
      ><ApButton v-if="canSwitch(row)" size="compact" variant="ghost" @click="$emit('switch', row)"
        >Switch…</ApButton
      ></template
    >
    <template #cell-history="{ row }"
      ><ApButton size="compact" variant="ghost" @click="$emit('history', row)"
        >History</ApButton
      ></template
    >
  </ApTable>
</template>
