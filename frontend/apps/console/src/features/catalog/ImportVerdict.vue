<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApCallout, plural } from "@/ui";
import DiagnosticsPanel from "./DiagnosticsPanel.vue";
import { severityCounts, type ImportRunDetail } from "./importRun.ts";

/**
 * The run's verdict (Catalog.md § C): failed → crit + the Diagnostics table; valid with warnings →
 * a caution callout with `Show N warnings` that expands the same table; clean → nominal.
 */
const props = defineProps<{ run: ImportRunDetail }>();
const counts = computed(() => severityCounts(props.run.diagnostics));
const open = ref(false);
const issues = computed(() =>
  [
    counts.value.error > 0 ? plural(counts.value.error, "error") : null,
    counts.value.warning > 0 ? plural(counts.value.warning, "warning") : null,
  ]
    .filter(Boolean)
    .join(" and "),
);
</script>

<template>
  <ApCallout v-if="run.status === 'running'" tone="info"
    >Parsing and validating… This page updates when it finishes.</ApCallout
  >
  <template v-else-if="run.status === 'failed'">
    <ApCallout tone="crit">
      This file can't be imported<template v-if="counts.error > 0"
        >: {{ plural(counts.error, "error") }}</template
      >. {{ run.failure_reason ?? "" }}
    </ApCallout>
    <DiagnosticsPanel v-if="run.diagnostics.length > 0" :diagnostics="run.diagnostics" index="C4" />
  </template>
  <template v-else-if="counts.error + counts.warning > 0">
    <ApCallout tone="caution">
      Imported with {{ issues }}. Parts of the file Cadence doesn't support were skipped.
      <ApButton size="compact" variant="ghost" :aria-expanded="open" @click="open = !open">{{
        open ? "Hide them" : `Show ${issues}`
      }}</ApButton>
    </ApCallout>
    <DiagnosticsPanel v-if="open" :diagnostics="run.diagnostics" index="C4" />
  </template>
  <ApCallout v-else tone="nominal">Parsed and validated, no schema errors.</ApCallout>
</template>
