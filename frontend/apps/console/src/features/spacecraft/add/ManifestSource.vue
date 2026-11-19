<script setup lang="ts">
import { computed, ref } from "vue";
import { ApCallout, ApSelect, formatCount, plural, type ApSelectOption } from "@/ui";
import { useDraft } from "./context.ts";
import {
  fieldLabels,
  guessMapping,
  manifestFields,
  manifestTemplate,
  parseCsv,
} from "./manifest.ts";
import type { ManifestField } from "./manifest.ts";

/** Manifest CSV: choose a file, check the column mapping. Parsing happens in the browser. */
const { draft, set } = useDraft();
const readError = ref<string | null>(null);
const templateHref = `data:text/csv;charset=utf-8,${encodeURIComponent(manifestTemplate())}`;

async function choose(event: Event) {
  const input = event.target;
  const file = input instanceof HTMLInputElement ? input.files?.[0] : undefined;
  if (!file) return;
  try {
    const parsed = parseCsv(await file.text());
    if (!parsed.ok) {
      readError.value = parsed.message;
      return;
    }
    readError.value = null;
    const header = [...parsed.header];
    const rows = parsed.rows.map((r) => [...r]);
    set("manifest", { fileName: file.name, header, rows, mapping: guessMapping(header) });
  } catch {
    readError.value = "The file could not be read.";
  }
}

const columnOptions = computed((): readonly ApSelectOption<string>[] => [
  { value: "none", label: "Not in file" },
  ...(draft.manifest?.header ?? []).map((h, i) => ({
    value: String(i),
    label: h || `Column ${i + 1}`,
  })),
]);

function remap(field: ManifestField, value: string) {
  const m = draft.manifest;
  if (!m) return;
  set("manifest", {
    ...m,
    mapping: { ...m.mapping, [field]: value === "none" ? null : Number(value) },
  });
}
</script>

<template>
  <div class="flex flex-col gap-3">
    <label class="flex flex-col gap-1.5">
      <span class="ap-label">Manifest CSV</span>
      <input type="file" accept=".csv,text/csv" class="text-md text-text-3" @change="choose" />
    </label>
    <a :href="templateHref" download="manifest-template.csv" class="text-sm text-text-3"
      >Download manifest template (.csv)</a
    >
    <ApCallout v-if="readError" tone="caution">{{ readError }}</ApCallout>
    <template v-if="draft.manifest">
      <p class="m-0 text-md text-text-3">
        <span class="font-mono text-readout">{{ draft.manifest.fileName }}</span> ·
        {{ plural(draft.manifest.rows.length, "row") }} ·
        {{ formatCount(manifestFields.filter((f) => draft.manifest?.mapping[f] !== null).length) }}
        of {{ manifestFields.length }} fields mapped
      </p>
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-3">
        <ApSelect
          v-for="field in manifestFields"
          :key="field"
          :label="`${fieldLabels[field]} column`"
          :options="columnOptions"
          :model-value="String(draft.manifest.mapping[field] ?? 'none')"
          @update:model-value="remap(field, $event)"
        />
      </div>
    </template>
  </div>
</template>
