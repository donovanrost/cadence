<script setup lang="ts">
import { sourceLabel, valueText, type SettingsField, type SettingsScope } from "./api.ts";

/** Read-only values with where each comes from (viewers, locked sections). */
defineProps<{ fields: readonly SettingsField[]; scope: SettingsScope["kind"] }>();
</script>

<template>
  <dl class="m-0 grid grid-cols-1 gap-px bg-hairline md:grid-cols-2">
    <div v-for="f in fields" :key="f.path" class="flex flex-col gap-1 bg-panel px-4 py-3">
      <dt class="ap-label">{{ f.label }}</dt>
      <dd
        class="m-0 font-mono text-md"
        :class="f.source === scope ? 'text-readout' : 'text-text-3'"
      >
        {{ valueText(f) }}
      </dd>
      <dd class="m-0 font-mono text-xs text-text-4 uppercase">{{ sourceLabel(f, scope) }}</dd>
      <dd v-if="f.help" class="m-0 text-sm text-text-3">{{ f.help }}</dd>
    </div>
  </dl>
</template>
