<script setup lang="ts">
import { computed } from "vue";
import { ApCallout, plural } from "@/ui";
import DiagnosticsPanel from "./DiagnosticsPanel.vue";
import DiffPanel from "./DiffPanel.vue";
import DiffStrip from "./DiffStrip.vue";
import { formatBytes, severityCounts, type ImportRunDetail } from "./importRun.ts";

/** File line, verdict, stats, diff (when available) and diagnostics for one import run. */
const props = defineProps<{ run: ImportRunDetail }>();
const counts = computed(() => severityCounts(props.run.diagnostics));
const fileLine = computed(() =>
  [
    props.run.file.name,
    props.run.file.format_label,
    props.run.file.size_bytes === null ? null : formatBytes(props.run.file.size_bytes),
  ]
    .filter((p): p is string => p !== null)
    .join(" · "),
);
</script>

<template>
  <p class="m-0 text-md text-text-3">
    <span class="font-mono text-readout">{{ fileLine }}</span>
  </p>
  <ApCallout v-if="run.status === 'running'" tone="info"
    >Parsing and validating… This page updates when it finishes.</ApCallout
  >
  <ApCallout v-else-if="run.status === 'failed'" tone="crit">
    This file can't be imported<template v-if="counts.error > 0"
      >: {{ plural(counts.error, "error") }}</template
    >.
    {{ run.failure_reason ?? "" }}
  </ApCallout>
  <ApCallout v-else-if="counts.error + counts.warning > 0" tone="caution">
    Imported with
    {{
      [
        counts.error > 0 ? plural(counts.error, "error") : null,
        counts.warning > 0 ? plural(counts.warning, "warning") : null,
      ]
        .filter(Boolean)
        .join(" and ")
    }}. Unsupported items were skipped; see the diagnostics.
  </ApCallout>
  <ApCallout v-else tone="nominal">Parsed and validated, no schema errors.</ApCallout>
  <DiffStrip v-if="run.status === 'succeeded'" :run="run" />
  <DiffPanel v-if="run.diff" :diff="run.diff" :base-number="run.base_revision?.number ?? null" />
  <ApCallout v-else-if="run.status === 'succeeded'" tone="info">{{
    run.base_revision
      ? `This revision couldn't be compared with r${run.base_revision.number}, so there's no diff.`
      : "This is the database's first revision, so there's nothing to compare it with."
  }}</ApCallout>
  <DiagnosticsPanel v-if="run.diagnostics.length > 0" :diagnostics="run.diagnostics" index="C4" />
</template>
