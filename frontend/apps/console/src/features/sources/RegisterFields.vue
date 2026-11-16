<script setup lang="ts">
import { computed } from "vue";
import { ApField, ApSelect } from "@/ui";
import { choices, needsCredentials, type RegisterDraft } from "./register.ts";
import type { SourceOptions } from "./writes.ts";

/** Register source's fields, in R1's words; changing the kind clears the isolation choice. */
const props = defineProps<{ options: SourceOptions }>();
const draft = defineModel<RegisterDraft>({ required: true });
const c = computed(() => choices(props.options, draft.value.kind));
const set = <K extends keyof RegisterDraft>(key: K, value: RegisterDraft[K]) =>
  (draft.value = { ...draft.value, [key]: value });
</script>

<template>
  <ApField
    :model-value="draft.name"
    label="Name"
    required
    hint="Cadence makes its id from the name."
    @update:model-value="set('name', $event)"
  />
  <ApSelect
    :model-value="draft.logical"
    label="Stores"
    required
    :options="c.logical"
    placeholder="Choose…"
    @update:model-value="set('logical', $event)"
  />
  <ApSelect
    :model-value="draft.kind"
    label="Kind"
    required
    :options="c.kinds"
    placeholder="Choose…"
    @update:model-value="draft = { ...draft, kind: $event, isolation: '' }"
  />
  <ApSelect
    :model-value="draft.isolation"
    label="Isolation"
    required
    :options="c.isolation"
    :disabled="draft.kind === ''"
    placeholder="Choose…"
    @update:model-value="set('isolation', $event)"
  />
  <ApSelect
    :model-value="draft.storage"
    label="Storage"
    required
    :options="c.storages"
    placeholder="Choose…"
    @update:model-value="set('storage', $event)"
  />
  <ApField
    v-if="needsCredentials(options, draft.kind)"
    :model-value="draft.credentials"
    label="Credentials reference"
    required
    mono
    hint="A secret reference, never the secret itself."
    @update:model-value="set('credentials', $event)"
  />
</template>
