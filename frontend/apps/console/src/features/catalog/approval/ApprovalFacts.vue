<script setup lang="ts">
import { ApStatusMark } from "@/ui";
import type { ModelRevision } from "./api.ts";
import { importerLine } from "./words.ts";

/** U65: who imported it (or that nobody knows) and whether its runtime plans are ready. */
defineProps<{ revision: ModelRevision }>();
</script>

<template>
  <ul class="m-0 flex list-none flex-col gap-1 p-0 text-md text-text-2">
    <li v-if="importerLine(revision)">{{ importerLine(revision) }}</li>
    <li v-else>
      <span class="inline-flex items-center gap-1.5 text-caution-text"
        ><ApStatusMark state="caution" />Importer not recorded</span
      >
      · Cadence doesn't know who imported this revision.
    </li>
    <li>
      Runtime plans:
      <span v-if="revision.plans_ready">Ready</span>
      <span v-else class="inline-flex items-center gap-1.5 text-caution-text"
        ><ApStatusMark state="caution" />Not ready yet</span
      >
    </li>
  </ul>
</template>
