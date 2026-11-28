<script setup lang="ts">
import { computed } from "vue";
import { isKnown, useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApKeyValue, ApPageHeader, ApPanel, ApRemote, type ApCrumb } from "@/ui";
import { fetchCatalogIndex } from "../api.ts";
import { fetchModelRevision, type ModelRevision } from "./api.ts";
import ApprovalPanel from "./ApprovalPanel.vue";
import RevisionRollout from "./RevisionRollout.vue";
import ComposedHeader from "./ComposedHeader.vue";
import RevisionSpacecraftPanel from "./RevisionSpacecraftPanel.vue";
import { importerLine } from "./words.ts";
import { compositionTitle, isComposed } from "../composition.ts";

/**
 * ux U65: a catalog revision's approval. Visible text says "catalog rev 4"; the compiled mission
 * model revision behind it is only in Technical details. Route by model revision id (api's wire).
 */
const props = defineProps<{ revisionId: string }>();
const scope = useMissionScope();
const key = computed(() => ({ missionId: scope.value.mission.id, revisionId: props.revisionId }));
const page = useRemoteQuery(key, fetchModelRevision);
/** Catalog.md §D (#313): the crumb names the revision's database, once its name has loaded. */
const databaseId = computed(() =>
  page.state.value.status === "ready"
    ? (page.state.value.value.catalog_revision?.database_id ?? null)
    : null,
);
const index = useRemoteQuery(
  () =>
    databaseId.value ? { missionId: scope.value.mission.id, databaseId: databaseId.value } : null,
  fetchCatalogIndex,
);
const databaseName = computed(() =>
  index.state.value.status === "ready"
    ? (index.state.value.value.databases.find((d) => d.id === databaseId.value)?.name ?? null)
    : null,
);

// U109: a composed base is titled `Composition 3` ("Composition" with no number); one catalog as before.
const title = (r: ModelRevision) =>
  isComposed(r.composition)
    ? (compositionTitle(r.composition) ?? "Composition")
    : r.catalog_revision
      ? `Catalog rev ${r.catalog_revision.number}`
      : "Catalog revision";
function crumbs(r: ModelRevision): readonly ApCrumb[] {
  const database: ApCrumb | null =
    r.catalog_revision && databaseName.value
      ? {
          label: databaseName.value,
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
  // #392: the status as sent, so one the console doesn't know is still said somewhere.
  {
    key: "status",
    label: "Model revision status",
    value: isKnown(r.status) ? r.status : r.status.unrecognized,
    mono: true,
  },
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
        <ComposedHeader
          v-if="isComposed(value.composition)"
          :revision="value"
          :composition="value.composition"
        />
        <ApprovalPanel
          v-if="hasApproval(value)"
          :revision="value"
          :model-key="key"
          @changed="page.refetch"
        />
        <!-- U102 "Where": C3 under the Approval panel (or its decided line). -->
        <RevisionRollout :revision="value" />
        <!-- #678: where it came from, and which spacecraft use it (one catalog revision only). -->
        <ApPanel v-if="value.catalog_revision" index="F1" title="Source">
          <p class="m-0 text-md text-text-2">
            {{ importerLine(value) ?? "Importer not recorded." }}
            <RouterLink
              v-if="value.catalog_revision.import_run_id"
              :to="{
                name: 'setup.catalog.import',
                params: { importId: value.catalog_revision.import_run_id },
              }"
              class="text-readout underline"
              >Open its import run</RouterLink
            >
          </p>
        </ApPanel>
        <RevisionSpacecraftPanel
          v-if="value.catalog_revision"
          :mission-id="scope.mission.id"
          :catalog-revision-id="value.catalog_revision.id"
        />
        <ApPanel index="F3" title="Technical details">
          <ApKeyValue :items="details(value)" :columns="2" />
        </ApPanel>
      </template>
    </ApRemote>
  </div>
</template>
