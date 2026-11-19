<script setup lang="ts">
import { ApCallout } from "@/ui";
import type { Breaking, BreakingWords } from "./breaking.ts";

/** ux C3, U102: breaking changes can't be fixed here yet (C2), so they're checked, not a dead end. */
defineProps<{ breaking: Breaking; words: BreakingWords }>();
const acknowledged = defineModel<boolean>({ required: true });
</script>

<template>
  <ApCallout tone="caution">
    {{ words.line }}
    <RouterLink
      v-if="breaking.kind === 'unknown' && breaking.importRunId"
      :to="{ name: 'setup.catalog.import', params: { importId: breaking.importRunId } }"
      class="text-readout hover:text-bright max-md:hit-44"
      >Open its import</RouterLink
    >
  </ApCallout>
  <label class="flex items-center gap-2 text-md text-readout">
    <input v-model="acknowledged" type="checkbox" class="size-4 accent-[var(--color-readout)]" />
    {{ words.checkbox }}
  </label>
</template>
