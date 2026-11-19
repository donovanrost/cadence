<script setup lang="ts">
import { valueText, type SettingsField } from "./api.ts";

/** Read-only values (viewers, locked or inherited sections); the source tag is on the section. */
defineProps<{ fields: readonly SettingsField[]; inherited?: boolean }>();
</script>

<template>
  <dl class="m-0 grid grid-cols-1 gap-px bg-hairline md:grid-cols-2">
    <div v-for="f in fields" :key="f.path" class="flex flex-col gap-1 bg-panel px-4 py-3">
      <dt class="ap-label">{{ f.label }}</dt>
      <dd class="m-0 font-mono text-md" :class="inherited ? 'text-text-4' : 'text-readout'">
        {{ valueText(f) }}
      </dd>
      <dd v-if="f.help" class="m-0 text-sm text-text-3">{{ f.help }}</dd>
    </div>
  </dl>
</template>
