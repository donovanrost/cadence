<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApEmptyState, ApPageHeader, ApPanel, ApRemote } from "@/ui";
import ImportRunBody from "./ImportRunBody.vue";
import { fetchImportRun } from "./importRun.ts";

/** S3 · Catalog import: validation + diagnostics (+ diff when the server has one). */
const route = useRoute();
const scope = useMissionScope();
const importId = computed(() =>
  typeof route.params.importId === "string" && route.params.importId ? route.params.importId : null,
);
const key = computed(() =>
  importId.value ? { missionId: scope.value.mission.id, importId: importId.value } : null,
);
const { state, refetch } = useRemoteQuery(key, fetchImportRun);
useMissionInvalidation(
  computed(() => scope.value.mission.id),
  ["catalog"],
  refetch,
);

const title = computed(() => {
  const s = state.value;
  if (s.status !== "ready") return "Catalog import";
  const rev = s.value.revision;
  const base = s.value.base_revision;
  if (rev && base) return `Catalog rev ${base.number} → rev ${rev.number}`;
  return rev ? `Catalog rev ${rev.number}` : "Catalog import";
});
const crumbs = computed(() => [
  { label: "Catalog", to: { name: "setup.catalog" } },
  { label: state.value.status === "ready" ? state.value.value.file.name : "Import" },
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader :title="title" size="reading" />
    <ApPanel v-if="!importId" index="B1" title="Source file" flush>
      <ApEmptyState
        state="off"
        headline="Upload isn't available in the console yet"
        sentence="The upload endpoint is being built. Import runs started elsewhere show here with their validation."
      />
    </ApPanel>
    <ApRemote v-else :state="state" loading-label="Loading import…" @retry="refetch">
      <template #default="{ value }"><ImportRunBody :run="value" /></template>
    </ApRemote>
  </div>
</template>
