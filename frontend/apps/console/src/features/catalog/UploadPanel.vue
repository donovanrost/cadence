<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, useId } from "vue";
import { useRouter } from "vue-router";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApChip, ApField, ApPanel, ApSelect } from "@/ui";
import type { CatalogIndex } from "./api.ts";
import { formatMiB, precheck, uploadCatalog, type Importers } from "./upload.ts";

/** B · Upload: one file, the database it revises (or a new one), label and notes. */
const props = defineProps<{ missionId: MissionId; index: CatalogIndex; importers: Importers }>();
const router = useRouter();
const file = ref<File | null>(null);
const databaseId = ref<string>(props.index.database?.id ?? "new");
const newName = ref("");
const label = ref("");
const notes = ref("");
const busy = ref(false);
const failure = ref<string | null>(null);

const databases = computed(() => [
  ...props.index.databases.map((d) => ({ value: d.id, label: d.name })),
  { value: "new", label: "New catalog database…" },
]);
const fileProblem = computed(() => (file.value ? precheck(file.value, props.importers) : null));
/** #244 (A6): the file's type/size problem is the file input's description while it stands. */
const problemId = useId();
const blocked = computed(() => {
  if (!file.value) return "Choose a file.";
  if (fileProblem.value) return fileProblem.value;
  if (databaseId.value === "new" && newName.value.trim() === "")
    return "Name the new catalog database.";
  return null;
});

function choose(event: Event) {
  const input = event.target;
  file.value = input instanceof HTMLInputElement ? (input.files?.[0] ?? null) : null;
}

async function upload() {
  if (blocked.value !== null || !file.value || busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const target =
      databaseId.value === "new"
        ? { newName: newName.value.trim() }
        : { databaseId: databaseId.value };
    const result = await uploadCatalog(props.missionId, {
      file: file.value,
      target,
      revisionLabel: label.value,
      revisionNotes: notes.value,
    });
    if (result.ok)
      await router.push({
        name: "setup.catalog.import",
        params: { importId: result.value.import_run_id },
      });
    else failure.value = failureOutcome(result.error, "changed").sentence;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="B1" title="Source file">
    <form class="flex flex-col gap-4" @submit.prevent="upload">
      <label
        class="flex min-h-40 cursor-pointer flex-col items-center justify-center gap-2 border border-dashed border-line bg-vacuum px-4 py-6 text-center focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-readout"
      >
        <span class="text-base text-readout">{{
          file ? file.name : "Choose an XTCE or catalog export"
        }}</span>
        <span class="text-sm text-text-3">Up to {{ formatMiB(importers.max_bytes) }}</span>
        <input
          type="file"
          class="sr-only"
          :aria-describedby="fileProblem ? problemId : undefined"
          :aria-invalid="fileProblem ? 'true' : undefined"
          :accept="importers.importers.flatMap((i) => i.extensions).join(',')"
          @change="choose"
        />
      </label>
      <div class="flex flex-wrap gap-2">
        <ApChip v-for="i in importers.importers" :key="i.key" :name="i.extensions.join(' ')">{{
          i.label
        }}</ApChip>
      </div>
      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <ApSelect v-model="databaseId" label="Catalog database" :options="databases" />
        <ApField v-if="databaseId === 'new'" v-model="newName" label="New database name" required />
        <ApField v-model="label" label="Revision label" placeholder="e.g. FSW 3.2.0" />
        <ApField v-model="notes" label="Notes" />
      </div>
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
      <ApCallout v-else-if="fileProblem" :id="problemId" tone="caution">{{
        fileProblem
      }}</ApCallout>
      <ApButton
        type="submit"
        variant="primary"
        size="commit"
        :disabled="blocked !== null || busy"
        :disabled-reason="blocked ?? 'Uploading…'"
      >
        {{ busy ? "Uploading…" : "Upload and validate" }}
      </ApButton>
    </form>
  </ApPanel>
</template>
