<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApKeyValue, ApPageHeader, ApPanel, ApRemote, type ApCrumb } from "@/ui";
import { fetchModelRevision, type ModelRevision } from "./api.ts";
import ApprovalPanel from "./ApprovalPanel.vue";

/**
 * ux U65: a catalog revision's approval. Visible text says "catalog rev 4"; the compiled mission
 * model revision behind it is only in Technical details. Route by model revision id (api's wire).
 */
const props = defineProps<{ revisionId: string }>();
const scope = useMissionScope();
const key = computed(() => ({ missionId: scope.value.mission.id, revisionId: props.revisionId }));
const page = useRemoteQuery(key, fetchModelRevision);

const title = (r: ModelRevision) =>
  r.catalog_revision ? `Catalog rev ${r.catalog_revision.number}` : "Catalog revision";
function crumbs(r: ModelRevision): readonly ApCrumb[] {
  const database: ApCrumb | null = r.catalog_revision
    ? {
        label: "Database",
        to: {
          name: "setup.catalog.database",
          params: { databaseId: r.catalog_revision.database_id },
        },
      }
    : null;
  return [
    { label: "Catalog", to: { name: "setup.catalog" } },
    ...(database ? [database] : []),
    { label: title(r) },
  ];
}
/** Nothing to approve and nothing decided (e.g. retired): no panel (ux). */
const hasApproval = (r: ModelRevision) => r.decision !== null || r.status === "candidate";
const details = (r: ModelRevision) => [
  { key: "model", label: "Mission model revision", value: r.id, mono: true },
  {
    key: "catalog",
    label: "Catalog revision",
    value: r.catalog_revision?.id ?? "None",
    mono: true,
  },
  {
    key: "report",
    label: "Comparison report",
    value: r.comparison?.report_id ?? "None",
    mono: true,
  },
  {
    key: "targets",
    label: "Changed runtime targets",
    value: r.comparison?.changed_targets.join(", ") || "None",
    mono: true,
  },
];
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1000px] flex-col gap-4">
    <ApRemote :state="page.state.value" loading-label="Loading revision…" @retry="page.refetch">
      <template #default="{ value }">
        <ApBreadcrumb :crumbs="crumbs(value)" />
        <ApPageHeader
          :label="`${scope.mission.name} · catalog · revision`"
          :title="title(value)"
          size="reading"
        >
          <template v-if="value.catalog_revision?.label" #subtitle
            ><span class="text-sm text-text-2">{{ value.catalog_revision.label }}</span></template
          >
        </ApPageHeader>
        <ApprovalPanel
          v-if="hasApproval(value)"
          :revision="value"
          :model-key="key"
          @changed="page.refetch"
        />
        <ApPanel index="F3" title="Technical details">
          <ApKeyValue :items="details(value)" :columns="2" />
        </ApPanel>
      </template>
    </ApRemote>
  </div>
</template>
