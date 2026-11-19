<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApPanel, ApTable, ApTag, plural, type ApColumn } from "@/ui";
import { ACTIVATIONS_LIVE, fetchActivations, mayDecide, requestedLine, stateTag } from "./api.ts";

/** Setup › Changes · Waiting for activation (L10): app saves a second person approves. */
const props = defineProps<{ missionId: MissionId }>();
const key = computed(() => ({ missionId: props.missionId, state: "pending" as const }));
const list = useRemoteQuery(() => (ACTIVATIONS_LIVE ? key.value : null), fetchActivations);
useMissionInvalidation(
  computed(() => props.missionId),
  ["activations"],
  list.refetch,
);
const pending = computed(() =>
  list.state.value.status === "ready" ? list.state.value.value.requests : [],
);
const scope = useMissionScope();
const session = useSession();
const viewer = computed(() => ({
  userId: session.user.id,
  orgAdmin: canAdministerOrganization(session, scope.value.organization),
}));
const columns: readonly ApColumn[] = [
  { key: "what", label: "Activation" },
  { key: "who", label: "Requested" },
  { key: "state", label: "State" },
];
</script>

<template>
  <ApPanel
    v-if="pending.length > 0"
    index="A0"
    title="Waiting for activation"
    :meta="plural(pending.length, 'request')"
    flush
  >
    <ApTable
      :columns="columns"
      :rows="pending"
      :row-key="(r) => r.id"
      caption="Waiting for activation"
    >
      <template #cell-what="{ row }">
        <RouterLink
          :to="{ name: 'setup.activation', params: { requestId: row.id } }"
          class="font-semibold text-primary no-underline hover:underline max-md:hit-44"
          >{{ row.app?.name ?? "App" }}</RouterLink
        >
        <span class="text-text-2"> · {{ row.summary }}</span>
      </template>
      <template #cell-who="{ row }"
        ><span class="font-mono text-sm">{{ requestedLine(row) }}</span></template
      >
      <template #cell-state="{ row }"
        ><ApTag
          :state="stateTag(row).state"
          :label="mayDecide(row, viewer) ? 'AWAITS YOU' : stateTag(row).label"
      /></template>
    </ApTable>
  </ApPanel>
</template>
