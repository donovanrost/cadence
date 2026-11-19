<script setup lang="ts">
import { ApStatTile, formatCount } from "@/ui";
import { kindTile, type ImportRunDetail } from "./importRun.ts";

/** C1 stat strip (Catalog.md:34): Declarations · Commands · Telemetry · Unchanged · Breaking. */
defineProps<{ run: ImportRunDetail }>();
</script>

<template>
  <div
    class="grid w-fit auto-cols-[minmax(150px,220px)] grid-flow-col gap-px border border-hairline bg-hairline"
  >
    <!-- api: the importer's own count of what it read from the file, not a model total. -->
    <ApStatTile label="Declarations" :value="run.declaration_count" caption="read from this file" />
    <template v-if="run.diff">
      <ApStatTile
        v-if="run.diff.summary.commands"
        label="Commands"
        v-bind="kindTile(run.diff.summary.commands)"
      />
      <ApStatTile
        v-if="run.diff.summary.telemetry"
        label="Telemetry"
        v-bind="kindTile(run.diff.summary.telemetry)"
      />
      <ApStatTile
        label="Unchanged"
        :value="run.diff.summary.unchanged"
        :caption="`of ${formatCount(run.diff.summary.total_before)} commands and telemetry`"
      />
      <ApStatTile
        v-if="run.diff.summary.breaking != null"
        label="Breaking"
        :value="run.diff.summary.breaking"
        :state="run.diff.summary.breaking > 0 ? 'caution' : 'neutral'"
      />
    </template>
  </div>
</template>
