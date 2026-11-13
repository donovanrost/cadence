<script setup lang="ts">
import type { TemplateRow } from "./api.ts";

/**
 * P4 "From templates": the templates, each linking to its page. ux wants a count per day per
 * template ("Block 1 daily · 1,500 for 11-14"); that waits on api's grouped read.
 */
defineProps<{ templates: readonly TemplateRow[] }>();
</script>

<template>
  <ul class="m-0 flex list-none flex-col p-0 py-2">
    <li v-for="t in templates" :key="t.id" class="px-4 py-2">
      <RouterLink
        :to="{ name: 'setup.contact-planning.template', params: { templateId: t.id } }"
        class="font-semibold text-readout hover:underline"
        >{{ t.name }}</RouterLink
      >
    </li>
    <li v-if="templates.length === 0" class="px-4 py-2 text-md text-text-3">No templates.</li>
  </ul>
</template>
