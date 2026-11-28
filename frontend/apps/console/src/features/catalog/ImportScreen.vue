<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApButton, ApPageHeader, ApRemote, type ApCrumb } from "@/ui";
import ImportRunBody from "./ImportRunBody.vue";
import UploadPanel from "./UploadPanel.vue";
import { fetchCatalogIndex } from "./api.ts";
import { fetchImporters } from "./upload.ts";
import { fetchImportRun } from "./importRun.ts";

/** S3 · Catalog import: validation + diagnostics (+ diff when the server has one). */
const route = useRoute("setup.catalog.import");
const scope = useMissionScope();
const importId = computed(() =>
  typeof route.params.importId === "string" && route.params.importId ? route.params.importId : null,
);
const key = computed(() =>
  importId.value ? { missionId: scope.value.mission.id, importId: importId.value } : null,
);
const { state, refetch } = useRemoteQuery(key, fetchImportRun);
/** #1160: a new import is the upload's check (`catalog.import`, any mission operator). */
const canImport = computed(
  () => state.value.status === "ready" && state.value.value.permissions.includes("catalog.import"),
);
// Upload form data (only when no import run is selected).
const uploadKey = computed(() => (importId.value ? null : scope.value.mission.id));
const importers = useRemoteQuery(uploadKey, fetchImporters);
const index = useRemoteQuery(
  () => (uploadKey.value ? { missionId: uploadKey.value, databaseId: null } : null),
  fetchCatalogIndex,
);
useMissionInvalidation(
  computed(() => scope.value.mission.id),
  ["catalog"],
  refetch,
);

const title = computed(() => {
  const s = state.value;
  if (!importId.value) return "Import a catalog";
  if (s.status !== "ready") return "Catalog import";
  const rev = s.value.revision;
  const base = s.value.base_revision;
  if (rev && base) return `Catalog rev ${base.number} → rev ${rev.number}`;
  return rev ? `Catalog rev ${rev.number}` : "Catalog import";
});
const crumbs = computed((): readonly ApCrumb[] => [
  { label: "Catalog", to: { name: "setup.catalog" } },
  { label: state.value.status === "ready" ? state.value.value.file.name : "Import" },
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader :title="title" size="reading">
      <!-- Catalog.md § C: a different file starts a new import; this run stays in the history. -->
      <ApButton
        v-if="importId && canImport && state.status === 'ready' && state.value.status !== 'running'"
        :to="{ name: 'setup.catalog.import' }"
        >Replace file</ApButton
      >
    </ApPageHeader>
    <template v-if="!importId">
      <ApRemote
        :state="importers.state.value"
        loading-label="Loading importers…"
        @retry="importers.refetch"
      >
        <template #default="{ value: accepted }">
          <ApRemote
            :state="index.state.value"
            loading-label="Loading catalog…"
            @retry="index.refetch"
          >
            <template #default="{ value: catalog }">
              <UploadPanel :mission-id="scope.mission.id" :index="catalog" :importers="accepted" />
            </template>
          </ApRemote>
        </template>
      </ApRemote>
    </template>
    <ApRemote v-else :state="state" loading-label="Loading import…" @retry="refetch">
      <template #default="{ value }"><ImportRunBody :run="value" /></template>
    </ApRemote>
  </div>
</template>
