<script setup lang="ts">
import { SchemaForm, type FormValues, type SchemaField } from "@/features/changes/index.ts";
import { ApCallout, ApTag } from "@/ui";
import { fieldText, type ProfileField } from "./detail.ts";
import { generationNote } from "./present.ts";

/** Add override's value: the schema field, the profile's value under it, and any override it replaces. */
defineProps<{
  field: SchemaField;
  profileField: ProfileField;
  errors: Readonly<Record<string, string>>;
  /** "EARENDIL-001 already overrides this: …", or null. */
  existing: string | null;
}>();
const values = defineModel<FormValues>({ required: true });
</script>

<template>
  <SchemaForm
    v-model="values"
    :schema="{ kind: 'spacecraft_override', fields: [field] }"
    :errors="errors"
  />
  <p class="m-0 flex flex-wrap items-center gap-2 text-sm text-text-3">
    Profile value: {{ fieldText(profileField) }}
    <ApTag
      v-if="profileField.runtime_impact === 'generation'"
      state="caution"
      label="Cancels queued commands"
      :title="generationNote"
    />
  </p>
  <ApCallout v-if="existing" tone="info">{{ existing }}</ApCallout>
</template>
