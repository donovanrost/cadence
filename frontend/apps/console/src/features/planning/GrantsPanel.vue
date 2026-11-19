<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { ApButton, ApEmptyState, ApPanel, ApRemote, ApTable, ApTag, type ApColumn } from "@/ui";
import GrantRevoke from "./GrantRevoke.vue";
import GrantSheet from "./GrantSheet.vue";
import {
  canText,
  fetchGrants,
  grantTag,
  identityName,
  limitsText,
  untilText,
  type Grant,
} from "./grants.ts";

/** Policy › Grants (L3): what lets a service identity act without a person. */
const props = defineProps<{ missionId: MissionId }>();
const grants = useRemoteQuery(() => props.missionId, fetchGrants);
const ready = computed(() =>
  grants.state.value.status === "ready" ? grants.state.value.value : null,
);
const canManage = computed(() => ready.value?.permissions.includes("grants.manage") ?? false);
const columns = computed<readonly ApColumn[]>(() => [
  { key: "who", label: "Service identity" },
  { key: "can", label: "Can" },
  { key: "limits", label: "Limits", mono: true },
  { key: "until", label: "Valid until", mono: true },
  { key: "state", label: "State" },
  ...(canManage.value ? [{ key: "act", label: "Action", hiddenLabel: true }] : []),
]);
const sheet = ref<InstanceType<typeof GrantSheet> | null>(null);
const revoke = ref<InstanceType<typeof GrantRevoke> | null>(null);
</script>

<template>
  <ApPanel index="G1" title="Grants" flush>
    <template v-if="canManage" #header>
      <ApButton size="compact" variant="primary" @click="sheet?.open()">Grant automation…</ApButton>
    </template>
    <ApRemote :state="grants.state.value" loading-label="Loading grants…" @retry="grants.refetch">
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.grants.length === 0"
          state="off"
          headline="No grants"
          sentence="Without a grant, a person submits every plan Cadence drafts."
        />
        <ApTable
          v-else
          :columns="columns"
          :rows="value.grants"
          :row-key="(g: Grant) => g.id"
          caption="Automation grants"
        >
          <template #cell-who="{ row }">{{ identityName(row) }}</template>
          <template #cell-can="{ row }">{{ canText(row) }}</template>
          <template #cell-limits="{ row }">{{ limitsText(row) }}</template>
          <template #cell-until="{ row }">{{ untilText(row) }}</template>
          <template #cell-state="{ row }"
            ><ApTag :state="grantTag(row).state" :label="grantTag(row).label"
          /></template>
          <template #cell-act="{ row }"
            ><ApButton
              v-if="row.state === 'active'"
              size="compact"
              variant="ghost"
              @click="revoke?.open(row)"
              >Revoke…</ApButton
            ></template
          >
        </ApTable>
        <p v-if="!canManage" class="m-0 px-4 py-3 text-sm text-text-3">
          Org admins grant automation.
        </p>
        <GrantSheet ref="sheet" :mission-id="missionId" :grants="value" @granted="grants.refetch" />
      </template>
    </ApRemote>
    <GrantRevoke ref="revoke" :mission-id="missionId" @revoked="grants.refetch" />
  </ApPanel>
</template>
