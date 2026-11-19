<script setup lang="ts">
import { ApCallout, plural } from "@/ui";

/**
 * ux C3: breaking changes can't be fixed here yet (C2), so they're checked, not a dead end.
 * `breaking` null: the count isn't on this read (U102's fallback), so the diff is checked instead.
 */
defineProps<{ revisionNumber: number; breaking: number | null }>();
const acknowledged = defineModel<boolean>({ required: true });
</script>

<template>
  <ApCallout tone="caution">
    <template v-if="breaking === null"
      >This page can't show whether rev {{ revisionNumber }} breaks anything in use. Check its
      import's diff before you stage.</template
    >
    <template v-else
      >Rev {{ revisionNumber }} changes {{ breaking }} commands or points in ways that break
      existing use. Cadence can't tell yet what uses them.</template
    >
  </ApCallout>
  <label class="flex items-center gap-2 text-md text-readout">
    <input v-model="acknowledged" type="checkbox" class="size-4 accent-[var(--color-readout)]" />
    <template v-if="breaking === null">I've checked rev {{ revisionNumber }}'s diff</template>
    <template v-else>I've checked the {{ plural(breaking, "breaking change") }}</template>
  </label>
</template>
