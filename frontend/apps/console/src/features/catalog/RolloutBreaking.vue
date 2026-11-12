<script setup lang="ts">
import { ApCallout, plural } from "@/ui";

/** ux C3: breaking changes can't be fixed here yet (C2), so they're checked, not a dead end. */
defineProps<{ revisionNumber: number; breaking: number }>();
const acknowledged = defineModel<boolean>({ required: true });
</script>

<template>
  <ApCallout tone="caution">
    Rev {{ revisionNumber }} changes {{ breaking }} commands or points in ways that break existing
    use. Cadence can't tell yet what uses them.
  </ApCallout>
  <label class="flex items-center gap-2 text-md text-readout">
    <input v-model="acknowledged" type="checkbox" class="size-4 accent-[var(--color-readout)]" />
    I've checked the {{ plural(breaking, "breaking change") }}
  </label>
</template>
