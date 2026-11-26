<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { AuditTable, fetchAudit } from "@/features/audit/index.ts";
import { ApEmptyState, ApPanel, ApRemote } from "@/ui";

/** People.md person page · Activity: their last 10 audit events (AU1 `actor_id`), last 90 days. */
const props = defineProps<{ orgId: OrganizationId; userId: string; name: string }>();
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
  <ApPanel index="P2" title="Activity" flush>
    <template #meta>
      <span class="flex items-center gap-3">
        <span>Last 10 events in the past 90 days</span>
        <RouterLink
          :to="{ name: 'org.audit', query: { actor: userId, who: name } }"
          class="text-text-3 hover:text-readout"
          >Audit log</RouterLink
        >
      </span>
    </template>
    <ApRemote
      forbidden-text="Org admins see this."
      :state="state"
      loading-label="Loading activity…"
      @retry="refetch"
    >
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.events.length === 0"
          state="off"
          headline="No activity in the past 90 days."
        />
        <AuditTable v-else :events="value.events.slice(0, 10)" />
      </template>
    </ApRemote>
  </ApPanel>
</template>
