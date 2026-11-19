<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import {
  ApBreadcrumb,
  ApButton,
  ApCallout,
  ApKeyValue,
  ApPageHeader,
  ApPanel,
  ApRemote,
  type ApCrumb,
} from "@/ui";
import ArtifactRevisions from "./ArtifactRevisions.vue";
import {
  artifactLine,
  fetchArtifact,
  reimportArtifact,
  reimportFailure,
  runningRun,
  type ArtifactPage,
} from "./artifact.ts";
import ImportRunsPanel from "./ImportRunsPanel.vue";

/** L18 Catalog › source file: what was uploaded, what it made, Import again, Download. */
const props = defineProps<{ artifactId: string }>();
const router = useRouter();
const scope = useMissionScope();
const key = computed(() => ({ missionId: scope.value.mission.id, artifactId: props.artifactId }));
const page = useRemoteQuery(key, fetchArtifact);
const busy = ref(false);
const failure = ref<{ text: string; runId: string | null } | null>(null);
const crumbs: readonly ApCrumb[] = [
  { label: "Catalog", to: { name: "setup.catalog" } },
  { label: "Source file" },
];
const details = (a: ArtifactPage["artifact"]) => [
  { key: "sha", label: "SHA-256", value: a.sha256, mono: true },
  { key: "db", label: "Database", value: a.database.name },
  { key: "media", label: "Media type", value: a.media_type ?? "Not recorded", mono: true },
];
const toRun = (importId: string) =>
  router.push({ name: "setup.catalog.import", params: { importId } });

async function again() {
  if (busy.value) return;
  busy.value = true;
  try {
    const r = await reimportArtifact(key.value);
    if (r.ok) return void (await toRun(r.value.import_run.id));
    failure.value = { text: reimportFailure(r.error), runId: runningRun(r.error) };
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1000px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApRemote :state="page.state.value" loading-label="Loading source file…" @retry="page.refetch">
      <template #default="{ value }">
        <ApPageHeader
          :label="`${scope.mission.name} · catalog · source file`"
          :title="value.artifact.file_name"
          size="reading"
        >
          <template #subtitle
            ><span class="text-sm text-text-2">{{ artifactLine(value.artifact) }}</span></template
          >
          <ApButton :href="value.artifact.download_url">Download</ApButton>
          <ApButton
            v-if="value.permissions.includes('catalog.import')"
            variant="primary"
            :disabled="busy"
            disabled-reason="Starting…"
            @click="again"
            >Import again</ApButton
          >
        </ApPageHeader>
        <p v-if="value.permissions.includes('catalog.import')" class="m-0 text-sm text-text-3">
          Import again runs the importer on this file and makes a new candidate revision. Nothing
          changes on spacecraft until you roll it out.
        </p>
        <ApCallout v-if="failure" tone="caution"
          >{{ failure.text }}
          <template v-if="failure.runId" #action
            ><ApButton size="compact" @click="toRun(failure.runId)">Open it</ApButton></template
          >
        </ApCallout>
        <ArtifactRevisions
          :revisions="value.revisions"
          :match="
            value.import_runs.find((r) => r.matched && r.revision_number === null)?.matched ??
            undefined
          "
        />
        <ImportRunsPanel :runs="value.import_runs" />
        <ApPanel index="F3" title="Technical details">
          <ApKeyValue :items="details(value.artifact)" :columns="2">
            <!-- A hash has no break points: let it wrap inside its column. -->
            <template #value-sha
              ><span class="[overflow-wrap:anywhere]">{{ value.artifact.sha256 }}</span></template
            >
          </ApKeyValue>
        </ApPanel>
      </template>
    </ApRemote>
  </div>
</template>
