<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useConsoleScope } from "@/shell";
import {
  ApCallout,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApSegmented,
  ApTable,
  ApTag,
  formatAbsolute,
  type ApColumn,
} from "@/ui";
import { fetchAudit, kindLabel, type AuditPage } from "./api.ts";

/** Organization › Audit log. Says which sources are missing until the read is unified (ux spec). */
const scope = useConsoleScope();
const organization = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const days = ref<"1" | "7" | "30">("7");
const query = computed(() =>
  organization.value
    ? { organizationId: organization.value.id, days: Number(days.value), kinds: [] }
    : null,
);
const { state, refetch } = useRemoteQuery(query, fetchAudit);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const columns: readonly ApColumn[] = [
  { key: "at", label: "Time", mono: true },
  { key: "actor", label: "Actor" },
  { key: "action", label: "Action" },
  { key: "mission", label: "Mission" },
  { key: "why", label: "Why" },
];
const missing = (p: AuditPage) =>
  p.sources.missing.map((k) => kindLabel[k].toLowerCase()).join(" and ");
const included = (p: AuditPage) =>
  p.sources.included.map((k) => kindLabel[k].toLowerCase()).join(", ");
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${organization?.name ?? ''} · audit log`"
      :title="days === '1' ? 'Last 24 hours' : `Last ${days} days`"
      size="reading"
    >
      <ApSegmented
        v-model="days"
        label="Range"
        :options="[
          { value: '1', label: '24h' },
          { value: '7', label: '7d' },
          { value: '30', label: '30d' },
        ]"
      />
    </ApPageHeader>
    <ApPanel v-if="notProvided" index="L1" title="Audit log" flush>
      <ApEmptyState
        state="off"
        headline="The audit log isn't available in the console yet"
        sentence="Configuration revisions are in Setup › Revisions in the meantime."
      />
    </ApPanel>
    <ApRemote v-else :state="state" loading-label="Loading audit log…" @retry="refetch">
      <template #default="{ value }">
        <ApCallout v-if="value.sources.missing.length > 0" tone="info">
          Showing {{ included(value) }} events. {{ missing(value) }} events aren't in the audit log
          yet.
        </ApCallout>
        <ApPanel index="L1" title="Audit" flush>
          <ApEmptyState
            v-if="value.events.length === 0"
            :headline="`No audited actions in the last ${days === '1' ? '24 hours' : `${days} days`}`"
          />
          <ApTable
            v-else
            :columns="columns"
            :rows="value.events"
            :row-key="(e) => e.id"
            caption="Audit log"
          >
            <template #cell-at="{ row }">{{ formatAbsolute(new Date(row.at)) }}</template>
            <template #cell-actor="{ row }">
              <span :class="row.actor.kind === 'service' ? 'font-mono' : ''">{{
                row.actor.name
              }}</span>
              <ApTag v-if="row.actor.kind === 'service'" class="ml-2" label="Service" />
            </template>
            <template #cell-action="{ row }"
              >{{ row.action
              }}<span v-if="row.target" class="text-text-3">
                · {{ row.target.label }}</span
              ></template
            >
            <template #cell-mission="{ row }">{{ row.mission?.name ?? "—" }}</template>
            <template #cell-why="{ row }"
              ><span class="text-text-3">{{ row.reason ?? "" }}</span></template
            >
          </ApTable>
        </ApPanel>
      </template>
    </ApRemote>
  </div>
</template>
