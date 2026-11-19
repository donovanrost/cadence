<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApTable, ApTag, formatShort, type ApColumn } from "@/ui";
import { restrictionText, type AccountGrant } from "./grants.ts";

/** The account's grants: mission, restrictions, when, state, and Revoke… for active ones. */
const props = defineProps<{ grants: readonly AccountGrant[]; canManage: boolean }>();
const emit = defineEmits<{ revoke: [grant: AccountGrant] }>();
const columns = computed<readonly ApColumn[]>(() => [
  { key: "mission", label: "Mission" },
  { key: "limits", label: "Restrictions" },
  { key: "granted", label: "Granted", mono: true },
  { key: "state", label: "State" },
  ...(props.canManage ? [{ key: "act", label: "Action", hiddenLabel: true }] : []),
]);
</script>

<template>
  <ApTable :columns="columns" :rows="grants" :row-key="(g) => g.id" caption="Account grants">
    <template #cell-mission="{ row }">{{ row.mission.name }}</template>
    <template #cell-limits="{ row }"
      ><span class="text-text-2">{{ restrictionText(row) }}</span></template
    >
    <template #cell-granted="{ row }">{{ formatShort(new Date(row.granted_at)) }}</template>
    <template #cell-state="{ row }"
      ><ApTag
        :state="row.state === 'active' ? 'nominal' : 'off'"
        :label="row.state === 'active' ? 'ACTIVE' : 'REVOKED'"
    /></template>
    <template #cell-act="{ row }"
      ><ApButton
        v-if="row.state === 'active'"
        size="compact"
        variant="ghost"
        @click="emit('revoke', row)"
        >Revoke…</ApButton
      ></template
    >
  </ApTable>
</template>
