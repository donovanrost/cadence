<script setup lang="ts">
import { ApTable, type ApColumn } from "@/ui";
import { canApprove, canCommand, roleLabel, type Member } from "./api.ts";

/** U1: members. Presence columns are left out until the server reports presence (U10). */
defineProps<{ rows: readonly Member[] }>();
const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "role", label: "Role" },
  { key: "command", label: "Command", mono: true },
  { key: "go", label: "Second GO", mono: true },
];
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(m) => m.user_id" caption="People">
    <template #cell-name="{ row }">
      <span class="flex flex-col">
        <RouterLink
          :to="{ name: 'org.people.person', params: { userId: row.user_id } }"
          class="font-semibold text-readout hover:underline"
          >{{ row.display_name ?? row.email }}</RouterLink
        >
        <span class="font-mono text-xs text-text-4">{{ row.email }}</span>
      </span>
    </template>
    <template #cell-role="{ row }">{{ roleLabel(row.role) }}</template>
    <template #cell-command="{ row }">
      <span :class="canCommand(row) ? 'text-readout' : 'text-text-4'">{{
        canCommand(row) ? "YES" : "NO"
      }}</span>
    </template>
    <template #cell-go="{ row }">
      <span :class="canApprove(row) ? 'text-readout' : 'text-text-4'">{{
        canApprove(row) ? "YES" : "NO"
      }}</span>
    </template>
  </ApTable>
</template>
