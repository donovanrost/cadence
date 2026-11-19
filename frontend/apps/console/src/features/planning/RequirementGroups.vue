<script setup lang="ts">
import { SchemaForm, type FormValues } from "@/features/changes/index.ts";
import { ApPanel } from "@/ui";
import { schemaGroups } from "./requirements.ts";
import type { TemplateSchema } from "./templates.ts";

/** The requirement form's groups (Window, then Requirement), advanced fields collapsed (ux P4). */
defineProps<{ schema: TemplateSchema; errors: Readonly<Record<string, string>> }>();
const values = defineModel<FormValues>({ required: true });
// keyed-by-text: schema group keys, an open set from the server's form layout; an unknown group shows its key
const titles: Readonly<Record<string, string>> = { window: "Window", requirement: "Requirement" };
</script>

<template>
  <ApPanel
    v-for="(g, i) in schemaGroups(schema)"
    :key="g.key"
    :index="`Q${i + 1}`"
    :title="titles[g.key] ?? g.key"
  >
    <SchemaForm
      v-if="g.fields.length > 0"
      v-model="values"
      :schema="{ kind: 'requirement', fields: g.fields }"
      :errors="errors"
    />
    <!-- a11y A6: an error on an Advanced field opens it, so the error isn't hidden. -->
    <details
      v-if="g.advanced.length > 0"
      class="mt-3"
      :open="g.advanced.some((f) => errors[f.path] !== undefined) || undefined"
    >
      <summary class="ap-label cursor-pointer">Advanced</summary>
      <div class="mt-3">
        <SchemaForm
          v-model="values"
          :schema="{ kind: 'requirement', fields: g.advanced }"
          :errors="errors"
        />
      </div>
    </details>
  </ApPanel>
</template>
