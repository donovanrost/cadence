<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { AuditTable, fetchAudit } from "@/features/audit/index.ts";
import { ApEmptyState, ApPanel, ApRemote } from "@/ui";

/** People.md person page · Activity: their last 10 audit events (AU1 `actor_id`), last 90 days. */
const props = defineProps<{ orgId: string; userId: string }>();
const to = new Date().toISOString();
const key = computed(() => ({
  organizationId: props.orgId,
  days: 90,
  kinds: [] as const,
  missionId: null,
  actorId: props.userId,
  to,
}));
const { state, refetch } = useRemoteQuery(key, fetchAudit);
</script>

<template>
  <ApPanel index="P2" title="Activity" meta="Last 10 · 90 days" flush>
    <ApRemote :state="state" loading-label="Loading activity…" @retry="refetch">
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.events.length === 0"
          state="off"
          headline="No activity in the last 90 days"
        />
        <AuditTable v-else :events="value.events.slice(0, 10)" />
      </template>
    </ApRemote>
  </ApPanel>
</template>
