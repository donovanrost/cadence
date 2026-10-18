<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { ref, watch } from "vue";
import { usageSummaryText, type UsageSummary } from "../../shared/usage-summary";
import CatalogUploadForm from "./CatalogUploadForm.vue";
import StatusBadge from "../../shared/StatusBadge.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import CadenceCollapsible from "@cadence/ui/CadenceCollapsible.vue";
import CadenceCollapsibleContent from "@cadence/ui/CadenceCollapsibleContent.vue";

type NavigationItem = {
  label: string;
  href: string;
};

type Navigation = {
  mission: NavigationItem;
  catalog: NavigationItem;
  current: { label: string };
};

type CatalogDatabase = {
  id: string;
  name: string;
  slug: string;
  description: string;
  spacecraft_usage: UsageSummary;
};

type Revision = {
  id: string;
  revision_id: string;
  label: string;
  number: number;
  spacecraft_usage: UsageSummary;
  mission_model_revision_id: string;
  href: string;
};

type ImportRun = {
  id: string;
  run_id: string;
  status: {
    value: string;
    label: string;
    tone: "info" | "ready" | "blocked";
  };
  href: string;
};

type CatalogUploadFormProps = InstanceType<typeof CatalogUploadForm>["$props"];

const props = defineProps<{
  database: CatalogDatabase;
  navigation: Navigation;
  revision_form_open: boolean;
  revision_form: CatalogUploadFormProps["form"];
  upload: CatalogUploadFormProps["upload"];
  detected_importer: CatalogUploadFormProps["detected_importer"];
  submit_disabled: boolean;
  revisions: Revision[];
  import_runs: ImportRun[];
}>();

const revisionFormOpen = ref(props.revision_form_open);
watch(
  () => props.revision_form_open,
  (open) => {
    revisionFormOpen.value = open;
  },
);

const emit = defineEmits<{
  "toggle-revision-form": [payload: Record<string, never>];
  validate: [payload: Record<string, Record<string, string>>];
  save: [];
  "cancel-upload": [payload: { ref: string }];
}>();

const requestRevisionFormChange = (open: boolean) => {
  revisionFormOpen.value = open;
  emit("toggle-revision-form", {});
};
useManagementHeader("/missions/:mission_id/catalog/databases/:catalog_database_id", () => ({
  title: props.database.name,
  identifier: props.database.slug,
  primary: {
    id: "add-revision-toggle",
    label: revisionFormOpen.value ? "Cancel" : "Add revision",
    ...(revisionFormOpen.value ? {} : { icon: "hero-plus" as const }),
    run: () => requestRevisionFormChange(!revisionFormOpen.value),
  },
}));
</script>

<template>
  <CadenceCollapsible
    content-id="catalog-revision-upload-slot"
    :open="revisionFormOpen"
    @request-change="requestRevisionFormChange"
  >
    <div id="catalog-database-show-surface" class="space-y-6">
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <CadenceCard
          class="card border border-base-300 bg-base-200 lg:col-span-2"
          body-class="card-body p-6"
        >
          <p class="hud-label">Database</p>
          <p class="mt-2 text-sm text-base-content/70">{{ database.description }}</p>
        </CadenceCard>

        <CadenceCard class="card border border-base-300 bg-base-200" body-class="card-body p-6">
          <p class="hud-label">Spacecraft usage</p>
          <p id="catalog-spacecraft-usage-summary" class="mt-2 text-sm text-base-content/60">
            {{ usageSummaryText(database.spacecraft_usage) }}
          </p>
          <p class="mt-2 text-xs text-base-content/60">
            Across all revisions. One spacecraft may have both an active and a saved configuration.
          </p>
        </CadenceCard>
      </div>

      <CadenceCollapsibleContent>
        <div>
          <CatalogUploadForm
            :form="revision_form"
            :upload="upload"
            :detected_importer="detected_importer"
            :submit_disabled="submit_disabled"
            @validate="emit('validate', $event)"
            @save="emit('save')"
            @cancel-upload="emit('cancel-upload', $event)"
          />
        </div>
      </CadenceCollapsibleContent>

      <CadenceCard
        id="catalog-revision-history"
        class="card border border-base-300 bg-base-200"
        body-class="card-body p-6"
      >
        <p class="hud-label">Revision history</p>
        <p
          v-if="revisions.length === 0"
          id="catalog-revisions-empty-state"
          class="text-sm text-base-content/60"
        >
          No revisions yet.
        </p>
        <CadenceTableFrame v-else id="catalog-revisions-table">
          <thead>
            <tr>
              <th class="hud-label">Revision</th>
              <th class="hud-label">Spacecraft usage</th>
              <th class="hud-label text-right">Actions</th>
            </tr>
          </thead>
          <tbody id="catalog-revisions-table-body">
            <tr v-for="revision in revisions" :id="revision.id" :key="revision.revision_id">
              <td>
                <p class="font-medium">{{ revision.label }}</p>
                <p class="font-mono text-xs text-base-content/60">#{{ revision.number }}</p>
              </td>
              <td>
                <span :id="`${revision.id}-usage`" class="text-sm">{{
                  usageSummaryText(revision.spacecraft_usage)
                }}</span>
              </td>
              <td class="text-right">
                <a
                  :href="revision.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="btn btn-ghost btn-xs"
                  >View revision</a
                >
              </td>
            </tr>
          </tbody>
        </CadenceTableFrame>
      </CadenceCard>

      <CadenceCard
        id="catalog-import-attempts"
        class="card border border-base-300 bg-base-200"
        body-class="card-body p-6"
      >
        <p class="hud-label">Import attempts</p>
        <p
          v-if="import_runs.length === 0"
          id="catalog-import-runs-empty-state"
          class="text-sm text-base-content/60"
        >
          No import attempts yet.
        </p>
        <CadenceTableFrame v-else id="catalog-import-runs-table">
          <thead>
            <tr>
              <th class="hud-label">Status</th>
              <th class="hud-label">Run</th>
              <th class="hud-label text-right">Actions</th>
            </tr>
          </thead>
          <tbody id="catalog-import-runs-table-body">
            <tr v-for="run in import_runs" :id="run.id" :key="run.run_id">
              <td>
                <StatusBadge :status="run.status.tone" :label="run.status.label" />
              </td>
              <td class="font-mono text-xs text-base-content/60">{{ run.run_id }}</td>
              <td class="text-right">
                <a
                  :href="run.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="btn btn-ghost btn-xs"
                  >View run</a
                >
              </td>
            </tr>
          </tbody>
        </CadenceTableFrame>
      </CadenceCard>
    </div>
  </CadenceCollapsible>
</template>
